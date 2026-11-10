import Foundation

struct Category: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String?
}

/// Short videos (TikTok, YouTube Shorts) or long ones (regular YouTube videos and playlists), as on the Mac.
enum VideoForm: String, Codable, Hashable {
    case short, long
}

/// Which videos a sync downloads, the one saved in Settings. Short is what
/// it always synced.
enum SyncForms: String, CaseIterable, Identifiable {
    case short, long, all
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// The manifest's `forms` parameter.
    var query: String { self == .all ? "short,long" : rawValue }
    var includesLong: Bool { self != .short }
    func includes(_ video: Video) -> Bool { self == .all || (video.isLong ? self == .long : self == .short) }

    /// What the Sync menu says.
    var menuTitle: String { "\(label) Videos" }
}

struct Creator: Codable, Identifiable, Hashable {
    let username: String
    let nickname: String?
    let days: Int
    let category: String?
    let hasAvatar: Bool
    /// A YouTube playlist ("youtube-playlist@<ID>"): long videos only, in `order`. Nil from Macs before long videos.
    var playlist: Bool?
    /// A playlist's video IDs in playlist order.
    var order: [String]?
    /// A Vine author ("vine@<Vine user ID>"): short videos only, no category. Nil from Macs before Vines.
    var vine: Bool?
    /// A channel with long videos on, whose older videos can be asked for. Nil from Macs before API 10.
    var isPlaylist: Bool { playlist == true }
    var isVine: Bool { vine == true || username.hasPrefix(vineKeyPrefix) }
    var id: String { username }
    var isYouTube: Bool { isYouTubeKey(username) }
    /// The @handle without the Mac's "youtube@" key prefix.
    var handle: String { creatorHandle(username) }
    var displayName: String { nickname.flatMap { $0.isEmpty ? nil : $0 } ?? "@\(handle)" }
    /// Where it's from, for "Open in YouTube".
    var siteName: String { isYouTube ? "YouTube" : "TikTok" }
    /// Its page on YouTube or TikTok. Vine authors and the Mac's Suggestions playlist have none.
    var pageURL: URL? {
        if isVine { return nil }
        if isPlaylist {
            let id = username.replacingOccurrences(of: "youtube-playlist@", with: "")
            return id == "suggestions" ? nil : URL(string: "https://www.youtube.com/playlist?list=\(id)")
        }
        if !isYouTube { return URL(string: "https://www.tiktok.com/@\(username)") }
        return URL(string: handle.hasPrefix("UC") ? "https://www.youtube.com/channel/\(handle)" : "https://www.youtube.com/@\(handle)")
    }
}

/// The Mac keys YouTube creators as "youtube@<handle>" (TikTok usernames can't contain "@") and TikTok ones by username.
let youTubeKeyPrefix = "youtube@"
/// The Mac keys Vine authors as "vine@<Vine user ID>".
let vineKeyPrefix = "vine@"

/// Home's "Other Creators" and Vine cards, alongside the category ids, in a mix's `picked` cards.
let otherCard = "other"
let vineCard = "vine"
/// Long videos' Playlists card, which is never in a mix, in the playback rules.
let playlistCard = "playlists"
/// YouTube channels, and YouTube playlists ("youtube-playlist@<ID>").
func isYouTubeKey(_ creatorKey: String) -> Bool { creatorKey.hasPrefix(youTubeKeyPrefix) || creatorKey.hasPrefix("youtube-playlist@") }
func creatorHandle(_ creatorKey: String) -> String {
    creatorKey.hasPrefix(youTubeKeyPrefix) ? String(creatorKey.dropFirst(youTubeKeyPrefix.count)) : creatorKey
}

struct Video: Codable, Identifiable, Hashable {
    let id: String
    let creator: String
    let date: Date
    let caption: String
    let duration: Double?
    let viewCount: Int?
    let size: Int
    let fileExtension: String
    /// Long videos only (nil means short): "long", the title and description, and whether the Mac has a poster.
    var form: VideoForm?
    var title: String?
    var details: String?
    var hasPoster: Bool?
    /// Long videos picked by hand on the Mac from a creator's older videos: when. They come first until watched.
    var pickedAt: Date?

    var isLong: Bool { form == .long }
    /// For long videos: the title, or the caption if there's no title.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return caption.isEmpty ? "Untitled" : caption
    }
}

/// A creator's videos of one form that are fully downloaded on this phone: newest first, or a playlist's own order.
/// A YouTube creator with both forms has a short and a long library.
struct CreatorLibrary: Identifiable, Hashable {
    let creator: Creator
    let videos: [Video]
    var form = VideoForm.short
    var id: String { creator.username }
}

/// What the Mac sends from GET /manifest.
struct Manifest: Codable {
    let macName: String
    let timeLimitMinutes: Int
    let categories: [Category]
    let creators: [Creator]
    let videos: [Video]
    /// The categories whose Automix also plays the Vines (a Funny category, on the Mac). Nil from Macs before Vines.
    var vineCategories: [String]?
    /// When the Mac last finished a download. Nil from Macs before API 6, and until its first download.
    var lastDownloadAt: Date?

    static func decode(_ data: Data) throws -> Manifest {
        try JSONDecoder.curated.decode(Manifest.self, from: data)
    }
}

/// Whether a video has been watched, and when that last changed. Shared with the Mac, which keeps
/// the newest change for each video.
struct PlayedMark: Codable, Equatable {
    var played: Bool
    var at: Date

    /// The Mac reads whole-second ISO 8601 dates only.
    static func now(_ played: Bool) -> PlayedMark {
        PlayedMark(played: played, at: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
    }
}

/// Whether a video is saved to Watch Later (or bookmarked), and when that last changed. Merged with the Mac like
/// PlayedMark.
struct WatchLaterMark: Codable, Equatable {
    var saved: Bool
    var at: Date

    static func now(_ saved: Bool) -> WatchLaterMark {
        WatchLaterMark(saved: saved, at: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
    }
}

/// How far into a long video playback got, and when that last changed, merged with the Mac: the newest change wins.
/// No `seconds` means it was cleared (the video was finished), which syncs too.
struct PositionMark: Codable, Equatable {
    var seconds: Double?
    var at: Date

    static func now(_ seconds: Double?) -> PositionMark {
        PositionMark(seconds: seconds, at: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
    }

    /// Newest wins. Within the same second, a cleared one and then the furthest, so every device settles on the same mark.
    func supersedes(_ other: PositionMark?) -> Bool {
        guard let other else { return true }
        if at != other.at { return at > other.at }
        return (seconds ?? .infinity) > (other.seconds ?? .infinity)
    }
}

/// The long video last playing on any device, so the others can have it ready. No `id` means it was closed or finished.
struct NowPlayingMark: Codable, Equatable {
    var id: String?
    var at: Date

    static let none = NowPlayingMark(id: nil, at: Date(timeIntervalSince1970: 0))

    static func now(_ id: String?) -> NowPlayingMark {
        NowPlayingMark(id: id, at: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
    }

    /// Newest wins. Within the same second, the larger id, so every device settles on the same mark.
    func supersedes(_ other: NowPlayingMark) -> Bool {
        at != other.at ? at > other.at : (id ?? "") > (other.id ?? "")
    }
}

/// What each category does in playback, shared with the Mac and other phones: the newest change on any device wins,
/// swapped through `/positions` (API 8). Categories are named by the keys of a mix's `picked` cards: a category's id,
/// `otherCard`, `vineCard`, or (long videos, 1× only) `playlistCard`.
struct PlaybackRules: Codable, Equatable {
    struct Cards: Codable, Equatable {
        /// Left out of Automix unless picked by long-pressing it. A category's own Automix still plays it.
        var automixOff: Set<String> = []
        /// Always plays at 1×, whatever speed is chosen; the chosen speed comes back on the next video.
        var normalSpeed: Set<String> = []

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            automixOff = try c.decodeIfPresent(Set<String>.self, forKey: .automixOff) ?? []
            normalSpeed = try c.decodeIfPresent(Set<String>.self, forKey: .normalSpeed) ?? []
        }
    }

    /// When these last changed. 1970 until they're first changed, so the Mac's are taken until then.
    var at = Date(timeIntervalSince1970: 0)
    var short = Cards()
    var long = Cards()
    /// Long videos go back this far when they resume, to pick the thread up again.
    var resumeRewindSeconds = 0
    /// Nil until changed here or heard from the Mac; the manifest's until then.
    var timeLimitMinutes: Int?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decodeIfPresent(Date.self, forKey: .at) ?? at
        short = try c.decodeIfPresent(Cards.self, forKey: .short) ?? short
        long = try c.decodeIfPresent(Cards.self, forKey: .long) ?? long
        resumeRewindSeconds = try c.decodeIfPresent(Int.self, forKey: .resumeRewindSeconds) ?? resumeRewindSeconds
        timeLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .timeLimitMinutes)
    }

    func cards(_ form: VideoForm) -> Cards { form == .long ? long : short }

    static let rewindChoices = [0, 5, 10, 30]
    static let timeLimitChoices = [5, 10, 15, 20, 30, 45, 60]
}

/// Where the paired Mac was last reached, and this phone's token for it.
struct Pairing: Codable, Equatable {
    var host: String
    var port: Int
    var token: String
    var macName: String

    /// The computer's own name: the Mac calls itself "Curated on <name>".
    var computerName: String {
        macName.hasPrefix("Curated on ") ? String(macName.dropFirst("Curated on ".count)) : macName
    }
}

/// One event of the Mac's `/download/progress`.
struct MacDownloadProgress: Decodable, Equatable {
    let downloading: Bool
    var progress: Double?
    var done: Int?
    var total: Int?
    var current: [String]?
    var lastDownloadAt: Date?
}

enum PlaybackMode: Hashable {
    case creator(String)
    /// A nil category means all creators. `picked`, from long-pressing Home's Automix or Top 15, limits it to some of
    /// Home's cards instead: category ids, `otherCard` and `vineCard`.
    case automix(String?, picked: Set<String>? = nil)
    case top(String?, picked: Set<String>? = nil)
    case watchLater
    /// Kept out of Automix and never deleted automatically; plays straight through, watched or not.
    case bookmarks
    // Long videos have their own queues, as on the Mac: a creator's or playlist's videos, Latest (every unwatched one,
    // newest first), Automix, and their own Watch Later and Bookmarks. No Top list.
    case longCreator(String)
    case latest(String?)
    case longAutomix(String?, picked: Set<String>? = nil)
    case longWatchLater
    case longBookmarks
    /// Every Vine, round-robin across their authors.
    case vineAutomix

    var form: VideoForm {
        switch self {
        case .creator, .automix, .top, .watchLater, .bookmarks, .vineAutomix: .short
        case .longCreator, .latest, .longAutomix, .longWatchLater, .longBookmarks: .long
        }
    }

    /// A creator's (or playlist's) videos, either form.
    var creatorUsername: String? {
        switch self {
        case .creator(let u), .longCreator(let u): u
        default: nil
        }
    }

    var isBookmarks: Bool { self == .bookmarks || self == .longBookmarks }

    /// Automix of either form. (`isAutomix` is short videos' only, which has Time Limit.)
    var isAnyAutomix: Bool {
        switch self {
        case .automix, .longAutomix, .vineAutomix: true
        default: false
        }
    }

    /// A generated mix that runs on until it's out of unwatched videos.
    var isOpenMix: Bool {
        switch self {
        case .automix, .longAutomix, .vineAutomix, .latest: true
        default: false
        }
    }

    static let topCountAll = 15
    static let topCountCategory = 5
    static func topCount(_ category: String?) -> Int { category == nil ? topCountAll : topCountCategory }

    /// Short videos' Automix (Vine's too), which has Time Limit.
    var isAutomix: Bool {
        switch self {
        case .automix, .vineAutomix: true
        default: false
        }
    }
    var topLimit: Int? { if case .top(let c, _) = self { PlaybackMode.topCount(c) } else { nil } }
}

extension JSONDecoder {
    static let curated: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let curated: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
