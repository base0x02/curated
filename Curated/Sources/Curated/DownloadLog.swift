import Foundation

/// How much downloads write to `logs/downloads.log` (Settings → Advanced).
enum LogLevel: String, Codable, CaseIterable, Identifiable {
    /// Each creator's result and every error.
    case normal
    /// Also what each creator's listing found, how long it took, and every error line yt-dlp printed.
    case detailed
    /// Also every command run, with all of its output and its exit status.
    case debug

    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: "Normal"
        case .detailed: "Detailed"
        case .debug: "Debug"
        }
    }
}

/// The download log file, shared by the app and the scheduled job (which also keeps printing to scheduled.log).
/// Every line is timestamped and tagged with its kind. The file is rotated to downloads.1.log at `maxSize`.
enum DownloadLog {
    enum Kind: String { case info = "INFO", error = "ERROR", detail = "DETAIL", debug = "DEBUG" }

    static var file: URL { Paths.logs.appendingPathComponent("downloads.log") }
    static var previousFile: URL { Paths.logs.appendingPathComponent("downloads.1.log") }
    private static let maxSize = 5_000_000

    private static let lock = NSLock()
    nonisolated(unsafe) private static var currentLevel = LogLevel.normal
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static var level: LogLevel {
        get { lock.withLock { currentLevel } }
        set { lock.withLock { currentLevel = newValue } }
    }
    static var showsDetail: Bool { level != .normal }
    static var showsDebug: Bool { level == .debug }

    static func info(_ line: String) { write(.info, line) }
    static func error(_ line: String) { write(.error, line) }
    static func detail(_ line: @autoclosure () -> String) { if showsDetail { write(.detail, line()) } }
    static func debug(_ line: @autoclosure () -> String) { if showsDebug { write(.debug, line()) } }

    /// The app's and the scheduled job's progress lines, written to the file too.
    static func tee(_ log: @escaping (String) -> Void) -> (String) -> Void {
        { line in info(line); log(line) }
    }

    /// Opens a run: the level from settings, and what's about to happen.
    static func beginRun(_ what: String, settings: AppSettings) {
        level = settings.logLevel
        info("──── \(what)")
        detail("Settings: TikTok cookies \(settings.cookieBrowser.rawValue), YouTube cookies "
               + "\(settings.youtubeCookieBrowser.rawValue), library \(settings.libraryPath), logging \(settings.logLevel.rawValue)")
        detail("yt-dlp: \(Tools.find("yt-dlp") ?? "not found"), ffmpeg: \(Tools.find("ffmpeg") ?? "not found")")
    }

    /// One creator's (or the Vine feed's) outcome; failures are errors so they stand out.
    static func result(_ name: String, _ result: DownloadResult, seconds: TimeInterval) {
        let took = String(format: "%.1fs", seconds)
        if let error = result.error, error != "Cancelled" {
            write(.error, "\(name) failed after \(took): \(error)")
        } else {
            detail("\(name) finished in \(took): \(result.newVideos) new, \(result.removed) removed, "
                   + "\(result.belowMinViews) under min views" + (result.error.map { " (\($0))" } ?? ""))
        }
    }

    static func write(_ kind: Kind, _ line: String) {
        let text = "\(stampFormatter.string(from: Date())) [\(kind.rawValue)] \(line)\n"
        lock.withLock {
            // Opened for each line, since the app and the scheduled job can both be writing (and rotating) it.
            let fm = FileManager.default
            let url = file
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize {
                try? fm.removeItem(at: previousFile)
                try? fm.moveItem(at: url, to: previousFile)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        }
    }
}
