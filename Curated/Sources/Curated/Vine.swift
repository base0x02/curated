import AppKit
import CryptoKit
import Foundation
import SwiftUI

/// Vine classics, from divine.video's archive of Vine (experimental, `AppSettings.vineEnabled`).
///
/// There are no Vine creators to pick: Curated keeps `vineBatchSize` unwatched Vines (bookmarks aside), and each
/// download tops that back up with the next videos from the classics feed (most-looped first) that haven't been
/// downloaded before. Each video goes into its author's folder,
/// `vine@<Vine user ID>/`, laid out like a creator's (videos named `<timestamp>_<Vine ID>.mp4`, `videos.jsonl`,
/// `profile.json`, `avatar.jpg`), plus the video's thumbnail beside it as a poster. The authors are made up as
/// `Creator`s with `platform == .vine` when the library is scanned, and never saved in `Config.creators`.
///
/// `vine@classics/` holds the feed's own state: `archive.txt` (every Vine ID downloaded, so a deleted video never
/// comes back) and `cursor.txt` (where in the feed the next download starts). Its download results are in
/// `RunState` under `Vine.feedID`.
///
/// Vines are short videos, but stay out of Top lists and the age-based cleanup (they're all years old). Phones get
/// them only when they ask (`/manifest?…&vine=1`, see PhoneSync.swift).
/// The main Automix and the Funny category's Automix mix them in as if Vine were one more creator.
enum Vine {
    /// The feed's folder, and its key in `RunState` and `AppModel.statuses`. TikTok names can't contain "@", and
    /// Vine user IDs are numbers, so it clashes with neither.
    static let feedID = "vine@classics"
    static let folderPrefix = "vine@"
    static let classicsURL = URL(string: "https://divine.video/discovery/classics")!
    /// How many unwatched Vines to keep (`AppSettings.vineBatchSize`).
    static let batchSizes = [5, 10, 15, 25, 50, 100]
    /// Categories whose Automix also mixes in Vines.
    static let categoryNames: Set<String> = ["funny", "comedy", "humor", "humour"]

    /// The green of the classic Vine logo.
    static let green = Color(red: 0x00 / 255, green: 0xB4 / 255, blue: 0x88 / 255)

    static func feedFolder(_ settings: AppSettings) -> URL {
        Library.folder(for: feedID, settings: settings)
    }

    /// Every Vine author with a folder in the library, made up as a creator.
    static func scan(settings: AppSettings) -> [CreatorLibrary] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: settings.libraryURL, includingPropertiesForKeys: nil)) ?? []
        return folders.map(\.lastPathComponent)
            .filter { $0.hasPrefix(folderPrefix) && $0 != feedID }
            .map { Library.scan(Creator(username: String($0.dropFirst(folderPrefix.count)), days: 1, platform: .vine),
                                settings: settings) }
            .filter { !$0.videos.isEmpty }
    }

    /// Every author's Vines as one "creator", so Automix plays them about as often as any one real creator.
    /// Shuffled, since they're all years old and newest-first means nothing here.
    static func mixLibrary(_ libraries: [CreatorLibrary]) -> CreatorLibrary {
        CreatorLibrary(creator: Creator(username: "classics", days: 1, platform: .vine), nickname: "Vine", avatar: nil,
                       videos: libraries.flatMap(\.videos).shuffled())
    }

    // MARK: Download

    private static let api = "https://api.divine.video/api/v2/videos"
    private static let pageSize = 50
    private static let maxConcurrent = 4
    private static let safeKey = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,64}$")

    /// One video from the feed, with what Curated needs.
    private struct Item {
        let vineID: String
        let author: String
        let authorName: String?
        let authorAvatar: URL?
        let pubkey: String?
        let timestamp: Int
        let caption: String
        let duration: Int?
        let loops: Int?
        let videoURL: URL
        let sha256: String?
        let thumbnailURL: URL?
    }

    /// Every Vine author's folder in the library.
    private static func authorFolders(_ settings: AppSettings) -> [URL] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: settings.libraryURL, includingPropertiesForKeys: nil)) ?? []
        return folders.filter { $0.lastPathComponent.hasPrefix(folderPrefix) && $0.lastPathComponent != feedID }
    }

    /// Unwatched Vines on disk, leaving out bookmarks (which stay out of the mixes).
    static func unwatchedCount(settings: AppSettings) -> Int {
        let played = Set(PlayedStore.load().filter(\.value.played).keys)
        let bookmarked = BookmarkStore.bookmarkedIDs()
        return authorFolders(settings).reduce(0) { total, folder in
            total + Library.videoFiles(in: folder).count { !played.contains($0.id) && !bookmarked.contains($0.id) }
        }
    }

    /// Each downloaded Vine's place in the download history (the order they came from the feed).
    static func downloadOrder(settings: AppSettings) -> [String: Int] {
        let lines = ((try? String(contentsOf: feedFolder(settings).appendingPathComponent("archive.txt"), encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        return Dictionary(lines.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Takes trimmed Vines out of the download history (the feed's archive and their authors' videos.jsonl), and
    /// starts the next download back at the top of the feed, where they're the first ones not downloaded.
    static func forget(_ videos: [Video], settings: AppSettings) {
        guard !videos.isEmpty else { return }
        let feed = feedFolder(settings)
        Library.forget(Set(videos.map(\.id)), in: feed)
        for (creator, ids) in Dictionary(grouping: videos, by: \.creator) {
            Library.forget(Set(ids.map(\.id)), in: Library.folder(for: creator, settings: settings))
        }
        try? "".write(to: feed.appendingPathComponent("cursor.txt"), atomically: true, encoding: .utf8)
    }

    /// Tops the Vines back up to `keep` unwatched with the next ones nobody has downloaded yet.
    static func download(keep: Int, settings: AppSettings, runner: ProcessRunner,
                         log: @escaping (String) -> Void) async -> DownloadResult {
        let unwatched = unwatchedCount(settings: settings)
        let batchSize = keep - unwatched
        guard batchSize > 0 else {
            log("Vine: \(unwatched) unwatched, keeping \(keep). Nothing to download")
            return DownloadResult()
        }
        let fm = FileManager.default
        let feedFolder = feedFolder(settings)
        do {
            try fm.createDirectory(at: feedFolder, withIntermediateDirectories: true)
        } catch {
            return DownloadResult(error: "Can't create \(feedFolder.path): \(error.localizedDescription)")
        }
        let archiveFile = feedFolder.appendingPathComponent("archive.txt")
        let cursorFile = feedFolder.appendingPathComponent("cursor.txt")
        let archived = Set(((try? String(contentsOf: archiveFile, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        var cursor = (try? String(contentsOf: cursorFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cursor?.isEmpty == true { cursor = nil }

        log("Vine: \(unwatched) of \(keep) unwatched, looking for \(batchSize) more classics…")
        // Phase 1: walk the feed from where the last download stopped, collecting videos not downloaded yet.
        var picked: [Item] = []
        var seen: Set<String> = []
        var nextStart = cursor
        var wrapped = cursor == nil
        var error: String?
        while picked.count < batchSize, !runner.isCancelled {
            guard let (items, next) = await fetchPage(cursor) else {
                error = "Couldn't reach divine.video"
                break
            }
            var stoppedEarly = false
            for item in items where !archived.contains(item.vineID) && seen.insert(item.vineID).inserted {
                picked.append(item)
                if picked.count == batchSize {
                    stoppedEarly = item.vineID != items.last?.vineID
                    break
                }
            }
            // Start next time at this page if some of it is left, or else at the next one.
            nextStart = stoppedEarly ? cursor : next
            if let next {
                cursor = next
            } else if !wrapped {
                // The end of the feed: go round again from the top, where anything skipped before is still waiting.
                wrapped = true
                cursor = nil
                nextStart = nil
            } else {
                break
            }
        }
        try? (nextStart ?? "").write(to: cursorFile, atomically: true, encoding: .utf8)
        if runner.isCancelled { return DownloadResult(error: "Cancelled") }
        if picked.isEmpty { return DownloadResult(error: error) }
        log("Vine: \(picked.count) new")

        // Phase 2: download them, a few at a time, recording each one as it lands.
        var result = DownloadResult()
        var failures: [String] = []
        var pending = picked[...]
        await withTaskGroup(of: (Item, String?).self) { group in
            func startNext() {
                guard !runner.isCancelled, let item = pending.popFirst() else { return }
                group.addTask { (item, await save(item, settings: settings)) }
            }
            for _ in 0..<maxConcurrent { startNext() }
            // The files they share are written here, one video at a time.
            while let (item, failure) = await group.next() {
                if let failure {
                    failures.append(failure)
                } else {
                    result.newVideos += 1
                    appendLine(item.vineID, to: archiveFile)
                    appendLine(metadata(item), to: authorFolder(item, settings).appendingPathComponent("videos.jsonl"))
                    log("Vine: \(item.authorName ?? "unknown"): \(item.caption.isEmpty ? item.vineID : String(item.caption.prefix(60)))")
                }
                startNext()
            }
        }
        if settings.evenOutVolume {
            for folder in Set(picked.map { authorFolder($0, settings) }) where !runner.isCancelled {
                await Loudness.normalize(folder: folder, runner: runner, log: log, label: "Vine")
            }
        }
        if runner.isCancelled {
            result.error = "Cancelled"
        } else if let failure = failures.last {
            result.error = failures.count == 1 ? failure : "\(failures.count) failed: \(failure)"
        }
        log("Vine: done — \(result.newVideos) new" + (result.error.map { " (\($0))" } ?? ""))
        return result
    }

    /// One page of the classics feed, and the cursor for the next one (nil at the end). Nil if it can't be read.
    private static func fetchPage(_ cursor: String?) async -> ([Item], String?)? {
        var components = URLComponents(string: api)!
        components.queryItems = [URLQueryItem(name: "classic", value: "true"), URLQueryItem(name: "platform", value: "vine"),
                                 URLQueryItem(name: "sort", value: "loops"), URLQueryItem(name: "limit", value: "\(pageSize)")]
            + (cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? [])
        guard let data = await get(components.url!),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let pagination = body["pagination"] as? [String: Any]
        let next = pagination?["has_more"] as? Bool == true ? pagination?["next_cursor"] as? String : nil
        let videos = body["data"] as? [[String: Any]] ?? []
        return (videos.compactMap(item), next)
    }

    /// Reads one API record. Leaves out anything without a video, or with a content warning.
    private static func item(_ video: [String: Any]) -> Item? {
        var tags: [String: String] = [:]
        var imeta: [String: String] = [:]
        for tag in video["tags"] as? [[String]] ?? [] {
            guard let name = tag.first else { continue }
            if name == "imeta" {
                for entry in tag.dropFirst() {
                    let parts = entry.split(separator: " ", maxSplits: 1)
                    if parts.count == 2 { imeta[String(parts[0])] = String(parts[1]) }
                }
            } else if tag.count > 1, tags[name] == nil {
                tags[name] = tag[1]
            }
        }
        func string(_ key: String) -> String? { (video[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func int(_ value: Any?) -> Int? { (value as? Int) ?? (value as? String).flatMap { Int($0) } }
        func safe(_ key: String?) -> String? {
            guard let key, safeKey.firstMatch(in: key, range: NSRange(key.startIndex..., in: key)) != nil else { return nil }
            return key
        }

        guard (video["content_labels"] as? [Any] ?? []).isEmpty,
              let videoURL = (string("video_url") ?? imeta["url"]).flatMap(URL.init(string:)),
              let id = string("id") else { return nil }
        let vineID = safe(tags["vine_id"]) ?? safe(string("d_tag")) ?? String(id.prefix(16))
        let pubkey = string("pubkey")
        let author = safe(tags["vine_user_id"]) ?? safe(tags["author_id"]) ?? pubkey.map { String($0.prefix(16)) } ?? "unknown"
        guard let timestamp = int(video["published_at"]) ?? int(tags["published_at"]) ?? int(video["created_at"]) else { return nil }
        return Item(vineID: vineID, author: author, authorName: string("author_name") ?? tags["author"],
                    authorAvatar: string("author_avatar").flatMap(URL.init(string:)), pubkey: pubkey,
                    timestamp: timestamp, caption: caption(tags["summary"] ?? string("title")),
                    duration: int(imeta["duration"]) ?? int(video["duration"]).flatMap { $0 > 0 ? $0 : nil },
                    loops: int(tags["loops"]), videoURL: videoURL,
                    sha256: string("sha256") ?? imeta["x"],
                    thumbnailURL: (string("thumbnail") ?? imeta["image"]).flatMap(URL.init(string:)))
    }

    /// The Vine's caption, without the archive's placeholders ("Vine video", or Vine's own "Watch …'s Vine taken on
    /// …" blurb), or the nostr IDs that stand in for the people it mentions ("w/nostr:npub1…", "wnostr:npub1…") and
    /// the "w/", colons and commas they leave behind.
    private static func caption(_ text: String?) -> String {
        guard let text, text != "Vine video", !(text.hasPrefix("Watch ") && text.contains("'s Vine taken on")) else {
            return ""
        }
        return [(#"(nostr:)?npub1[0-9a-z]{20,}"#, ""),        // the IDs
                (#"(?<![^\s(])[wW][/:]*(?=[\s,:]*(#|$|\)))"#, ""),  // a "w/" with nobody left after it
                (#"(?<=\b[wW])[:/]*,\s*"#, "/ "),            // "w:, Bob" → "w/ Bob"
                (#"\s[:,]+(?=\s)"#, ""),                    // stray " , " and " : "
                (#"\s*,(\s*,)+"#, ","),                     // "a, , b" → "a, b"
                (#"(?<=[wW]/)\s*,\s*"#, " "),                // "w/ , Bob" → "w/ Bob"
                (#"\(\s*\)"#, ""),
                (#"[\s,]+$"#, ""),
                (#"\s{2,}"#, " ")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1, options: .regularExpression) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func authorFolder(_ item: Item, _ settings: AppSettings) -> URL {
        Library.folder(for: Creator(username: item.author, days: 1, platform: .vine).id, settings: settings)
    }

    /// The video's line in its author's videos.jsonl: the fields yt-dlp writes for other creators, with the loop
    /// count standing in for views.
    private static func metadata(_ item: Item) -> String {
        var meta: [String: Any] = ["id": item.vineID, "description": item.caption, "timestamp": item.timestamp]
        if let duration = item.duration { meta["duration"] = duration }
        if let loops = item.loops { meta["view_count"] = loops }
        let line = (try? JSONSerialization.data(withJSONObject: meta, options: .sortedKeys)) ?? Data()
        return String(decoding: line, as: UTF8.self)
    }

    /// Downloads one Vine into its author's folder (checking its hash), with its thumbnail, and the author's name and
    /// avatar the first time. Returns an error message, or nil once it's in place.
    private static func save(_ item: Item, settings: AppSettings) async -> String? {
        let fm = FileManager.default
        let folder = authorFolder(item, settings)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = "\(item.timestamp)_\(item.vineID)"
        let file = folder.appendingPathComponent("\(base).mp4")

        guard let data = await get(item.videoURL, timeout: 60) else { return "Couldn't download Vine \(item.vineID)" }
        if let expected = item.sha256?.lowercased(),
           SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() != expected {
            return "Vine \(item.vineID) didn't match its checksum"
        }
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            return "Can't save \(file.lastPathComponent): \(error.localizedDescription)"
        }
        if let thumbnailURL = item.thumbnailURL, let poster = await get(thumbnailURL) {
            try? poster.write(to: folder.appendingPathComponent("\(base).jpg"), options: .atomic)
        }

        if !fm.fileExists(atPath: folder.appendingPathComponent("profile.json").path) {
            await saveProfile(item, in: folder)
        }
        return nil
    }

    /// The author's name and avatar: from the video's record, or else their divine.video profile.
    private static func saveProfile(_ item: Item, in folder: URL) async {
        var name = item.authorName
        var avatar = item.authorAvatar
        if avatar == nil || name == nil, let pubkey = item.pubkey,
           let data = await get(URL(string: "https://api.divine.video/api/users/\(pubkey)")!),
           let profile = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["profile"] as? [String: Any] {
            name = name ?? (profile["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            avatar = avatar ?? (profile["picture"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        }
        if let avatar, let image = await get(avatar) {
            try? image.write(to: folder.appendingPathComponent("avatar.jpg"), options: .atomic)
        }
        Library.saveProfile(nickname: name, in: folder)
    }

    private static func get(_ url: URL, timeout: TimeInterval = 30) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("Curated (personal; +https://divine.video)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let status = (response as? HTTPURLResponse)?.statusCode {
                if status == 200 { return data }
                guard status == 429 || status >= 500 else { return nil }
            }
            try? await Task.sleep(for: .seconds(1 << attempt))
        }
        return nil
    }

    private static func appendLine(_ line: String, to file: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// The V from the Vine logo on its own, in the current foreground style, like an SF Symbol (the sidebar's Vine card).
/// Falls back to a letter if the artwork is missing.
struct VineGlyph: View {
    var height: CGFloat = 13

    private static let image: NSImage? = {
        let image = Bundle.main.url(forResource: "vine-glyph", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        return image
    }()

    var body: some View {
        Group {
            if let image = Self.image, image.size.height > 0 {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: height * image.size.width / image.size.height, height: height)
            } else {
                Text("V").font(.system(size: height, weight: .heavy, design: .rounded))
            }
        }
        .accessibilityLabel("Vine")
    }
}

/// The classic Vine app icon: a white V on a green rounded square. Drawn in SwiftUI if the artwork is missing (e.g. a
/// debug build run outside the app bundle).
struct VineLogo: View {
    var size: CGFloat = 18

    private static let image = Bundle.main.url(forResource: "vine", withExtension: "svg").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Vine.green)
                    .overlay {
                        Text("V").font(.system(size: size * 0.7, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Vine")
    }
}
