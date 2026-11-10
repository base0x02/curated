import Foundation

enum Tools {
    static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                              FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path]

    static func find(_ name: String) -> String? {
        searchPaths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// launchd jobs get a minimal PATH, so make sure yt-dlp can find ffmpeg etc.
    static var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (searchPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        env["PYTHONIOENCODING"] = "utf-8"
        return env
    }
}

/// Runs processes (several at once if needed), streaming merged stdout/stderr line by line.
/// Cancelling stops all of them, from any thread.
final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func cancel() {
        lock.withLock {
            cancelled = true
            processes.values.forEach { $0.terminate() }
        }
    }

    /// `onLine` returns false to stop the process early.
    func run(_ executable: String, _ arguments: [String], onLine: @escaping (String) -> Bool) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.runBlocking(executable, arguments, onLine: onLine))
            }
        }
    }

    private func runBlocking(_ executable: String, _ arguments: [String], onLine: (String) -> Bool) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.environment = Tools.environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        let started: Bool = lock.withLock {
            guard !cancelled else { return false }
            do { try p.run() } catch { return false }
            processes[ObjectIdentifier(p)] = p
            return true
        }
        guard started else {
            DownloadLog.error("Couldn't start \(executable) \(arguments.joined(separator: " "))")
            return -1
        }
        // Which run a line came from: the process id, plus the URL (or batch file) it was given.
        let tag = "\(URL(fileURLWithPath: executable).lastPathComponent) \(p.processIdentifier)"
            + (arguments.last { $0.contains("://") }.map { " \($0)" } ?? "")
        DownloadLog.debug("\(tag): run \(arguments.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " "))")

        let handle = pipe.fileHandleForReading
        var buffer = Data()
        var stopped = false
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                let line = String(decoding: lineData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("ERROR") { DownloadLog.detail("\(tag): \(line)") }
                else if !line.isEmpty { DownloadLog.debug("\(tag): \(line)") }
                if !line.isEmpty, !stopped, !onLine(line) {
                    stopped = true
                    p.terminate()
                }
            }
        }
        p.waitUntilExit()
        lock.withLock { processes[ObjectIdentifier(p)] = nil }
        DownloadLog.debug("\(tag): exit \(p.terminationStatus)" + (stopped ? " (stopped early, enough listed)" : ""))
        return stopped ? 0 : p.terminationStatus
    }
}

struct DownloadResult {
    var newVideos = 0
    var removed = 0
    /// Videos in the window that were skipped for having too few views this time.
    var belowMinViews = 0
    var error: String?
    /// Only from `pendingLong`: the new videos a download would fetch, not downloaded.
    var pending: [PendingVideo] = []
}

/// A new long video found by `DownloadEngine.pendingLong`, to pick from before downloading (see LongPicker.swift).
struct PendingVideo: Identifiable, Hashable {
    enum State { case queued, downloading, done, failed }

    let id: String
    let creatorID: String
    let title: String?
    let date: Date?
    /// Suggested videos only: the channel's name and the video's length in seconds, from the home feed.
    var channel: String? = nil
    var duration: Int? = nil
    /// YouTube's 16:9 thumbnail (its 4:3 ones are letterboxed).
    var thumbnail: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
}

enum DownloadEngine {
    /// How many creators to download at once. Kept small so TikTok doesn't start rate limiting.
    static let maxConcurrent = 3

    /// Creators that have never been downloaded first, then whoever has gone longest without a successful refresh,
    /// so the stalest feeds are fresh even if a run is stopped early.
    static func prioritized(_ creators: [Creator], state: RunState) -> [Creator] {
        func lastRefresh(_ creator: Creator) -> Date {
            guard let info = state.creators[creator.id] else { return .distantPast }
            return info.lastSuccess ?? (info.error == nil ? info.date : Date(timeIntervalSince1970: 0))
        }
        return creators.enumerated()
            .sorted { (lastRefresh($0.element), $0.offset) < (lastRefresh($1.element), $1.offset) }
            .map(\.element)
    }

    /// Every new long video `creators` have, listed without downloading anything, `maxConcurrent` creators at a time.
    /// `onFound` is called with each creator's `pending` videos (or error).
    static func pendingLong(_ creators: [Creator], settings: AppSettings, runner: ProcessRunner,
                            log: @escaping (String) -> Void,
                            onFound: @escaping (Creator, DownloadResult) async -> Void) async {
        guard let ytdlp = Tools.find("yt-dlp") else {
            for creator in creators { await onFound(creator, DownloadResult(error: "yt-dlp not found. Install it with: brew install yt-dlp")) }
            return
        }
        var pending = creators[...]
        await withTaskGroup(of: Void.self) { group in
            func startNext() {
                guard !runner.isCancelled, let creator = pending.popFirst() else { return }
                group.addTask {
                    let result = await download(creator, form: .long, ytdlp: ytdlp, settings: settings, runner: runner,
                                                log: log, listOnly: true)
                    await onFound(creator, result)
                }
            }
            for _ in 0..<maxConcurrent { startNext() }
            while await group.next() != nil { startNext() }
        }
    }

    /// How many videos the older-videos picker reveals at a time. The grid only fetches thumbnails for tiles on screen.
    static let olderVideosPerLoad = 40

    /// All of a creator's long videos on YouTube, newest first (the channel's "UULF…" list, which leaves out Shorts and
    /// live streams), passed to `onFound` a few at a time as they're listed. Leaves out `excluding` and what's in the
    /// creator's archive (downloaded before, deleted or skipped). Reading it all once costs about one request per 100
    /// videos, far less than asking again from the start for each page. Returns an error if nothing could be listed.
    static func olderLong(_ creator: Creator, excluding: Set<String>, settings: AppSettings, runner: ProcessRunner,
                          log: @escaping (String) -> Void, onFound: @escaping @MainActor ([PendingVideo]) -> Void) async -> String? {
        guard let ytdlp = Tools.find("yt-dlp") else { return "yt-dlp not found. Install it with: brew install yt-dlp" }
        let profileFolder = Library.folder(for: creator.id, settings: settings)
        try? FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
        guard let channelID = await refreshYouTubeChannel(creator, folder: profileFolder, log: log) else {
            return "Couldn't find the YouTube channel @\(creator.username)"
        }
        let archive = Library.folder(for: creator, form: .long, settings: settings).appendingPathComponent("archive.txt")
        let archived = Set(((try? String(contentsOf: archive, encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) })
        let browser = settings.youtubeCookieBrowser
        let cookieArgs = browser == .none ? [] : ["--cookies-from-browser", browser.rawValue]
        log("Listing @\(creator.username)'s long videos…")
        var batch: [PendingVideo] = [], errors: [String] = [], entries = 0
        _ = await runner.run(ytdlp, ["--flat-playlist", "--lazy-playlist", "--no-warnings", "-j",
                                     "--extractor-args", "youtubetab:approximate_date"]
                                    + cookieArgs + ["https://www.youtube.com/playlist?list=UULF\(channelID.dropFirst(2))"]) { line in
            if line.hasPrefix("ERROR") { errors.append(line); return true }
            guard line.hasPrefix("{"), let entry = try? JSONDecoder().decode(Suggestion.self, from: Data(line.utf8)) else { return true }
            entries += 1
            if !excluding.contains(entry.id), !archived.contains(entry.id),
               entry.live_status != "is_live", entry.live_status != "is_upcoming" {
                batch.append(PendingVideo(id: entry.id, creatorID: creator.id, title: entry.title,
                                          date: entry.timestamp.map(Date.init(timeIntervalSince1970:)),
                                          duration: entry.duration.map { Int($0) }))
            }
            if batch.count >= olderVideosPerLoad {
                let found = batch
                batch = []
                Task { @MainActor in onFound(found) }
            }
            return true
        }
        let found = batch
        await MainActor.run { onFound(found) }
        DownloadLog.detail("@\(creator.username): \(entries) long videos listed")
        // Stopped on purpose, or some were listed: what's there can still be picked.
        guard !runner.isCancelled, entries == 0, let error = errors.last else { return nil }
        return cleanError(error)
    }

    /// One video on the YouTube home feed, as yt-dlp's flat listing of `:ytrec` gives it.
    struct Suggestion: Decodable {
        let id: String
        let title: String?
        let duration: Double?
        let channel: String?
        /// "UC…"
        let channel_id: String?
        /// "@handle"
        let uploader_id: String?
        let url: String?
        let live_status: String?
        let timestamp: Double?

        /// Long videos only: no Shorts (the feed's Shorts shelf), live streams, premieres or playlists.
        var isLongVideo: Bool {
            guard let url, url.contains("/watch?v="), live_status != "is_live", live_status != "is_upcoming" else { return false }
            return (duration ?? 0) >= 60
        }

        /// The handle without its "@", lowercased like `Creator.username`.
        var handle: String? { uploader_id.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased() } }
    }

    /// How many entries of the home feed to read: about two pages of it.
    static let suggestionsToList = 60

    /// The long videos on the YouTube home feed of whoever is signed in to YouTube in `settings.youtubeCookieBrowser`
    /// (yt-dlp reads the browser's cookies itself and follows the feed's continuations). Signed out, YouTube's home
    /// page is empty, which comes back as an error saying so.
    static func suggestions(settings: AppSettings, runner: ProcessRunner,
                            log: @escaping (String) -> Void) async -> (videos: [Suggestion], error: String?) {
        #if DEBUG
        // CURATED_TEST_SUGGESTIONS=<file of yt-dlp JSON lines> stands in for the feed, for tests.
        if let path = ProcessInfo.processInfo.environment["CURATED_TEST_SUGGESTIONS"] {
            let lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n")
            return (lines.compactMap { try? JSONDecoder().decode(Suggestion.self, from: Data($0.utf8)) }.filter(\.isLongVideo), nil)
        }
        #endif
        guard let ytdlp = Tools.find("yt-dlp") else { return ([], "yt-dlp not found. Install it with: brew install yt-dlp") }
        let browser = settings.youtubeCookieBrowser
        guard browser != .none else {
            return ([], "Curated needs to borrow your YouTube sign-in to see your suggestions. Pick the browser you watch "
                        + "YouTube in under Settings → Downloads → Sign-In → YouTube.")
        }
        log("Reading your YouTube home feed (signed in through \(browser.label))…")
        var found: [Suggestion] = [], errors: [String] = [], entries = 0
        _ = await runner.run(ytdlp, ["--flat-playlist", "--no-warnings", "-j", "-I", "1:\(suggestionsToList)",
                                     "--extractor-args", "youtubetab:approximate_date",
                                     "--cookies-from-browser", browser.rawValue, ":ytrec"]) { line in
            if line.hasPrefix("ERROR") { errors.append(line); return true }
            guard line.hasPrefix("{"), let entry = try? JSONDecoder().decode(Suggestion.self, from: Data(line.utf8)) else { return true }
            entries += 1
            if entry.isLongVideo, !found.contains(where: { $0.id == entry.id }) { found.append(entry) }
            return true
        }
        if runner.isCancelled { return (found, "Cancelled") }
        DownloadLog.detail("Home feed: \(entries) entries, \(found.count) long videos")
        if let error = errors.last, found.isEmpty { return ([], cleanError(error)) }
        if entries == 0 {
            return ([], "Your YouTube home feed came back empty. Curated reads it through \(browser.label)'s sign-in: "
                        + "make sure you're signed in to YouTube there (or pick another browser under Settings → Downloads "
                        + "→ Sign-In), and that your YouTube watch history is on, or YouTube shows no home feed.")
        }
        return (found, nil)
    }

    /// Downloads creators in priority order, up to `maxConcurrent` at a time, recording each result in RunState.
    /// `onStart` and `onFinish` are called as each creator begins and ends. With `only`, a creator listed there gets
    /// just those long videos (picked in the long-video picker), and `onVideo` follows each one. `heights` overrides
    /// the creator's resolution for single long videos, by video id (a nil value is Best).
    static func downloadAll(_ creators: [Creator], forms: Set<VideoForm> = Set(VideoForm.allCases),
                            settings: AppSettings, runner: ProcessRunner,
                            log: @escaping (String) -> Void,
                            only: [String: Set<String>]? = nil,
                            heights: [String: Int?] = [:],
                            onVideo: ((String, PendingVideo.State) -> Void)? = nil,
                            onStart: @escaping (Creator) async -> Void = { _ in },
                            onFinish: @escaping (Creator, DownloadResult) async -> Void = { _, _ in }) async {
        var pending = prioritized(creators, state: RunState.load())[...]
        let started = Date()
        let formNames = forms.map(\.rawValue).sorted().joined(separator: "+")
        DownloadLog.info("Downloading \(creators.count) creator(s) (\(formNames)), \(maxConcurrent) at a time")
        DownloadLog.detail("Order: " + pending.map(\.id).joined(separator: ", "))
        let tally = Tally()
        await withTaskGroup(of: Void.self) { group in
            func startNext() {
                guard !runner.isCancelled, let creator = pending.popFirst() else { return }
                group.addTask {
                    await onStart(creator)
                    let began = Date()
                    DownloadLog.detail("\(creator.id): started")
                    let result = await download(creator, forms: forms, settings: settings, runner: runner, log: log,
                                                only: only?[creator.id], heights: heights, onVideo: onVideo)
                    DownloadLog.result(creator.id, result, seconds: Date().timeIntervalSince(began))
                    tally.add(creator.id, result)
                    RunState.record(result, for: creator.id)
                    await onFinish(creator, result)
                }
            }
            for _ in 0..<maxConcurrent { startNext() }
            while await group.next() != nil { startNext() }
        }
        let (done, newVideos, failed) = tally.totals
        let minutes = Int(Date().timeIntervalSince(started)) / 60, seconds = Int(Date().timeIntervalSince(started)) % 60
        DownloadLog.info("Finished \(done) of \(creators.count) creator(s) in \(minutes)m \(seconds)s: \(newVideos) new video(s)"
                         + (runner.isCancelled ? ", stopped early" : ""))
        if !failed.isEmpty {
            DownloadLog.error("\(failed.count) failed: " + failed.map { "\($0.0) (\($0.1))" }.joined(separator: "; "))
        }
    }

    /// Each creator's outcome, for the run's summary line.
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var done = 0, newVideos = 0
        private var failed: [(String, String)] = []
        func add(_ id: String, _ result: DownloadResult) {
            lock.withLock {
                done += 1
                newVideos += result.newVideos
                if let error = result.error, error != "Cancelled" { failed.append((id, error)) }
            }
        }
        var totals: (Int, Int, [(String, String)]) { lock.withLock { (done, newVideos, failed) } }
    }

    /// TikTok lists up to 3 pinned (possibly old) videos first; after that the feed is newest-first.
    private static let oldVideosBeforeStopping = 4

    /// Downloads a creator's short videos and/or (YouTube) long videos: whichever they have turned on, out of `forms`.
    /// With `only`, just those long videos; `heights` overrides the creator's resolution for single long videos.
    static func download(_ creator: Creator, forms: Set<VideoForm> = Set(VideoForm.allCases), settings: AppSettings,
                         runner: ProcessRunner, log: @escaping (String) -> Void, only: Set<String>? = nil,
                         heights: [String: Int?] = [:],
                         onVideo: ((String, PendingVideo.State) -> Void)? = nil) async -> DownloadResult {
        guard let ytdlp = Tools.find("yt-dlp") else {
            return DownloadResult(error: "yt-dlp not found. Install it with: brew install yt-dlp")
        }
        var result = DownloadResult()
        for form in VideoForm.allCases where forms.contains(form) && creator.downloads(form) && !runner.isCancelled {
            let part = await download(creator, form: form, ytdlp: ytdlp, settings: settings, runner: runner, log: log,
                                      only: form == .long ? only : nil, heights: form == .long ? heights : [:],
                                      onVideo: form == .long ? onVideo : nil)
            result.newVideos += part.newVideos
            result.removed += part.removed
            result.belowMinViews += part.belowMinViews
            result.error = result.error ?? part.error
            // Short videos only: new ones, and the first time, everything downloaded before.
            if form == .short, !creator.playlist, settings.evenOutVolume, !runner.isCancelled {
                await Loudness.normalize(folder: Library.folder(for: creator, form: form, settings: settings),
                                         runner: runner, log: log, label: label(creator, form: form))
            }
        }
        return result
    }

    /// `listOnly` stops after the listing, with what would be downloaded in `pending`. `only` downloads just those
    /// videos (that aren't in the archive) in place of the listing's new ones. `heights` overrides the creator's
    /// resolution for single long videos (a nil value is Best).
    private static func download(_ creator: Creator, form: VideoForm, ytdlp: String, settings: AppSettings,
                                 runner: ProcessRunner, log: @escaping (String) -> Void, listOnly: Bool = false,
                                 only: Set<String>? = nil, heights: [String: Int?] = [:],
                                 onVideo: ((String, PendingVideo.State) -> Void)? = nil) async -> DownloadResult {
        let folder = Library.folder(for: creator, form: form, settings: settings)
        // The main folder holds the avatar and profile, for long videos too.
        let profileFolder = Library.folder(for: creator.id, settings: settings)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: profileFolder, withIntermediateDirectories: true)
        } catch {
            return DownloadResult(error: "Can't create \(folder.path): \(error.localizedDescription)")
        }

        let browser = creator.platform == .youtube ? settings.youtubeCookieBrowser : settings.cookieBrowser
        let cookieArgs = browser == .none ? [] : ["--cookies-from-browser", browser.rawValue]
        let cutoff = Library.cutoff(for: creator)
        let name = label(creator, form: form)
        DownloadLog.detail("\(name): cookies from \(browser.rawValue), folder \(folder.path)"
                           + (creator.playlist || creator.keepsByCount ? "" : ", posted since \(Date(timeIntervalSince1970: cutoff))"))
        let archive = folder.appendingPathComponent("archive.txt")
        let archived = Set(((try? String(contentsOf: archive, encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) })

        // Kept by count: only as many as it takes to get back to `keepVideos` unwatched.
        let counting = form == .short && creator.keepsByCount
        let played: Set<String> = counting ? Set(PlayedStore.load().filter(\.value.played).keys) : []
        var needed = 0
        if counting, let keep = creator.keepVideos {
            // Bookmarks stay out of the mixes, so they don't count toward the videos kept.
            let bookmarked = BookmarkStore.bookmarkedIDs()
            let unwatched = Library.videoFiles(in: folder).count { !played.contains($0.id) && !bookmarked.contains($0.id) }
            needed = keep - unwatched
            guard needed > 0 else {
                log("\(name): \(unwatched) unwatched, keeping \(keep). Nothing to download")
                await refreshProfile(creator, folder: profileFolder, log: log)
                return DownloadResult()
            }
            log("Checking \(name): \(unwatched) of \(keep) unwatched, looking for \(needed) more"
                + (creator.keepHistorical ? " (older videos too)…" : "…"))
        } else {
            log(creator.playlist ? "Checking \(name)…" : "Checking \(name) for videos from the last \(creator.days) day(s)…")
        }
        let newest = counting ? Library.newestDownloadDate(in: folder) : nil
        /// Kept by count, whether an unseen video could still be one of the picks, for knowing when to stop listing.
        let wanted: (String, Int?) -> Bool = { id, views in
            !archived.contains(id) && !played.contains(id) && (views ?? 0) >= (creator.minViews ?? 0)
        }

        // Phase 1: find the videos inside the window (a playlist: all of it; kept by count: enough to choose from),
        // without downloading anything.
        let listing: Listing
        switch creator.platform {
        case .tiktok:
            await refreshTikTokProfile(creator, folder: profileFolder, log: log)
            listing = counting
                ? await listTikTokForCount(creator, ytdlp: ytdlp, cookieArgs: cookieArgs, newest: newest,
                                           needed: needed, wanted: wanted, runner: runner)
                : await listTikTok(creator, ytdlp: ytdlp, cookieArgs: cookieArgs, cutoff: cutoff, runner: runner)
        case .youtube where creator.isSuggestions:
            // Nothing to list: its videos are the ones picked from the home feed (`only`).
            listing = Listing()
        case .youtube where creator.playlist:
            listing = await listPlaylist(creator, ytdlp: ytdlp, cookieArgs: cookieArgs, folder: folder, runner: runner)
        case .youtube:
            var youtube = await listYouTube(creator, form: form, profileFolder: profileFolder,
                                            cutoff: counting ? 0 : cutoff, log: log)
            // The feed only has the latest 15. Older ones come from the channel's whole list of Shorts.
            let inFeed = Set(youtube.recentIDs)
            let fromFeed = youtube.recentIDs.count(where: { wanted($0, youtube.viewCounts[$0]) })
            if counting, creator.keepHistorical || newest == nil, fromFeed < needed,
               let channelID = await refreshYouTubeChannel(creator, folder: profileFolder, log: log) {
                let shorts = URL(string: "https://www.youtube.com/playlist?list=UUSH\(channelID.dropFirst(2))")!
                let older = await listFlatPlaylist(shorts, ytdlp: ytdlp, cookieArgs: cookieArgs, runner: runner) { list in
                    list.recentIDs.count { !inFeed.contains($0) && wanted($0, list.viewCounts[$0]) } >= needed - fromFeed
                }
                for id in older.recentIDs where !youtube.recentIDs.contains(id) {
                    youtube.recentIDs.append(id)
                    youtube.viewCounts[id] = older.viewCounts[id]
                    youtube.dates[id] = older.dates[id]
                }
                if youtube.error == nil { youtube.error = older.error }
            }
            listing = youtube
        case .vine:
            // Vines come from the classics feed (Vine.download), never one author at a time.
            listing = Listing()
        }
        if runner.isCancelled { return DownloadResult(error: "Cancelled") }
        Library.mergeViewCounts(listing.viewCounts, in: folder)
        // Hand-picked videos don't need the listing, only their ids.
        if only == nil, listing.recentIDs.isEmpty, let error = listing.error {
            return DownloadResult(error: cleanError(error))
        }
        if let error = listing.error {
            DownloadLog.error("\(name): listing stopped with an error after \(listing.recentIDs.count) video(s): \(cleanError(error))")
        }
        if !listing.recentIDs.isEmpty { DownloadLog.debug("\(name): listed \(listing.recentIDs.joined(separator: " "))") }

        var result = DownloadResult()
        // A playlist limited to its newest N: those by upload date (ties in playlist order). Already-downloaded ones
        // count toward N.
        var candidates = listing.recentIDs
        if creator.playlist, let limit = creator.playlistLimit {
            candidates = candidates.enumerated()
                .sorted { (listing.dates[$0.element] ?? 0, -$0.offset) > (listing.dates[$1.element] ?? 0, -$1.offset) }
                .prefix(limit)
                .map(\.element)
        }
        var toFetch = candidates.filter { !archived.contains($0) && !played.contains($0) }
        if let minViews = creator.minViews {
            // Skipped videos stay out of the archive, so the next run checks their (by then higher) view counts again.
            let popular = toFetch.filter { (listing.viewCounts[$0] ?? 0) >= minViews }
            result.belowMinViews = toFetch.count - popular.count
            toFetch = popular
        }
        if counting {
            toFetch = pickForCount(toFetch, dates: listing.dates, newest: newest,
                                   historical: creator.keepHistorical, needed: needed)
        }
        log("\(name): \(listing.recentIDs.count) \(creator.playlist ? "in the playlist" : counting ? "listed" : "recent")"
            + (candidates.count < listing.recentIDs.count ? ", newest \(candidates.count)" : "")
            + ", \(toFetch.count) new" +
            (result.belowMinViews > 0 ? ", \(result.belowMinViews) under \(compactViews(creator.minViews ?? 0)) views" : ""))
        if listOnly {
            result.pending = toFetch.map {
                PendingVideo(id: $0, creatorID: creator.id, title: listing.titles[$0],
                             date: listing.dates[$0].map(Date.init(timeIntervalSince1970:)))
            }
            return result
        }
        if let only {
            // The picked ones, in the listing's order (any it no longer lists last).
            let picked = only.subtracting(archived)
            toFetch = listing.recentIDs.filter(picked.contains) + picked.subtracting(listing.recentIDs).sorted()
            log("\(name): \(toFetch.count) picked")
        }

        /// One yt-dlp run over `ids`, long ones at up to `height` (nil: Best). Returns its errors.
        func fetch(_ ids: [String], height: Int?) async -> [String] {
            let batch = FileManager.default.temporaryDirectory
                .appendingPathComponent("curated-\(creator.id)-\(form.rawValue)-\(UUID().uuidString).txt")
            try? ids.map { videoURL(creator, form: form, id: $0) }.joined(separator: "\n")
                .write(to: batch, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: batch) }

            // Prefer H.264 so AVPlayer can always play it. Short: skip photo slideshows (no video stream).
            // Long: at most the creator's resolution (or the one picked for the video), plus YouTube's thumbnail as
            // a poster beside it (same name, .jpg; a video's first frame is often black).
            // Best: the highest resolution that's H.264, which on YouTube is 1080p.
            let longFormat = height.map { height in
                ["-f", "bv*[height<=\(height)]+ba/b[height<=\(height)]/bv*+ba/b", "-S", "vcodec:h264,res:\(height),acodec:m4a"]
            } ?? ["-f", "bv*+ba/b", "-S", "vcodec:h264,res,acodec:m4a"]
            let format = form == .short
                ? ["-f", "b[vcodec!=none]/bv*+ba", "-S", "vcodec:h264,res,br"]
                : longFormat + ["--write-thumbnail", "--convert-thumbnails", "jpg",
                                "-o", "thumbnail:" + folder.appendingPathComponent("%(timestamp)s_%(id)s.%(ext)s").path]
            var errors: [String] = []
            /// The video being downloaded, for `onVideo`.
            var current: String?
            let fetching = Set(ids)
            _ = await runner.run(ytdlp, [
                "--newline", "--no-progress", "--no-warnings",
            ] + format + [
                "--merge-output-format", "mp4",
                "--download-archive", archive.path,
                "-o", folder.appendingPathComponent("%(timestamp)s_%(id)s.%(ext)s").path,
                "--print-to-file", "after_move:%(.{id,title,description,timestamp,upload_date,duration,view_count})j",
                folder.appendingPathComponent("videos.jsonl").path,
                "-a", batch.path,
            ] + cookieArgs) { line in
                if line.hasPrefix("ERROR") {
                    // Photo posts have no video format; skip them quietly.
                    if !line.contains("Requested format is not available") { errors.append(line) }
                    else { DownloadLog.detail("\(name): skipped a photo post (no video)") }
                    // "ERROR: [youtube] <id>: …"
                    if let onVideo, let id = firstMatch(#"^ERROR: \[[^\]]+\] ([^:\s]+):"#, in: line), fetching.contains(id) {
                        onVideo(id, .failed)
                        if current == id { current = nil }
                    }
                } else if line.contains("[download] Destination:") || line.contains("[Merger]") {
                    // "<timestamp>_<id>.<ext>", or "….f137.mp4" for one stream of several.
                    if let onVideo, line.contains("[download] Destination:"),
                       let file = line.split(separator: "/").last, let underscore = file.firstIndex(of: "_") {
                        let id = String(file[file.index(after: underscore)...].prefix { $0 != "." })
                        if id != current, fetching.contains(id) {
                            current = id
                            onVideo(id, .downloading)
                        }
                    }
                    return true
                } else if line.hasPrefix("[download] Downloading item") {
                    log("\(name): \(line.replacingOccurrences(of: "[download] ", with: ""))")
                } else if line.contains("Writing '%(") {
                    result.newVideos += 1
                    if let id = current { onVideo?(id, .done) }
                    current = nil
                }
                return true
            }
            return errors
        }

        // Phase 2: download only the new, in-range videos. Long videos picked at another resolution than the
        // creator's go in their own yt-dlp run, one run per resolution, in the order each first comes up.
        if !toFetch.isEmpty {
            var groups: [(height: Int?, ids: [String])] = []
            for id in toFetch {
                let height = form == .long ? heights[id] ?? creator.longFormHeight : nil
                if let i = groups.firstIndex(where: { $0.height == height }) { groups[i].ids.append(id) }
                else { groups.append((height, [id])) }
            }
            var errors: [String] = []
            for group in groups where !runner.isCancelled {
                if groups.count > 1 {
                    log("\(name): \(group.ids.count) at \(group.height.map { "up to \($0)p" } ?? "best resolution")")
                }
                errors += await fetch(group.ids, height: group.height)
            }
            if runner.isCancelled { result.error = "Cancelled" }
            else if let error = errors.last { result.error = cleanError(error) }
            if errors.count > 1 { DownloadLog.error("\(name): \(errors.count) of \(toFetch.count) downloads failed") }
            dateUndatedFiles(in: folder, using: listing.dates)
        }

        // Long videos are never deleted for their age, only when watched (Delete All Watched) or trashed. Nor are
        // short ones kept by count.
        if settings.deleteOutsideWindow && form == .short && !counting {
            result.removed = Library.deleteVideos(in: folder, olderThan: cutoff, keeping: BookmarkStore.bookmarkedIDs())
        }
        log("\(name): done — \(result.newVideos) new" +
            (result.removed > 0 ? ", \(result.removed) old removed" : "") +
            (result.error.map { " (\($0))" } ?? ""))
        return result
    }

    /// YouTube doesn't always tell yt-dlp a video's upload time, so it names the file "NA_<id>.mp4", which the library
    /// can't place. Renames those (and their posters) to "<publish time>_<id>.<ext>", taking the time from YouTube's
    /// feed, or else the upload day yt-dlp recorded in videos.jsonl (playlists have no feed dates).
    private static func dateUndatedFiles(in folder: URL, using feedDates: [String: TimeInterval]) {
        let fm = FileManager.default
        var dates = uploadDays(in: folder)
        dates.merge(feedDates) { _, feed in feed }
        for file in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("NA_"), let date = dates[String(name.dropFirst(3))] else { continue }
            let dated = folder.appendingPathComponent("\(Int(date))_\(name.dropFirst(3)).\(file.pathExtension)")
            try? fm.moveItem(at: file, to: dated)
        }
    }

    /// Noon UTC on each video's "upload_date" (YYYYMMDD) in videos.jsonl.
    private static func uploadDays(in folder: URL) -> [String: TimeInterval] {
        struct Entry: Decodable { let id: String; let upload_date: String? }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHH"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let text = (try? String(contentsOf: folder.appendingPathComponent("videos.jsonl"), encoding: .utf8)) ?? ""
        var days: [String: TimeInterval] = [:]
        for line in text.split(separator: "\n") {
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)),
                  let day = entry.upload_date, let date = formatter.date(from: day + "12") else { continue }
            days[entry.id] = date.timeIntervalSince1970
        }
        return days
    }

    /// A YouTube playlist: every video in it, in order, with view counts. Saves the order (order.json) and the
    /// playlist's title as its name (profile.json).
    private static func listPlaylist(_ creator: Creator, ytdlp: String, cookieArgs: [String], folder: URL,
                                     runner: ProcessRunner) async -> Listing {
        var listing = Listing()
        var title: String?
        var errors: [String] = []
        // approximate_date: an upload day for each entry ("3 days ago"), for the newest-N limit and file dates.
        _ = await runner.run(ytdlp, ["--flat-playlist", "--no-warnings",
                                     "--extractor-args", "youtubetab:approximate_date",
                                     "--print", "ENTRY %(id)s %(view_count)s %(timestamp)s",
                                     "--print", "NAME %(id)s %(title)s",
                                     "--print", "TITLE %(playlist_title)s"]
                                    + cookieArgs + [creator.profileURL.absoluteString]) { line in
            if line.hasPrefix("ERROR") {
                errors.append(line)
            } else if line.hasPrefix("TITLE "), title == nil {
                title = String(line.dropFirst(6))
            } else if line.hasPrefix("NAME ") {
                let parts = line.dropFirst(5).split(separator: " ", maxSplits: 1)
                if parts.count == 2, parts[1] != "NA" { listing.titles[String(parts[0])] = String(parts[1]) }
            } else if line.hasPrefix("ENTRY ") {
                let parts = line.split(separator: " ")
                guard parts.count == 4 else { return true }
                let id = String(parts[1])
                listing.recentIDs.append(id)
                if let views = Int(parts[2]) { listing.viewCounts[id] = views }
                if let date = TimeInterval(parts[3]) { listing.dates[id] = date }
            }
            return true
        }
        if !listing.recentIDs.isEmpty { Library.savePlaylistOrder(listing.recentIDs, in: folder) }
        if let title, !title.isEmpty, title != "NA" { Library.saveProfile(nickname: title, in: folder) }
        listing.error = errors.last
        if !avatarIsFresh(in: folder) {
            await savePlaylistThumbnail(creator, ytdlp: ytdlp, cookieArgs: cookieArgs, folder: folder, runner: runner)
        }
        return listing
    }

    /// The playlist's own thumbnail (a custom one if it has it, else YouTube's pick), saved as its avatar.jpg.
    private static func savePlaylistThumbnail(_ creator: Creator, ytdlp: String, cookieArgs: [String], folder: URL,
                                              runner: ProcessRunner) async {
        struct Info: Decodable {
            struct Thumbnail: Decodable { let url: String; let width: Int? }
            let thumbnails: [Thumbnail]?
        }
        var json = ""
        // -I 0: the playlist's own details, no entries.
        _ = await runner.run(ytdlp, ["--flat-playlist", "--no-warnings", "-J", "-I", "0"]
                                    + cookieArgs + [creator.profileURL.absoluteString]) { line in
            if !line.hasPrefix("ERROR") && !line.hasPrefix("WARNING") { json += line }
            return true
        }
        let thumbnails = (try? JSONDecoder().decode(Info.self, from: Data(json.utf8)))?.thumbnails ?? []
        // The largest that's still a sensible size for an avatar.
        let best = thumbnails.filter { ($0.width ?? 0) <= 900 }.max { ($0.width ?? 0) < ($1.width ?? 0) } ?? thumbnails.last
        await saveAvatar(from: best.flatMap { URL(string: $0.url) }, in: folder, name: label(creator)) { _ in }
    }

    /// Videos posted inside a creator's window, newest first, with their latest view counts.
    private struct Listing {
        var recentIDs: [String] = []
        var viewCounts: [String: Int] = [:]
        /// Video titles, where the listing has them (YouTube's feed and playlists), for the long-video picker.
        var titles: [String: String] = [:]
        /// Publish times from YouTube's feed, for files yt-dlp couldn't date.
        var dates: [String: TimeInterval] = [:]
        var error: String?
    }

    private static func label(_ creator: Creator, form: VideoForm = .short) -> String {
        if creator.playlist { return "Playlist \(creator.username)" }
        return switch (creator.platform, form) {
        case (.tiktok, _): "@\(creator.username)"
        case (.youtube, .short): "YouTube @\(creator.username)"
        case (.youtube, .long): "YouTube @\(creator.username) (long)"
        case (.vine, _): "Vine \(creator.username)"
        }
    }

    private static func videoURL(_ creator: Creator, form: VideoForm, id: String) -> String {
        switch (creator.platform, form) {
        case (.tiktok, _): "\(creator.profileURL.absoluteString)/video/\(id)"
        case (.youtube, .short): "https://www.youtube.com/shorts/\(id)"
        case (.youtube, .long): "https://www.youtube.com/watch?v=\(id)"
        case (.vine, _): Vine.classicsURL.absoluteString
        }
    }

    /// TikTok: a cheap listing (timestamps come with the feed) until we're past the cutoff.
    private static func listTikTok(_ creator: Creator, ytdlp: String, cookieArgs: [String], cutoff: TimeInterval,
                                   runner: ProcessRunner) async -> Listing {
        var listing = Listing()
        var oldStreak = 0
        var errors: [String] = []
        _ = await runner.run(ytdlp, ["--flat-playlist", "--lazy-playlist", "--no-warnings",
                                     "--print", "LIST %(timestamp)s %(id)s %(view_count)s"]
                                    + cookieArgs + [creator.profileURL.absoluteString]) { line in
            if line.hasPrefix("ERROR") { errors.append(line); return true }
            let parts = line.split(separator: " ")
            guard parts.count == 4, parts[0] == "LIST", let ts = Double(parts[1]) else { return true }
            if ts >= cutoff {
                listing.recentIDs.append(String(parts[2]))
                if let views = Int(parts[3]) { listing.viewCounts[String(parts[2])] = views }
                oldStreak = 0
            } else {
                oldStreak += 1
            }
            return oldStreak < oldVideosBeforeStopping
        }
        listing.error = errors.last
        return listing
    }

    /// Kept by count: new posts (after the newest video ever downloaded) come first, oldest of them first, so none are
    /// skipped. Then, with `historical` or for a creator with nothing downloaded yet, older videos, newest first.
    /// `ids` are already the ones not downloaded, watched or under the minimum views.
    private static func pickForCount(_ ids: [String], dates: [String: TimeInterval], newest: TimeInterval?,
                                     historical: Bool, needed: Int) -> [String] {
        let ordered = ids.enumerated()
        let newer = ordered.filter { newest != nil && (dates[$0.element] ?? 0) > newest! }
            .sorted { (dates[$0.element] ?? 0, -$0.offset) < (dates[$1.element] ?? 0, -$1.offset) }
        let older = historical || newest == nil
            ? ordered.filter { newest == nil || (dates[$0.element] ?? 0) <= newest! }
                .sorted { (dates[$0.element] ?? 0, -$0.offset) > (dates[$1.element] ?? 0, -$1.offset) }
            : []
        return (newer + older).prefix(needed).map(\.element)
    }

    /// TikTok, kept by count: lists newest first until there's enough to choose from. Without `newest` (nothing
    /// downloaded yet) that's the newest few; otherwise everything since `newest`, plus (`historical`) enough older ones.
    private static func listTikTokForCount(_ creator: Creator, ytdlp: String, cookieArgs: [String], newest: TimeInterval?,
                                           needed: Int, wanted: @escaping (String, Int?) -> Bool,
                                           runner: ProcessRunner) async -> Listing {
        var listing = Listing()
        var oldStreak = 0
        var olderWanted = 0
        var errors: [String] = []
        let digOlder = creator.keepHistorical || newest == nil
        _ = await runner.run(ytdlp, ["--flat-playlist", "--lazy-playlist", "--no-warnings",
                                     "--print", "LIST %(timestamp)s %(id)s %(view_count)s"]
                                    + cookieArgs + [creator.profileURL.absoluteString]) { line in
            if line.hasPrefix("ERROR") { errors.append(line); return true }
            let parts = line.split(separator: " ")
            guard parts.count == 4, parts[0] == "LIST", let ts = Double(parts[1]) else { return true }
            let id = String(parts[2]), views = Int(parts[3])
            listing.recentIDs.append(id)
            listing.dates[id] = ts
            if let views { listing.viewCounts[id] = views }
            if let newest, ts > newest {
                oldStreak = 0
            } else {
                oldStreak += 1
                if wanted(id, views) { olderWanted += 1 }
            }
            // Up to 3 pinned videos come first, so a few extra before stopping.
            if listing.recentIDs.count >= maxCountListing { return false }
            return digOlder ? olderWanted < needed + oldVideosBeforeStopping : oldStreak < oldVideosBeforeStopping
        }
        listing.error = errors.last
        return listing
    }

    /// The most a kept-by-count listing looks through, newest first.
    private static let maxCountListing = 500

    /// A YouTube playlist's entries in order (for a channel's Shorts, newest first), until `enough` says so.
    private static func listFlatPlaylist(_ url: URL, ytdlp: String, cookieArgs: [String], runner: ProcessRunner,
                                         enough: @escaping (Listing) -> Bool) async -> Listing {
        var listing = Listing()
        var errors: [String] = []
        _ = await runner.run(ytdlp, ["--flat-playlist", "--lazy-playlist", "--no-warnings",
                                     "--extractor-args", "youtubetab:approximate_date",
                                     "--print", "ENTRY %(id)s %(view_count)s %(timestamp)s"]
                                    + cookieArgs + [url.absoluteString]) { line in
            if line.hasPrefix("ERROR") { errors.append(line); return true }
            let parts = line.split(separator: " ")
            guard parts.count == 4, parts[0] == "ENTRY" else { return true }
            let id = String(parts[1])
            listing.recentIDs.append(id)
            if let views = Int(parts[2]) { listing.viewCounts[id] = views }
            if let date = TimeInterval(parts[3]) { listing.dates[id] = date }
            return listing.recentIDs.count < maxCountListing && !enough(listing)
        }
        listing.error = errors.last
        return listing
    }

    /// Just the avatar and name, for a creator with nothing to download.
    private static func refreshProfile(_ creator: Creator, folder: URL, log: (String) -> Void) async {
        switch creator.platform {
        case .tiktok: await refreshTikTokProfile(creator, folder: folder, log: log)
        case .youtube where !creator.playlist: _ = await refreshYouTubeChannel(creator, folder: folder, log: log)
        default: break
        }
    }

    /// YouTube: the channel's Shorts-only feed (its "UUSH…" playlist) or long-videos-only feed ("UULF…", which leaves
    /// out Shorts and live streams) lists the latest 15 with publish dates and view counts, so nothing needs yt-dlp
    /// until the download.
    private static func listYouTube(_ creator: Creator, form: VideoForm, profileFolder: URL, cutoff: TimeInterval,
                                    log: (String) -> Void) async -> Listing {
        guard let channelID = await refreshYouTubeChannel(creator, folder: profileFolder, log: log) else {
            return Listing(error: "Couldn't find the YouTube channel @\(creator.username)")
        }
        let playlist = (form == .short ? "UUSH" : "UULF") + channelID.dropFirst(2)
        let feed = URL(string: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(playlist)")!
        guard let (data, response) = try? await URLSession.shared.data(from: feed),
              let status = (response as? HTTPURLResponse)?.statusCode else {
            return Listing(error: "Couldn't reach YouTube")
        }
        DownloadLog.debug("@\(creator.username): \(feed.absoluteString) returned HTTP \(status), \(data.count) bytes")
        if status == 404 { return Listing() }  // the channel has never posted one
        guard status == 200 else {
            return Listing(error: "YouTube's \(form == .short ? "Shorts" : "videos") feed returned HTTP \(status)")
        }

        var listing = Listing()
        let dates = ISO8601DateFormatter()
        for entry in String(decoding: data, as: UTF8.self).components(separatedBy: "<entry>").dropFirst() {
            guard let id = firstMatch(#"<yt:videoId>([^<]+)</yt:videoId>"#, in: entry),
                  let published = firstMatch(#"<published>([^<]+)</published>"#, in: entry).flatMap(dates.date(from:)),
                  published.timeIntervalSince1970 >= cutoff else { continue }
            listing.recentIDs.append(id)
            listing.dates[id] = published.timeIntervalSince1970
            if let title = firstMatch(#"<title>([^<]*)</title>"#, in: entry) { listing.titles[id] = decodeEntities(title) }
            if let views = firstMatch(#"<media:statistics views="(\d+)""#, in: entry).flatMap(Int.init) {
                listing.viewCounts[id] = views
            }
        }
        return listing
    }

    private static func cleanError(_ line: String) -> String {
        line.replacingOccurrences(of: #"^ERROR:\s*(\[[^\]]+\]\s*)?"#, with: "", options: .regularExpression)
    }

    private static let browserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"

    /// Avatars (and display names) are refreshed every few days.
    private static func avatarIsFresh(in folder: URL) -> Bool {
        let avatarFile = folder.appendingPathComponent("avatar.jpg")
        guard let modified = (try? avatarFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return false }
        return Date().timeIntervalSince(modified) < 3 * 86_400
    }

    private static func fetchPage(_ url: URL, cookie: String? = nil) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(browserAgent, forHTTPHeaderField: "User-Agent")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func saveAvatar(from url: URL?, in folder: URL, name: String, log: (String) -> Void) async {
        if let url, let (imageData, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            try? imageData.write(to: folder.appendingPathComponent("avatar.jpg"), options: .atomic)
        } else {
            log("\(name): couldn't fetch avatar")
        }
    }

    /// First capture group of `pattern` in `text`.
    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// Avatar + display name come from the profile page (not exposed by yt-dlp).
    private static func refreshTikTokProfile(_ creator: Creator, folder: URL, log: (String) -> Void) async {
        guard !avatarIsFresh(in: folder), let html = await fetchPage(creator.profileURL) else { return }

        func jsonString(_ key: String) -> String? {
            guard let range = html.range(of: "\"\(key)\":\"((?:[^\"\\\\]|\\\\.)*)\"", options: .regularExpression) else { return nil }
            let literal = String(html[range].dropFirst(key.count + 3))
            return (try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed)) as? String
        }

        if let nickname = jsonString("nickname") {
            Library.saveProfile(nickname: nickname, in: folder)
        }
        await saveAvatar(from: (jsonString("avatarMedium") ?? jsonString("avatarThumb")).flatMap(URL.init(string:)),
                         in: folder, name: label(creator), log: log)
    }

    /// The channel page gives the channel ID (needed for the Shorts feed; cached in channel_id.txt),
    /// the display name and the avatar. Returns the channel ID.
    private static func refreshYouTubeChannel(_ creator: Creator, folder: URL, log: (String) -> Void) async -> String? {
        let idFile = folder.appendingPathComponent("channel_id.txt")
        let known = creator.username.hasPrefix("UC") ? creator.username
            : (try? String(contentsOf: idFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let known, avatarIsFresh(in: folder) { return known }

        // SOCS skips the cookie-consent interstitial YouTube shows in some regions.
        guard let html = await fetchPage(creator.profileURL, cookie: "SOCS=CAI") else { return known }
        guard let channelID = known ?? firstMatch(#""externalId":"(UC[A-Za-z0-9_-]{22})""#, in: html) else { return nil }
        try? channelID.write(to: idFile, atomically: true, encoding: .utf8)

        if let title = firstMatch(#"<meta property="og:title" content="([^"]*)""#, in: html) {
            Library.saveProfile(nickname: decodeEntities(title), in: folder)
        }
        // The page links a 900px avatar; ask for a smaller one.
        let avatar = firstMatch(#"<meta property="og:image" content="([^"]*)""#, in: html)
            .map { decodeEntities($0).replacingOccurrences(of: #"=s\d+-"#, with: "=s240-", options: .regularExpression) }
        await saveAvatar(from: avatar.flatMap(URL.init(string:)), in: folder, name: label(creator), log: log)
        return channelID
    }

    private static func decodeEntities(_ s: String) -> String {
        [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(s) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

/// Cross-process lock so the app and the scheduled job never download at the same time.
final class DownloadLock {
    private var fd: Int32 = -1

    func tryAcquire() -> Bool {
        fd = open(Paths.lock.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false
        }
        return true
    }

    func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit { release() }
}
