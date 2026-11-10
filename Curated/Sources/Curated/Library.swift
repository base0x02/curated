import AVFoundation
import Foundation

enum Library {
    static let videoExtensions: Set<String> = ["mp4", "m4v", "mov"]

    /// Each creator's folder is named by their `Creator.id`. It holds their short videos, avatar and profile.
    static func folder(for creatorID: String, settings: AppSettings) -> URL {
        settings.libraryURL.appendingPathComponent(creatorID, isDirectory: true)
    }

    /// Where a creator's videos of `form` go. Long videos get their own folder (`youtube-long@<handle>`), so the
    /// age-based cleanup and phone sync, which only look at `folder(for:)`, never touch them.
    static func folder(for creator: Creator, form: VideoForm, settings: AppSettings) -> URL {
        form == .short || creator.playlist ? folder(for: creator.id, settings: settings)
            : settings.libraryURL.appendingPathComponent(creator.longFormFolderName, isDirectory: true)
    }

    private struct Meta: Decodable {
        let id: String
        let title: String?
        let description: String?
        let duration: Double?
        let view_count: Double?
    }

    private struct Profile: Codable {
        var nickname: String?
    }

    /// The avatar and display name always come from the creator's main folder, whichever form is scanned.
    static func scan(_ creator: Creator, form: VideoForm = .short, settings: AppSettings) -> CreatorLibrary {
        let profileFolder = folder(for: creator.id, settings: settings)
        let folder = folder(for: creator, form: form, settings: settings)
        let fm = FileManager.default

        var meta: [String: Meta] = [:]
        if let text = try? String(contentsOf: folder.appendingPathComponent("videos.jsonl"), encoding: .utf8) {
            for line in text.split(separator: "\n") {
                if let m = try? JSONDecoder().decode(Meta.self, from: Data(line.utf8)) { meta[m.id] = m }
            }
        }

        let views = viewCounts(in: folder)
        // A playlist's folder holds long videos only.
        let files = creator.playlist && form == .short ? []
            : (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let videos: [Video] = files.compactMap { url in
            guard videoExtensions.contains(url.pathExtension.lowercased()),
                  let (timestamp, id) = parseFilename(url) else { return nil }
            let m = meta[id]
            let caption = [m?.description, m?.title].compactMap { $0 }.first { !$0.isEmpty } ?? ""
            return Video(id: id, creator: creator.id, url: url,
                         date: Date(timeIntervalSince1970: timestamp), caption: caption,
                         duration: m?.duration.map { Int($0) },
                         viewCount: views[id] ?? m?.view_count.map { Int($0) }, form: form,
                         title: m?.title ?? "", details: m?.description ?? "",
                         size: fileSize(url) ?? 0)
        }
        .sorted { $0.date > $1.date }
        let ordered = creator.playlist ? playlistOrder(videos, in: folder) : videos

        let avatar = profileFolder.appendingPathComponent("avatar.jpg")
        let profile = (try? Data(contentsOf: profileFolder.appendingPathComponent("profile.json")))
            .flatMap { try? JSONDecoder().decode(Profile.self, from: $0) }

        return CreatorLibrary(creator: creator,
                              nickname: profile?.nickname.flatMap { $0.isEmpty ? nil : $0 },
                              avatar: fm.fileExists(atPath: avatar.path) ? avatar : nil,
                              videos: ordered, form: form)
    }

    /// A playlist's videos in the playlist's order (order.json, saved by each download), newest first after those.
    private static func playlistOrder(_ videos: [Video], in folder: URL) -> [Video] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("order.json")),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return videos }
        let position = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return videos.enumerated()
            .sorted { (position[$0.element.id] ?? Int.max, $0.offset) < (position[$1.element.id] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    static func savePlaylistOrder(_ ids: [String], in folder: URL) {
        try? JSONEncoder().encode(ids).write(to: folder.appendingPathComponent("order.json"), options: .atomic)
    }

    /// Files are saved as "<unix timestamp>_<video id>.<ext>".
    static func parseFilename(_ url: URL) -> (TimeInterval, String)? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_", maxSplits: 1)
        guard parts.count == 2, let ts = TimeInterval(parts[0]) else { return nil }
        return (ts, String(parts[1]))
    }

    /// A file's size in bytes, or nil if it can't be read.
    static func fileSize(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
    }

    /// Latest view counts, refreshed from the profile listing on every download run.
    static func viewCounts(in folder: URL) -> [String: Int] {
        (try? Data(contentsOf: folder.appendingPathComponent("views.json")))
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
    }

    static func mergeViewCounts(_ counts: [String: Int], in folder: URL) {
        guard !counts.isEmpty else { return }
        let merged = viewCounts(in: folder).merging(counts) { _, new in new }
        try? JSONEncoder().encode(merged).write(to: folder.appendingPathComponent("views.json"), options: .atomic)
    }

    static func saveProfile(nickname: String?, in folder: URL) {
        try? JSONEncoder().encode(Profile(nickname: nickname))
            .write(to: folder.appendingPathComponent("profile.json"), options: .atomic)
    }

    /// Unplayed videos only. Round-robin across creators (random order, random starting creator), each creator newest first.
    static func automixQueue(_ libraries: [CreatorLibrary], excluding played: Set<String>) -> [Video] {
        let lists = libraries.map { $0.videos.filter { !played.contains($0.id) } }.filter { !$0.isEmpty }.shuffled()
        var queue: [Video] = []
        let longest = lists.map(\.count).max() ?? 0
        for round in 0..<longest {
            for list in lists where round < list.count {
                queue.append(list[round])
            }
        }
        return queue
    }

    /// Every unplayed video, newest first: for long videos, where a round-robin mix doesn't suit.
    static func latestQueue(_ libraries: [CreatorLibrary], excluding played: Set<String>) -> [Video] {
        libraries.flatMap(\.videos).filter { !played.contains($0.id) }.sorted { $0.date > $1.date }
    }

    /// Video files in `folder` posted before `cutoff` (a Unix timestamp), except the ones in `keeping` (bookmarks).
    static func videos(in folder: URL, olderThan cutoff: TimeInterval, keeping: Set<String> = []) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { url in
            guard videoExtensions.contains(url.pathExtension.lowercased()),
                  let (ts, id) = parseFilename(url) else { return false }
            return ts < cutoff && !keeping.contains(id)
        }
    }

    @discardableResult
    static func deleteVideos(in folder: URL, olderThan cutoff: TimeInterval, keeping: Set<String> = []) -> Int {
        videos(in: folder, olderThan: cutoff, keeping: keeping)
            .filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
    }

    /// The post time and id of each video file in `folder`.
    static func videoFiles(in folder: URL) -> [(date: TimeInterval, id: String)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url in
            guard videoExtensions.contains(url.pathExtension.lowercased()), let (ts, id) = parseFilename(url) else { return nil }
            return (ts, id)
        }
    }

    /// The post time of the newest video ever downloaded into `folder`, including ones deleted since (videos.jsonl
    /// keeps a line for each).
    static func newestDownloadDate(in folder: URL) -> TimeInterval? {
        struct Entry: Decodable { let timestamp: TimeInterval? }
        let text = (try? String(contentsOf: folder.appendingPathComponent("videos.jsonl"), encoding: .utf8)) ?? ""
        let logged = text.split(separator: "\n").compactMap {
            (try? JSONDecoder().decode(Entry.self, from: Data($0.utf8)))?.timestamp
        }
        return (logged + videoFiles(in: folder).map(\.date)).max()
    }

    /// Takes videos out of a folder's download history (archive.txt and videos.jsonl), so a later download can fetch
    /// them again and the newest-download date no longer counts them.
    static func forget(_ ids: Set<String>, in folder: URL) {
        guard !ids.isEmpty else { return }
        struct Entry: Decodable { let id: String }
        let archive = folder.appendingPathComponent("archive.txt")
        if let text = try? String(contentsOf: archive, encoding: .utf8) {
            let kept = text.split(separator: "\n").filter { line in
                !(line.split(separator: " ").last.map { ids.contains(String($0)) } ?? false)
            }
            try? (kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")).write(to: archive, atomically: true, encoding: .utf8)
        }
        let jsonl = folder.appendingPathComponent("videos.jsonl")
        if let text = try? String(contentsOf: jsonl, encoding: .utf8) {
            let kept = text.split(separator: "\n").filter { line in
                !((try? JSONDecoder().decode(Entry.self, from: Data(line.utf8))).map { ids.contains($0.id) } ?? false)
            }
            try? (kept.joined(separator: "\n") + (kept.isEmpty ? "" : "\n")).write(to: jsonl, atomically: true, encoding: .utf8)
        }
    }

    /// Adds YouTube videos to a folder's download history (archive.txt) without downloading them, so no download
    /// ever fetches them (skipped in the long-video picker).
    static func archive(_ ids: [String], in folder: URL) {
        guard !ids.isEmpty else { return }
        let archive = folder.appendingPathComponent("archive.txt")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var text = (try? String(contentsOf: archive, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += ids.map { "youtube \($0)\n" }.joined()
        try? text.write(to: archive, atomically: true, encoding: .utf8)
    }

    static func cutoff(for creator: Creator) -> TimeInterval {
        Date().addingTimeInterval(-Double(creator.days) * 86_400).timeIntervalSince1970
    }

    /// Keeps videos until their total length reaches `seconds`; the video that crosses the limit is the last one.
    static func limitToDuration(_ queue: [Video], seconds: TimeInterval) async -> [Video] {
        var total: TimeInterval = 0
        var result: [Video] = []
        for video in queue {
            result.append(video)
            total += await duration(of: video)
            if total >= seconds { break }
        }
        return result
    }

    /// From yt-dlp's metadata, or read from the file for videos downloaded without it.
    static func duration(of video: Video) async -> TimeInterval {
        if let d = video.duration { return TimeInterval(d) }
        let seconds = (try? await AVURLAsset(url: video.url).load(.duration))?.seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    /// The most-viewed unplayed videos, capped at `count`. If view counts are missing for some videos,
    /// the rest of the list is filled Automix-style (a random creator's newest unplayed video, round by round).
    static func topQueue(_ libraries: [CreatorLibrary], excluding played: Set<String>, count topCount: Int) -> [Video] {
        let unplayed = libraries.flatMap(\.videos).filter { !played.contains($0.id) }
        var picked = Array(unplayed.filter { $0.viewCount != nil }
            .sorted { $0.viewCount! > $1.viewCount! }
            .prefix(topCount))
        if picked.count < topCount {
            let exclude = played.union(picked.map(\.id))
            picked += automixQueue(libraries, excluding: exclude).prefix(topCount - picked.count)
        }
        return picked
    }
}
