import Foundation

/// USB sync for Android phones: `adb reverse` makes the phone's own 127.0.0.1:8765 lead to this Mac's sync port
/// over the cable, so a plugged-in phone syncs without Wi-Fi. It opens nothing on the Mac's network.
enum AdbReverse {
    /// The port the Android app tries on 127.0.0.1.
    static let phonePort: UInt16 = 8765
    private static var phoneSpec: String { "tcp:\(phonePort)" }
    private static var macSpec: String { "tcp:\(SyncServer.port)" }
    /// One pass at a time, so a pass started before the toggle flipped can't undo the one after it.
    private static let queue = DispatchQueue(label: "local.curated.adb")

    struct Device: Equatable {
        let serial: String
        let name: String
        /// The phone's sync port currently leads to this Mac.
        var forwarded: Bool
    }

    static let executable: String? = {
        let sdk = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/platform-tools").path
        return (Tools.searchPaths + [sdk]).map { "\($0)/adb" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Adds (or removes) the forwarding on every connected phone and reports each one's state.
    /// A phone already forwarded somewhere else (say, to a test copy) is left alone.
    static func sync(enabled: Bool) async -> [Device] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: syncNow(enabled: enabled)) }
        }
    }

    private static func syncNow(enabled: Bool) -> [Device] {
        guard let adb = executable else { return [] }
        // Started on its own with no pipes: a freshly spawned adb server would otherwise hold our pipe open.
        run(adb, ["start-server"], output: false)
        guard let list = run(adb, ["devices", "-l"]) else { return [] }
        var devices: [Device] = []
        for line in list.split(separator: "\n").dropFirst() {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[1] == "device", manages(fields[0]) else { continue }
            let serial = fields[0]
            let name = fields.first { $0.hasPrefix("model:") }
                .map { $0.dropFirst(6).replacingOccurrences(of: "_", with: " ") } ?? serial
            let target = reverseTarget(adb, serial)
            var forwarded = target == macSpec
            if enabled && target == nil {
                forwarded = run(adb, ["-s", serial, "reverse", phoneSpec, macSpec]) != nil
            } else if !enabled && forwarded {
                forwarded = run(adb, ["-s", serial, "reverse", "--remove", phoneSpec]) == nil
            }
            devices.append(Device(serial: serial, name: name, forwarded: forwarded))
        }
        return devices
    }

    /// A test copy on its own port (CURATED_SYNC_PORT) only touches emulators, or ANDROID_SERIAL if set,
    /// so it never takes over a real phone's USB sync.
    private static func manages(_ serial: String) -> Bool {
        if let only = ProcessInfo.processInfo.environment["ANDROID_SERIAL"] { return serial == only }
        return SyncServer.port == phonePort || serial.hasPrefix("emulator-")
    }

    /// Where the phone's sync port leads on the Mac ("tcp:8765"), or nil if it isn't forwarded.
    private static func reverseTarget(_ adb: String, _ serial: String) -> String? {
        guard let list = run(adb, ["-s", serial, "reverse", "--list"]) else { return nil }
        for line in list.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if let i = fields.firstIndex(of: phoneSpec), i + 1 < fields.count { return fields[i + 1] }
        }
        return nil
    }

    /// Standard output if adb succeeded. Gives up after 10 seconds.
    @discardableResult
    private static func run(_ adb: String, _ arguments: [String], output: Bool = true) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adb)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = output ? pipe : FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let timeout = DispatchWorkItem { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        let data = output ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        p.waitUntilExit()
        timeout.cancel()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

extension AppModel {
    var usbSyncActive: Bool { usbDevices.contains { $0.forwarded } }

    /// Checks connected phones every few seconds while sync is on, since unplugging the cable drops the forwarding.
    /// Turning sync off removes it.
    func updateUsbSync() {
        usbSyncTask?.cancel()
        let syncOn = settings.syncEnabled
        let enabled = syncOn && usbSyncEnabled
        usbSyncTask = Task { [weak self] in
            repeat {
                let devices = await AdbReverse.sync(enabled: enabled)
                guard !Task.isCancelled, let self else { return }
                if usbDevices != devices { usbDevices = devices }
                guard syncOn else { return }
                try? await Task.sleep(for: .seconds(3))
            } while !Task.isCancelled
        }
    }
}
