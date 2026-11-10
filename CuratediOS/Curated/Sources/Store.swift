import Foundation

/// Everything the phone keeps, in Application Support (videos are excluded from iCloud backups).
struct Store {
    let root: URL
    var library: URL { root.appendingPathComponent("library", isDirectory: true) }
    var videosDir: URL { library.appendingPathComponent("videos", isDirectory: true) }
    var avatarsDir: URL { library.appendingPathComponent("avatars", isDirectory: true) }
    /// Long videos' thumbnails from the Mac, "<video id>.jpg".
    var postersDir: URL { library.appendingPathComponent("posters", isDirectory: true) }
    private var manifestFile: URL { library.appendingPathComponent("manifest.json") }
    private var playedFile: URL { root.appendingPathComponent("played.json") }
    private var pairingFile: URL { root.appendingPathComponent("pairing.json") }
    private var watchLaterFile: URL { root.appendingPathComponent("watchlater.json") }
    private var bookmarksFile: URL { root.appendingPathComponent("bookmarks.json") }
    /// Where each long video was left off, in seconds. Kept on this device only.
    /// Before positions synced: `{videoID: seconds}`. Only read, to carry them over into `positionMarksFile`.
    private var positionsFile: URL { root.appendingPathComponent("positions.json") }
    private var positionMarksFile: URL { root.appendingPathComponent("positionmarks.json") }
    private var nowPlayingFile: URL { root.appendingPathComponent("nowplaying.json") }
    private var playbackRulesFile: URL { root.appendingPathComponent("playbackrules.json") }

    /// Saves marks off the main thread, in order, so marking a video watched doesn't hold up the next one starting.
    private static let writer = DispatchQueue(label: "local.curated.store", qos: .utility)

    private func write<T: Encodable>(_ value: T, to file: URL, with encoder: JSONEncoder) {
        Self.writer.async { try? encoder.encode(value).write(to: file, options: .atomic) }
    }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Curated", isDirectory: true)
        for dir in [videosDir, avatarsDir, postersDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var lib = library
        try? lib.setResourceValues(values)
    }

    func loadManifest() -> Manifest? {
        (try? Data(contentsOf: manifestFile)).flatMap { try? Manifest.decode($0) }
    }

    func saveManifest(_ data: Data) {
        try? data.write(to: manifestFile, options: .atomic)
    }

    func videoFile(_ video: Video) -> URL { videosDir.appendingPathComponent("\(video.id).\(video.fileExtension)") }
    func partialFile(_ video: Video) -> URL { videosDir.appendingPathComponent("\(video.id).\(video.fileExtension).part") }
    func avatarFile(_ username: String) -> URL { avatarsDir.appendingPathComponent("\(username).jpg") }
    func posterFile(_ video: Video) -> URL { postersDir.appendingPathComponent("\(video.id).jpg") }

    /// Only complete files count; downloads land as .part and are renamed when done.
    func isDownloaded(_ video: Video) -> Bool {
        guard let size = fileSize(videoFile(video)) else { return false }
        return video.size <= 0 || size == video.size
    }

    func fileSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// Deletes files for videos the Mac no longer has (or that are no longer synced), and their posters. Returns how
    /// many videos went.
    func removeVideos(except keep: [Video]) -> Int {
        let posters = Set(keep.map { posterFile($0).lastPathComponent })
        for file in (try? FileManager.default.contentsOfDirectory(at: postersDir, includingPropertiesForKeys: nil)) ?? []
        where !posters.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
        let names = Set(keep.flatMap { [videoFile($0).lastPathComponent, partialFile($0).lastPathComponent] })
        let files = (try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { !names.contains($0.lastPathComponent) }
            .filter { (try? FileManager.default.removeItem(at: $0)) != nil }
            .filter { $0.pathExtension != "part" }
            .count
    }

    func removeAllVideos() {
        try? FileManager.default.removeItem(at: library)
        // After any position save still waiting to be written.
        let positionFiles = [positionsFile, positionMarksFile, nowPlayingFile, playbackRulesFile]
        Self.writer.async { for file in positionFiles { try? FileManager.default.removeItem(at: file) } }
        for dir in [videosDir, avatarsDir, postersDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func bytesUsed() -> Int {
        let files = FileManager.default.enumerator(at: library, includingPropertiesForKeys: [.fileSizeKey])?
            .compactMap { $0 as? URL } ?? []
        return files.reduce(0) { $0 + (fileSize($1) ?? 0) }
    }

    func loadPlayed() -> [String: PlayedMark] {
        (try? Data(contentsOf: playedFile)).flatMap { try? JSONDecoder.curated.decode([String: PlayedMark].self, from: $0) } ?? [:]
    }

    func savePlayed(_ marks: [String: PlayedMark]) {
        write(marks, to: playedFile, with: JSONEncoder.curated)
    }

    func loadWatchLater() -> [String: WatchLaterMark] {
        (try? Data(contentsOf: watchLaterFile)).flatMap { try? JSONDecoder.curated.decode([String: WatchLaterMark].self, from: $0) } ?? [:]
    }

    func saveWatchLater(_ marks: [String: WatchLaterMark]) {
        write(marks, to: watchLaterFile, with: JSONEncoder.curated)
    }

    func loadBookmarks() -> [String: WatchLaterMark] {
        (try? Data(contentsOf: bookmarksFile)).flatMap { try? JSONDecoder.curated.decode([String: WatchLaterMark].self, from: $0) } ?? [:]
    }

    func saveBookmarks(_ marks: [String: WatchLaterMark]) {
        write(marks, to: bookmarksFile, with: JSONEncoder.curated)
    }

    func loadPositions() -> [String: PositionMark] {
        if let marks = (try? Data(contentsOf: positionMarksFile)).flatMap({ try? JSONDecoder.curated.decode([String: PositionMark].self, from: $0) }) {
            return marks
        }
        // These had no dates before they synced. Date them long ago so any newer change wins.
        let old = (try? Data(contentsOf: positionsFile)).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        return old.mapValues { PositionMark(seconds: $0, at: Date(timeIntervalSince1970: 0)) }
    }

    func savePositions(_ marks: [String: PositionMark]) {
        write(marks, to: positionMarksFile, with: JSONEncoder.curated)
    }

    func loadNowPlaying() -> NowPlayingMark {
        (try? Data(contentsOf: nowPlayingFile)).flatMap { try? JSONDecoder.curated.decode(NowPlayingMark.self, from: $0) } ?? .none
    }

    func saveNowPlaying(_ mark: NowPlayingMark) {
        write(mark, to: nowPlayingFile, with: JSONEncoder.curated)
    }

    func loadPlaybackRules() -> PlaybackRules {
        (try? Data(contentsOf: playbackRulesFile)).flatMap { try? JSONDecoder.curated.decode(PlaybackRules.self, from: $0) } ?? PlaybackRules()
    }

    func savePlaybackRules(_ rules: PlaybackRules) {
        write(rules, to: playbackRulesFile, with: JSONEncoder.curated)
    }

    func loadPairing() -> Pairing? {
        (try? Data(contentsOf: pairingFile)).flatMap { try? JSONDecoder().decode(Pairing.self, from: $0) }
    }

    func savePairing(_ pairing: Pairing?) {
        if let pairing {
            try? JSONEncoder().encode(pairing).write(to: pairingFile, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: pairingFile)
        }
    }
}
