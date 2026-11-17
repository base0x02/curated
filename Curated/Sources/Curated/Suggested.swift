import AppKit
import Foundation
import SwiftUI
import WebKit

/// Suggested short videos: the first few videos of the signed-in TikTok For You feed and YouTube's Shorts shelf.
///
/// Turned on per platform in Settings → Downloads (`AppSettings.suggested`), each with how many unwatched suggestions
/// to keep (3 by default). Each download (the app's Download All, a phone's Update Mac and the overnight job) first
/// clears out watched suggestions, then tops each platform back up from the top of its feed, leaving out videos
/// already suggested, watched, or by a creator already followed.
///
/// Reading the feeds needs the user's sign-in:
/// - YouTube: the cookies of the browser picked for YouTube (`youtubeCookieBrowser`), exported by yt-dlp and sent with
///   a plain request for the home page, whose Shorts shelf lists Shorts in feed order.
/// - TikTok: the For You feed only comes from TikTok's signed web API, so it's read by a hidden web view
///   (`TikTokFeedReader`) that loads tiktok.com like a browser and notes what the page itself fetches. The web view
///   keeps its own sign-in (`tiktokStore`); when it has none, the cookies of the TikTok browser are copied into it.
///   When those don't sign it in either, Settings and an alert offer `TikTokSignInSheet` to sign in there.
/// How the last look went (signed in, signed out, locked out) is in `suggested.json` (`SuggestedStatus`), so a
/// problem the overnight job met is shown when the app next opens.
///
/// Each video goes into its creator's folder, `suggested-tiktok@<username>/` or `suggested-youtube@<handle>/`, laid
/// out like any creator's. They're made up as `Creator`s with `suggested == true` when the library is scanned
/// (`AppModel.suggestedLibraries`), never saved in `Config.creators`. `suggested@tiktok/` and `suggested@youtube/`
/// hold each feed's `archive.txt` (every video ever suggested, so none comes back) and a staging folder for downloads.
/// Following a suggested creator (`AppModel.followSuggested`, also `POST /suggested/follow` from phones) adds them as
/// a plain creator and moves their videos into the new creator's folder.
enum Suggested {
    /// Bright pink: the dashed ring around suggested creators' avatars, here and on phones.
    static let pink = Color(red: 0xFF / 255, green: 0x8E / 255, blue: 0xEA / 255)
    static let counts = [1, 2, 3, 5, 10, 15, 20]

    static let platforms: [Platform] = [.tiktok, .youtube]

    /// "suggested-tiktok@" or "suggested-youtube@": a suggested creator's key and folder start with this.
    static func folderPrefix(_ platform: Platform) -> String { "suggested-\(platform.rawValue)@" }

    /// The feed's own folder (archive and staging), and its key in `RunState` and `AppModel.statuses`.
    static func feedID(_ platform: Platform) -> String { "suggested@\(platform.rawValue)" }

    static func feedFolder(_ platform: Platform, settings: AppSettings) -> URL {
        Library.folder(for: feedID(platform), settings: settings)
    }

    /// Every suggested creator of `platform` with a folder in the library, made up as a creator, whether or not the
    /// feature is on (the caller decides what's shown).
    static func scan(_ platform: Platform, settings: AppSettings) -> [CreatorLibrary] {
        creatorFolders(platform, settings: settings)
            .map { Library.scan(creator(platform, username: String($0.lastPathComponent.dropFirst(folderPrefix(platform).count))),
                                settings: settings) }
            .filter { !$0.videos.isEmpty }
    }

    static func creator(_ platform: Platform, username: String) -> Creator {
        var creator = Creator(username: username, days: 1, platform: platform)
        creator.suggested = true
        return creator
    }

    /// Whether a library key is a suggested creator's.
    static func isSuggestedID(_ id: String) -> Bool { platforms.contains { id.hasPrefix(folderPrefix($0)) } }

    private static func creatorFolders(_ platform: Platform, settings: AppSettings) -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: settings.libraryURL, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { $0.lastPathComponent.hasPrefix(folderPrefix(platform)) }
    }

    /// Every suggested video of `platform` on disk.
    static func videoCount(_ platform: Platform, settings: AppSettings) -> Int {
        creatorFolders(platform, settings: settings).reduce(0) { $0 + Library.videoFiles(in: $1).count }
    }

    /// Moves every suggested creator's folder of `platform` to the Trash. The feed's archive stays, so nothing comes
    /// back if it's turned on again. Returns how many videos went.
    @discardableResult
    static func removeAll(_ platform: Platform, settings: AppSettings) -> Int {
        var removed = 0
        for folder in creatorFolders(platform, settings: settings) {
            let count = Library.videoFiles(in: folder).count
            if (try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)) != nil { removed += count }
        }
        try? FileManager.default.removeItem(at: feedFolder(platform, settings: settings).appendingPathComponent("staging"))
        return removed
    }

    // MARK: Status

    /// Saves how a look at `platform`'s feed went.
    static func record(_ status: SuggestedStatus, for platform: Platform) {
        var all = SuggestedStatus.loadAll()
        all[platform.rawValue] = status
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(all).write(to: Paths.suggested, options: .atomic)
    }

    // MARK: Refresh

    /// One video found in a feed. `author` is known for TikTok (from the feed) and found out on download for YouTube.
    struct FeedItem: Equatable {
        let id: String
        var author: String?
    }

    /// What reading a feed found: videos in feed order, or why there are none.
    enum FeedRead {
        case videos([FeedItem])
        case signedOut(String)
        case locked(String)
        case failed(String)
    }

    /// Takes watched suggestions away (bookmarks stay) and tops `platform` back up to its count from the top of its
    /// feed. `readTikTok` reads the For You feed (`TikTokFeedReader.read`), given how many videos to look through.
    static func refresh(_ platform: Platform, settings: AppSettings, followed: [Creator], runner: ProcessRunner,
                        log: @escaping (String) -> Void) async -> DownloadResult {
        let name = "Suggested \(platform.name)"
        var result = DownloadResult()
        result.removed = clearWatched(platform, settings: settings)
        let keep = settings.suggested.count(platform)
        let played = Set(PlayedStore.load().filter(\.value.played).keys)
        let bookmarked = BookmarkStore.bookmarkedIDs()
        let unwatched = creatorFolders(platform, settings: settings).reduce(0) { total, folder in
            total + Library.videoFiles(in: folder).count { !played.contains($0.id) && !bookmarked.contains($0.id) }
        }
        let needed = keep - unwatched
        guard needed > 0 else {
            log("\(name): \(unwatched) unwatched, keeping \(keep). Nothing to download")
            return result
        }
        log("\(name): \(unwatched) of \(keep) unwatched, reading your feed for \(needed) more…")

        let feedFolder = feedFolder(platform, settings: settings)
        try? FileManager.default.createDirectory(at: feedFolder, withIntermediateDirectories: true)
        let archive = feedFolder.appendingPathComponent("archive.txt")
        let archived = Set(((try? String(contentsOf: archive, encoding: .utf8)) ?? "")
            .split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) })
        let followedNames = Set(followed.filter { $0.platform == platform && !$0.playlist }.map { $0.username.lowercased() })

        let read: FeedRead
        switch platform {
        case .tiktok: read = await TikTokFeedReader.read(settings: settings, wanted: needed + archived.count + 10)
        default: read = await youTubeFeed(settings: settings)
        }
        if runner.isCancelled { return DownloadResult(removed: result.removed, error: "Cancelled") }
        let items: [FeedItem]
        switch read {
        case .videos(let found):
            items = found
        case .signedOut(let message):
            record(SuggestedStatus(state: .signedOut, message: message), for: platform)
            log("\(name): \(message)")
            result.error = message
            return result
        case .locked(let message):
            record(SuggestedStatus(state: .locked, message: message), for: platform)
            log("\(name): \(message)")
            result.error = message
            return result
        case .failed(let message):
            record(SuggestedStatus(state: .failed, message: message), for: platform)
            log("\(name): \(message)")
            result.error = message
            return result
        }
        let fresh = items.filter { item in
            !archived.contains(item.id) && !played.contains(item.id)
                && !(item.author.map { followedNames.contains($0.lowercased()) } ?? false)
        }
        let picked = Array(fresh.prefix(needed))
        DownloadLog.detail("\(name): \(items.count) in the feed, \(fresh.count) not seen before, picked \(picked.map(\.id).joined(separator: " "))")
        record(SuggestedStatus(state: .ok, message: nil, found: items.count), for: platform)
        guard !picked.isEmpty else {
            log("\(name): nothing new in your feed right now")
            return result
        }
        let downloaded = await download(picked, platform: platform, settings: settings, followed: followed,
                                        runner: runner, log: log)
        result.newVideos = downloaded.newVideos
        result.error = downloaded.error
        log("\(name): done — \(result.newVideos) new" + (result.error.map { " (\($0))" } ?? ""))
        return result
    }

    /// Trashes watched suggestions that aren't bookmarked, and the folders of creators left with no videos.
    private static func clearWatched(_ platform: Platform, settings: AppSettings) -> Int {
        let played = Set(PlayedStore.load().filter(\.value.played).keys)
        let bookmarked = BookmarkStore.bookmarkedIDs()
        let fm = FileManager.default
        var removed = 0
        for folder in creatorFolders(platform, settings: settings) {
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where Library.videoExtensions.contains(file.pathExtension.lowercased()) {
                guard let (_, id) = Library.parseFilename(file), played.contains(id), !bookmarked.contains(id) else { continue }
                if (try? fm.trashItem(at: file, resultingItemURL: nil)) != nil { removed += 1 }
                try? fm.removeItem(at: file.deletingPathExtension().appendingPathExtension("jpg"))
            }
            if Library.videoFiles(in: folder).isEmpty { try? fm.removeItem(at: folder) }
        }
        return removed
    }

    /// Downloads the picks into the staging folder, then moves each into its creator's folder (or, for a YouTube
    /// creator already followed, into theirs), fetching new creators' names and avatars.
    private static func download(_ items: [FeedItem], platform: Platform, settings: AppSettings, followed: [Creator],
                                 runner: ProcessRunner, log: @escaping (String) -> Void) async -> DownloadResult {
        guard let ytdlp = Tools.find("yt-dlp") else {
            return DownloadResult(error: "yt-dlp not found. Install it with: brew install yt-dlp")
        }
        let fm = FileManager.default
        let feedFolder = feedFolder(platform, settings: settings)
        let staging = feedFolder.appendingPathComponent("staging", isDirectory: true)
        try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let urls = items.map { item in
            platform == .tiktok
                ? "https://www.tiktok.com/@\(item.author ?? "_")/video/\(item.id)"
                : "https://www.youtube.com/shorts/\(item.id)"
        }
        let batch = fm.temporaryDirectory.appendingPathComponent("curated-suggested-\(UUID().uuidString).txt")
        try? urls.joined(separator: "\n").write(to: batch, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: batch) }
        let browser = platform == .youtube ? settings.youtubeCookieBrowser : settings.cookieBrowser
        let cookieArgs = browser == .none ? [] : ["--cookies-from-browser", browser.rawValue]
        let metaFile = staging.appendingPathComponent("videos.jsonl")
        var errors: [String] = []
        _ = await runner.run(ytdlp, [
            "--newline", "--no-progress", "--no-warnings",
            "-f", "b[vcodec!=none]/bv*+ba", "-S", "lang,vcodec:h264,res,br",
            "--merge-output-format", "mp4",
            "--download-archive", feedFolder.appendingPathComponent("archive.txt").path,
            "-o", staging.appendingPathComponent("%(timestamp)s_%(id)s.%(ext)s").path,
            "--print-to-file",
            "after_move:%(.{id,title,description,timestamp,upload_date,duration,view_count,uploader,uploader_id,channel,channel_id})j",
            metaFile.path,
            "-a", batch.path,
        ] + cookieArgs) { line in
            if line.hasPrefix("ERROR"), !line.contains("Requested format is not available") { errors.append(line) }
            return true
        }

        struct Meta: Decodable {
            let id: String
            let timestamp: Double?
            let upload_date: String?
            let uploader: String?
            let uploader_id: String?
            let channel: String?
            let channel_id: String?
        }
        var result = DownloadResult()
        let lines = ((try? String(contentsOf: metaFile, encoding: .utf8)) ?? "").split(separator: "\n")
        var newFolders: [URL: Creator] = [:]
        for line in lines {
            guard let meta = try? JSONDecoder().decode(Meta.self, from: Data(line.utf8)) else { continue }
            let author: String?
            if platform == .tiktok {
                author = items.first { $0.id == meta.id }?.author ?? meta.uploader
            } else {
                author = (meta.uploader_id?.hasPrefix("@") == true ? meta.uploader_id.map { String($0.dropFirst()) } : nil)
                    ?? meta.channel_id
            }
            guard let author = author?.lowercased(), !author.isEmpty, !author.contains("/") else { continue }
            let followedCreator = followed.first { $0.platform == platform && !$0.playlist && $0.username.lowercased() == author }
            let creator = followedCreator ?? self.creator(platform, username: author)
            let folder = Library.folder(for: creator.id, settings: settings)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var moved = false
            for file in (try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? [] {
                let base = file.deletingPathExtension().lastPathComponent
                guard base.hasSuffix("_\(meta.id)") else { continue }
                // yt-dlp names a video it can't date "NA_<id>": use the upload day, or now.
                var name = file.lastPathComponent
                if base.hasPrefix("NA_") {
                    let date = meta.upload_date.flatMap(uploadDay) ?? Date().timeIntervalSince1970
                    name = "\(Int(date))_\(meta.id).\(file.pathExtension)"
                }
                let target = folder.appendingPathComponent(name)
                try? fm.removeItem(at: target)
                if (try? fm.moveItem(at: file, to: target)) != nil,
                   Library.videoExtensions.contains(file.pathExtension.lowercased()) { moved = true }
            }
            guard moved else { continue }
            result.newVideos += 1
            append(String(line), to: folder.appendingPathComponent("videos.jsonl"))
            if followedCreator == nil, !fm.fileExists(atPath: folder.appendingPathComponent("profile.json").path) {
                Library.saveProfile(nickname: meta.channel ?? meta.uploader, in: folder)
                newFolders[folder] = creator
            } else if followedCreator != nil {
                // Already followed: the creator's own download would have fetched it, so it counts as theirs.
                append("\(platform.rawValue) \(meta.id)", to: folder.appendingPathComponent("archive.txt"))
            }
            log("Suggested \(platform.name): @\(author)")
        }
        try? fm.removeItem(at: metaFile)
        for (folder, creator) in newFolders where !runner.isCancelled {
            await DownloadEngine.refreshProfile(creator, folder: folder, log: log)
        }
        if settings.evenOutVolume {
            for folder in Set(newFolders.keys) where !runner.isCancelled {
                await Loudness.normalize(folder: folder, runner: runner, log: log, label: "Suggested")
            }
        }
        if runner.isCancelled { result.error = "Cancelled" }
        else if let error = errors.last { result.error = DownloadEngine.cleanError(error) }
        return result
    }

    private static func uploadDay(_ day: String) -> TimeInterval? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHH"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: day + "12")?.timeIntervalSince1970
    }

    static func append(_ line: String, to file: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Following

    /// Moves a suggested creator's folder into `creator`'s (made if missing), recording the videos in its archive so
    /// its own download doesn't fetch them again.
    static func moveToFollowed(_ suggested: Creator, into creator: Creator, settings: AppSettings) {
        let fm = FileManager.default
        let from = Library.folder(for: suggested.id, settings: settings)
        let to = Library.folder(for: creator.id, settings: settings)
        guard fm.fileExists(atPath: from.path) else { return }
        let ids = Library.videoFiles(in: from).map(\.id)
        if !fm.fileExists(atPath: to.path) {
            try? fm.moveItem(at: from, to: to)
        } else {
            for file in (try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)) ?? [] {
                let target = to.appendingPathComponent(file.lastPathComponent)
                switch file.lastPathComponent {
                case "videos.jsonl":
                    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                    for line in text.split(separator: "\n") { append(String(line), to: target) }
                case "archive.txt":
                    continue
                default:
                    if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: file, to: target) }
                }
            }
            try? fm.removeItem(at: from)
        }
        for id in ids { append("\(creator.platform.rawValue) \(id)", to: to.appendingPathComponent("archive.txt")) }
    }

    // MARK: Cookies

    /// The cookies `browser` holds for sites ending in `domain`, through yt-dlp (which can read every browser's
    /// cookie store). Nothing goes over the network: yt-dlp writes its cookie jar and then fails on a made-up URL.
    /// The jar has every site's cookies, so it lives in a private temporary folder only as long as it's read.
    static func browserCookies(_ browser: CookieBrowser, domain: String) async -> [HTTPCookie] {
        guard browser != .none, let ytdlp = Tools.find("yt-dlp") else { return [] }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("curated-cookies-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil
        else { return [] }
        defer { try? fm.removeItem(at: dir) }
        let jar = dir.appendingPathComponent("cookies.txt")
        _ = await ProcessRunner().run(ytdlp, ["--ignore-config", "--no-warnings", "--cookies-from-browser", browser.rawValue,
                                              "--cookies", jar.path, "--simulate", "curated-cookie-export:"]) { _ in true }
        let text = (try? String(contentsOf: jar, encoding: .utf8)) ?? ""
        return parseCookieJar(text, domain: domain)
    }

    /// A Netscape cookie file's cookies for `domain` and its subdomains.
    static func parseCookieJar(_ text: String, domain: String) -> [HTTPCookie] {
        text.split(separator: "\n").compactMap { raw in
            var line = String(raw)
            var httpOnly = false
            if line.hasPrefix("#HttpOnly_") {
                line.removeFirst("#HttpOnly_".count)
                httpOnly = true
            } else if line.hasPrefix("#") {
                return nil
            }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 7 else { return nil }
            let host = fields[0].trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host == domain || host.hasSuffix("." + domain) else { return nil }
            var properties: [HTTPCookiePropertyKey: Any] = [.domain: fields[0], .path: fields[2], .name: fields[5], .value: fields[6]]
            if fields[3] == "TRUE" { properties[.secure] = "TRUE" }
            if let expires = Double(fields[4]), expires > 0 { properties[.expires] = Date(timeIntervalSince1970: expires) }
            if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }

    // MARK: YouTube

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// The Shorts on the signed-in YouTube home page, in the order its Shorts shelf shows them.
    static func youTubeFeed(settings: AppSettings) async -> FeedRead {
        #if DEBUG
        // CURATED_TEST_SUGGESTED_YOUTUBE=<id,id,…> stands in for the feed; "signedOut" or "locked" for those.
        if let test = ProcessInfo.processInfo.environment["CURATED_TEST_SUGGESTED_YOUTUBE"] {
            if test == "signedOut" { return .signedOut("You're signed out of YouTube (test).") }
            if test == "locked" { return .locked("YouTube wants to check you're not a bot (test).") }
            return .videos(test.split(separator: ",").map { FeedItem(id: String($0)) })
        }
        #endif
        let browser = settings.youtubeCookieBrowser
        guard browser != .none else {
            return .signedOut("Curated needs your YouTube sign-in for suggested Shorts. Pick the browser you watch "
                              + "YouTube in under Settings → Downloads → Sign-In.")
        }
        let cookies = await browserCookies(browser, domain: "youtube.com")
        guard !cookies.isEmpty else {
            return .signedOut("Curated couldn't read \(browser.label)'s YouTube cookies. Sign in to YouTube in \(browser.label).")
        }
        var request = URLRequest(url: URL(string: "https://www.youtube.com/")!, timeoutInterval: 20)
        request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = false
        var data = Data(), status = 0
        for attempt in 1...2 {
            do {
                let (body, response) = try await URLSession.shared.data(for: request)
                data = body
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                break
            } catch {
                DownloadLog.detail("Suggested YouTube: home page request \(attempt) failed: \(error.localizedDescription)")
                if attempt == 2 { return .failed("Couldn't reach YouTube") }
            }
        }
        let html = String(decoding: data, as: UTF8.self)
        if status == 429 || html.contains("not a bot") || html.contains("unusual traffic") {
            return .locked("YouTube is asking whether you're a bot. Open YouTube in \(browser.label), sign in again and "
                           + "watch something, then try again.")
        }
        guard status == 200 else { return .failed("YouTube's home page returned HTTP \(status)") }
        if html.contains("\"LOGGED_IN\":false") || !html.contains("\"LOGGED_IN\":true") {
            return .signedOut("You're signed out of YouTube in \(browser.label). Sign in there, then try again.")
        }
        var seen: Set<String> = []
        let regex = try! NSRegularExpression(pattern: #""/shorts/([A-Za-z0-9_-]{11})""#)
        let ids = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }.filter { seen.insert($0).inserted }
        if ids.isEmpty {
            return .failed("Your YouTube home page has no Shorts shelf right now. YouTube only shows it with your watch "
                           + "history on.")
        }
        return .videos(ids.map { FeedItem(id: $0) })
    }
}

/// How the last look at a suggested feed went, per platform, in `suggested.json`.
struct SuggestedStatus: Codable, Equatable {
    enum State: String, Codable {
        case ok, signedOut, locked, failed
    }
    var state: State
    var message: String?
    var at = Date()
    /// How many videos the feed listed.
    var found: Int?

    var needsSignIn: Bool { state == .signedOut || state == .locked }

    static func loadAll() -> [String: SuggestedStatus] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Paths.suggested),
              let all = try? decoder.decode([String: SuggestedStatus].self, from: data) else { return [:] }
        return all
    }
}

/// Settings → Downloads → Suggested Short Videos.
struct SuggestedSettings: Codable, Equatable {
    var tiktok = false
    var youtube = false
    var tiktokCount = 3
    var youtubeCount = 3

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tiktok = try c.decodeIfPresent(Bool.self, forKey: .tiktok) ?? false
        youtube = try c.decodeIfPresent(Bool.self, forKey: .youtube) ?? false
        tiktokCount = try c.decodeIfPresent(Int.self, forKey: .tiktokCount) ?? 3
        youtubeCount = try c.decodeIfPresent(Int.self, forKey: .youtubeCount) ?? 3
    }

    var anyOn: Bool { tiktok || youtube }

    func isOn(_ platform: Platform) -> Bool {
        switch platform {
        case .tiktok: tiktok
        case .youtube: youtube
        case .vine: false
        }
    }

    func count(_ platform: Platform) -> Int { max(1, platform == .tiktok ? tiktokCount : youtubeCount) }

    mutating func set(_ platform: Platform, on: Bool) {
        if platform == .tiktok { tiktok = on } else if platform == .youtube { youtube = on }
    }

    mutating func set(_ platform: Platform, count: Int) {
        if platform == .tiktok { tiktokCount = max(1, count) } else if platform == .youtube { youtubeCount = max(1, count) }
    }
}

// MARK: - TikTok

/// Reads the For You feed in a hidden web view signed in to TikTok. TikTok only hands out its feed to its own web
/// app, so the page loads as it would in a browser, and a script noted before it runs reports each batch of videos
/// the page fetches (`/api/recommend/item_list/`). Videos never play: media needs a click.
@MainActor
final class TikTokFeedReader: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    /// The web view's own cookies and storage, kept between runs, shared with `TikTokSignInSheet`.
    static let storeID = UUID(uuidString: "6B1B3F0E-6C3A-4E43-9F4E-2D7C1E5A9C11")!
    static var store: WKWebsiteDataStore { WKWebsiteDataStore(forIdentifier: storeID) }
    static let forYouURL = URL(string: "https://www.tiktok.com/foryou")!
    static let loginURL = URL(string: "https://www.tiktok.com/login")!

    /// Wraps fetch and XMLHttpRequest to pass on the feed's batches: id, author, and whether it's an ad or a photo post.
    static let hook = """
    (function(){
      const post = (m) => { try { window.webkit.messageHandlers.feed.postMessage(m); } catch (e) {} };
      const report = (url, text) => {
        if (!String(url).includes('/api/recommend/item_list')) return;
        try {
          const list = (JSON.parse(text).itemList || []).map(i => ({
            id: String(i.id || ''), author: (i.author && i.author.uniqueId) || '',
            ad: !!(i.isAd || i.is_ad), photo: !!i.imagePost, live: !!i.liveRoomInfo }));
          post(JSON.stringify(list));
        } catch (e) { post('[]'); }
      };
      const ofetch = window.fetch;
      window.fetch = function(input, init) {
        const url = (typeof input === 'string') ? input : ((input && input.url) || '');
        const p = ofetch.apply(this, arguments);
        if (String(url).includes('item_list')) p.then(r => r.clone().text().then(t => report(url, t))).catch(() => {});
        return p;
      };
      const open = XMLHttpRequest.prototype.open, send = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(m, u) { this.__curatedURL = u; return open.apply(this, arguments); };
      XMLHttpRequest.prototype.send = function() {
        if (String(this.__curatedURL).includes('item_list')) this.addEventListener('load', () => report(this.__curatedURL, this.responseText));
        return send.apply(this, arguments);
      };
    })();
    """

    /// Who's signed in, and whether TikTok is showing a check or a ban rather than the feed.
    static let stateScript = """
    (() => {
      let uid = '';
      try {
        const d = JSON.parse(document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__').textContent);
        const user = d.__DEFAULT_SCOPE__['webapp.app-context'].user;
        uid = (user && user.uid) || '';
      } catch (e) {}
      const text = document.body ? document.body.innerText : '';
      return JSON.stringify({
        uid: String(uid),
        captcha: !!document.querySelector('#captcha-verify-container, #captcha_container, .captcha-verify-container, [class*="captcha_verify"]'),
        banned: /account (was|has been) (permanently )?(banned|suspended)/i.test(text)
      });
    })()
    """

    private var items: [Suggested.FeedItem] = []
    private var batches = 0
    private var web: WKWebView?
    private var window: NSWindow?

    /// The first `wanted` or so videos of the For You feed, or why they couldn't be read. When the web view isn't
    /// signed in and the TikTok browser is, that browser's cookies are copied in first.
    static func read(settings: AppSettings, wanted: Int) async -> Suggested.FeedRead {
        #if DEBUG
        // CURATED_TEST_SUGGESTED_TIKTOK=<author:id,…> stands in for the feed; "signedOut" or "locked" for those.
        if let test = ProcessInfo.processInfo.environment["CURATED_TEST_SUGGESTED_TIKTOK"] {
            if test == "signedOut" { return .signedOut("You're signed out of TikTok (test).") }
            if test == "locked" { return .locked("TikTok wants to check you're not a robot (test).") }
            return .videos(test.split(separator: ",").compactMap { pair in
                let parts = pair.split(separator: ":")
                return parts.count == 2 ? Suggested.FeedItem(id: String(parts[1]), author: String(parts[0])) : nil
            })
        }
        #endif
        let hasSession = await hasSessionCookie()
        if !hasSession, settings.cookieBrowser != .none {
            await importCookies(from: settings.cookieBrowser)
        }
        let nowSignedIn = await hasSessionCookie()
        DownloadLog.detail("Suggested TikTok: signed in before \(hasSession), now \(nowSignedIn)")
        var outcome = await TikTokFeedReader().load(wanted: wanted)
        // Signed out with the web view's own sign-in: the browser's may be newer.
        if case .signedOut = outcome, hasSession, settings.cookieBrowser != .none {
            await importCookies(from: settings.cookieBrowser)
            outcome = await TikTokFeedReader().load(wanted: wanted)
        }
        return outcome
    }

    static func hasSessionCookie() async -> Bool {
        await store.httpCookieStore.allCookies().contains { $0.name == "sessionid" && $0.domain.hasSuffix("tiktok.com") && !$0.value.isEmpty }
    }

    static func importCookies(from browser: CookieBrowser) async {
        let cookies = await Suggested.browserCookies(browser, domain: "tiktok.com")
        let cookieStore = store.httpCookieStore
        for cookie in cookies { await cookieStore.setCookie(cookie) }
        DownloadLog.detail("Suggested TikTok: copied \(cookies.count) cookies from \(browser.label)")
    }

    /// Forgets the web view's TikTok sign-in.
    static func signOut() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    private func load(wanted: Int) async -> Suggested.FeedRead {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.store
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(self, name: "feed")
        config.userContentController.addUserScript(WKUserScript(source: Self.hook, injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: false))
        // Off screen, but in a window, so the page runs as it would in a browser tab.
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 420, height: 800), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 800), configuration: config)
        web.customUserAgent = Suggested.safariUserAgent
        web.navigationDelegate = self
        window.contentView?.addSubview(web)
        window.orderBack(nil)
        self.window = window
        self.web = web
        defer {
            web.stopLoading()
            config.userContentController.removeScriptMessageHandler(forName: "feed")
            window.orderOut(nil)
            window.close()
            self.web = nil
            self.window = nil
        }
        web.load(URLRequest(url: Self.forYouURL))

        let started = Date()
        var state: (uid: String, captcha: Bool, banned: Bool)?
        while Date().timeIntervalSince(started) < 30 {
            try? await Task.sleep(for: .seconds(1))
            if items.count >= wanted { break }
            let elapsed = Date().timeIntervalSince(started)
            // Let the page settle, then see who it thinks is signed in.
            if elapsed > 6, items.isEmpty {
                state = await pageState()
                // A check or a ban won't go away by waiting; a missing user may just be the page still loading.
                if let state, state.captcha || state.banned || (state.uid.isEmpty && elapsed > 15) { break }
            }
            // Ask for the next batches the way scrolling does.
            if batches > 0, elapsed > 4 {
                _ = try? await web.evaluateJavaScript("""
                    document.dispatchEvent(new KeyboardEvent('keydown', {key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true}));
                    window.scrollBy(0, window.innerHeight);
                    """)
            }
        }
        if !items.isEmpty { return .videos(items) }
        let final = await pageState() ?? state
        DownloadLog.detail("Suggested TikTok: no feed after \(Int(Date().timeIntervalSince(started))) s, \(batches) batches, "
                           + "page \(web.url?.absoluteString ?? "none"), uid \(final?.uid ?? "?"), captcha \(final?.captcha ?? false)")
        if final?.banned == true {
            return .locked("TikTok says your account is banned or suspended. Suggested TikTok videos are paused.")
        }
        if final?.captcha == true {
            return .locked("TikTok wants to check you're not a robot. Open TikTok in Curated to finish the check.")
        }
        if final?.uid.isEmpty ?? true {
            return .signedOut("Curated isn't signed in to TikTok. Sign in to TikTok in Curated to get suggested videos.")
        }
        return .failed("TikTok's For You feed didn't load. Try again later.")
    }

    private func pageState() async -> (uid: String, captcha: Bool, banned: Bool)? {
        guard let web, let text = try? await web.evaluateJavaScript(Self.stateScript) as? String,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        return ((object["uid"] as? String) ?? "", object["captcha"] as? Bool ?? false, object["banned"] as? Bool ?? false)
    }

    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        struct Entry: Decodable { let id: String; let author: String; let ad: Bool; let photo: Bool; let live: Bool }
        MainActor.assumeIsolated {
            guard let text = message.body as? String else { return }
            let entries = (try? JSONDecoder().decode([Entry].self, from: Data(text.utf8))) ?? []
            batches += 1
            for entry in entries where !entry.ad && !entry.photo && !entry.live && !entry.id.isEmpty && !entry.author.isEmpty {
                if !items.contains(where: { $0.id == entry.id }) {
                    items.append(Suggested.FeedItem(id: entry.id, author: entry.author.lowercased()))
                }
            }
        }
    }
}

/// Signing in to TikTok, or finishing a check it asks for, in the web view `TikTokFeedReader` reads the feed with.
struct TikTokSignInSheet: View {
    var url: URL = TikTokFeedReader.loginURL
    var onDone: () -> Void
    @State private var signedIn: Bool?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to TikTok").font(.headline)
                    Text("Curated reads the first few videos of your For You feed with this sign-in. It stays on this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if signedIn == true {
                    Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button("Done") { onDone() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
            Divider()
            TikTokWebView(url: url)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 640, idealHeight: 760)
        .task {
            while !Task.isCancelled {
                signedIn = await TikTokFeedReader.hasSessionCookie()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private struct TikTokWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = TikTokFeedReader.store
        let web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = Suggested.safariUserAgent
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
}

// MARK: - App

/// The Suggested card, alongside the category ids, in a mix's `picked` cards and the playback rules.
let suggestedCard = "suggested"

/// What the app asks about suggestions.
enum SuggestedPrompt: Identifiable, Equatable {
    /// The feed needs a sign-in, or the account is locked out (`locked`).
    case signIn(Platform, message: String, locked: Bool)
    /// The platform's suggestions are off but some of its videos are still here.
    case leftovers(Platform, count: Int)
    /// Turning the platform off would delete this many videos.
    case turnOff(Platform, count: Int)

    var id: String {
        switch self {
        case .signIn(let p, _, _): "signIn-\(p.rawValue)"
        case .leftovers(let p, _): "leftovers-\(p.rawValue)"
        case .turnOff(let p, _): "turnOff-\(p.rawValue)"
        }
    }
}

extension AppModel {
    /// Every suggestion as one "creator", so Automix plays them about as often as one creator.
    var suggestedMixLibrary: CreatorLibrary {
        CreatorLibrary(creator: Suggested.creator(.tiktok, username: "all"), nickname: "Suggested", avatar: nil,
                       videos: suggestedLibraries.flatMap(\.videos).sorted { $0.date > $1.date })
    }

    func suggestedStatus(_ platform: Platform) -> SuggestedStatus? { suggestedStatus[platform.rawValue] }

    /// Turns a platform's suggestions on, or asks before turning them off when that would delete videos.
    func setSuggested(_ platform: Platform, on: Bool) {
        if on {
            settings.suggested.set(platform, on: true)
            return
        }
        let count = Suggested.videoCount(platform, settings: settings)
        if count > 0 {
            suggestedPrompt = .turnOff(platform, count: count)
        } else {
            settings.suggested.set(platform, on: false)
        }
    }

    /// Turns a platform's suggestions off and moves its suggested videos to the Trash. Phones drop them at their next sync.
    func turnOffSuggested(_ platform: Platform) {
        settings.suggested.set(platform, on: false)
        deleteSuggested(platform)
    }

    func deleteSuggested(_ platform: Platform) {
        let removed = Suggested.removeAll(platform, settings: settings)
        if removed > 0 { appendLog("Suggested \(platform.name): deleted \(removed) video\(removed == 1 ? "" : "s")") }
        reloadLibrary()
    }

    /// At launch: a platform with suggestions off that still has suggested videos (turned off by an older build, or
    /// in config.json) asks whether to delete them.
    func checkSuggestedLeftovers() {
        guard suggestedPrompt == nil else { return }
        for platform in Suggested.platforms where !settings.suggested.isOn(platform) {
            let count = Suggested.videoCount(platform, settings: settings)
            if count > 0 {
                suggestedPrompt = .leftovers(platform, count: count)
                return
            }
        }
    }

    /// Asks the user to sign in when a platform with suggestions on was last found signed out or locked out, once
    /// for each time that was found (here, or by the overnight job).
    func promptSignInIfNeeded() {
        guard suggestedPrompt == nil else { return }
        for platform in Suggested.platforms where settings.suggested.isOn(platform) {
            guard let status = suggestedStatus(platform), status.needsSignIn,
                  status.at > (promptedProblemAt ?? .distantPast) else { continue }
            setPromptedProblemAt(status.at)
            suggestedPrompt = .signIn(platform, message: status.message ?? "", locked: status.state == .locked)
            return
        }
    }

    /// Opens what fixes a sign-in: TikTok's sheet in Curated, or YouTube in the browser Curated borrows it from.
    func openSignIn(_ platform: Platform, locked: Bool = false) {
        switch platform {
        case .tiktok:
            tiktokSignInURL = locked ? TikTokFeedReader.forYouURL : TikTokFeedReader.loginURL
        default:
            let url = URL(string: "https://www.youtube.com/")!
            let app = settings.youtubeCookieBrowser.applicationURL
            if let app {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Adds a suggested creator as a plain creator in `category` and moves their suggestions into its folder, so
    /// they stay where they are on phones too. Starts downloading them when nothing else is. Returns what happened.
    @discardableResult
    func followSuggested(_ creatorID: String, category: UUID?) -> (ok: Bool, message: String, creatorID: String?) {
        guard let library = suggestedLibraries.first(where: { $0.id == creatorID })
                ?? Suggested.platforms.flatMap({ Suggested.scan($0, settings: settings) }).first(where: { $0.id == creatorID })
        else { return (false, "That suggested creator isn't on your Mac anymore.", nil) }
        let suggested = library.creator
        let name = library.displayName
        let validCategory = categories.contains { $0.id == category } ? category : nil
        var creator = config.creators.first { $0.platform == suggested.platform && !$0.playlist
            && $0.username.lowercased() == suggested.username.lowercased() }
        let alreadyFollowed = creator != nil
        if creator == nil {
            creator = Creator(username: suggested.username, days: settings.defaultDays, category: validCategory,
                              platform: suggested.platform)
        }
        guard let creator else { return (false, "Couldn't add \(name).", nil) }
        if isDownloading {
            // A download may be writing into the suggested folder: move it once that's done.
            pendingFollows.append((suggested, creator))
        } else {
            Suggested.moveToFollowed(suggested, into: creator, settings: settings)
        }
        if !alreadyFollowed { config.creators.append(creator) }
        reloadLibrary()
        appendLog("Followed \(name) from Suggested" + (validCategory.flatMap { id in categories.first { $0.id == id }?.name }.map { " (in \($0))" } ?? ""))
        if !isDownloading { download([creator]) }
        return (true, alreadyFollowed ? "\(name) was already one of your creators." : "Added \(name) to your creators.", creator.id)
    }

    /// Follows waiting for a download to finish before their videos move.
    func finishPendingFollows() {
        guard !pendingFollows.isEmpty else { return }
        for (suggested, creator) in pendingFollows { Suggested.moveToFollowed(suggested, into: creator, settings: settings) }
        pendingFollows = []
        reloadLibrary()
    }

    private func setPromptedProblemAt(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "suggestedPromptedAt")
        markPrompted(date)
    }
}

extension CookieBrowser {
    /// The browser's app, to open a sign-in page in it.
    var applicationURL: URL? { bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } }
}
