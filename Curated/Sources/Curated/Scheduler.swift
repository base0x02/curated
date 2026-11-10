import Foundation

/// The scheduled download is a per-user LaunchAgent that runs this executable with --scheduled-download at each of
/// `settings.scheduleTimes`, so it works even when the app isn't open. If the Mac is asleep at those times, launchd
/// runs it once on wake.
enum Scheduler {
    static let label = "local.curated.download"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func sync(_ settings: AppSettings) {
        // A test run with its own data dir must never repoint the real overnight job.
        guard Paths.dataDirOverride == nil, let executable = Bundle.main.executablePath else { return }
        launchctl(["bootout", "gui/\(getuid())/\(label)"])

        guard settings.scheduleEnabled else {
            try? FileManager.default.removeItem(at: plistURL)
            return
        }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "--scheduled-download"],
            "StartCalendarInterval": Set(settings.scheduleTimes).map { ["Hour": $0.hour, "Minute": $0.minute] },
            "StandardOutPath": Paths.logs.appendingPathComponent("scheduled.log").path,
            "StandardErrorPath": Paths.logs.appendingPathComponent("scheduled.log").path,
            "ProcessType": "Background",
        ]
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        } catch {
            NSLog("Curated: failed to install schedule: \(error)")
        }
    }

    /// Takes the overnight job out of launchd and deletes its plist (for Reset Everything). Never from a test run.
    static func remove() {
        guard Paths.dataDirOverride == nil else { return }
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    static func nextRun(_ settings: AppSettings) -> Date? {
        guard settings.scheduleEnabled else { return nil }
        let now = Date()
        return settings.scheduleTimes.compactMap {
            Calendar.current.nextDate(after: now, matching: DateComponents(hour: $0.hour, minute: $0.minute),
                                      matchingPolicy: .nextTime)
        }.min()
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

/// Entry point for the scheduled (headless) run.
enum HeadlessRunner {
    static func run() -> Int32 {
        let lock = DownloadLock()
        guard lock.tryAcquire() else {
            print("\(Date()) Another download is already running; skipping.")
            DownloadLog.info("Scheduled download skipped: another download is already running")
            return 0
        }
        defer { lock.release() }

        let config = Config.load()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            print("\(Date()) Scheduled download for \(config.creators.count) creator(s)")
            DownloadLog.beginRun("Scheduled download", settings: config.settings)
            let log = DownloadLog.tee { print($0) }
            if config.settings.vineEnabled {
                let began = Date()
                let result = await Vine.download(keep: config.settings.vineBatchSize, settings: config.settings,
                                                 runner: ProcessRunner(), log: log)
                DownloadLog.result(Vine.feedID, result, seconds: Date().timeIntervalSince(began))
                RunState.record(result, for: Vine.feedID)
            }
            await DownloadEngine.downloadAll(config.creators, settings: config.settings, runner: ProcessRunner(), log: log)
            let now = Date()
            RunState.update { state in
                state.lastRun = now
                if config.creators.contains(where: \.downloadsShorts) { state.lastShortRun = now }
                if config.creators.contains(where: \.downloadsLongForm) { state.lastLongRun = now }
            }
            print("\(Date()) Finished")
            semaphore.signal()
        }
        semaphore.wait()
        return 0
    }
}
