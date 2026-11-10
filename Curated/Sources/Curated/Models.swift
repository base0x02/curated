import AppKit
import Foundation

enum Paths {
    /// Set CURATED_DATA_DIR to run against a separate config/played history (for testing).
    static let dataDirOverride = ProcessInfo.processInfo.environment["CURATED_DATA_DIR"]
    static let appSupport: URL = {
        let url = dataDirOverride.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Curated", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static var config: URL { appSupport.appendingPathComponent("config.json") }
    static var state: URL { appSupport.appendingPathComponent("state.json") }
    static var lock: URL { appSupport.appendingPathComponent("download.lock") }
    static var played: URL { appSupport.appendingPathComponent("played.json") }
    static var sync: URL { appSupport.appendingPathComponent("sync.json") }
    static var watchLater: URL { appSupport.appendingPathComponent("watchlater.json") }
    static var bookmarks: URL { appSupport.appendingPathComponent("bookmarks.json") }
    static var handPicked: URL { appSupport.appendingPathComponent("handpicked.json") }
    static var ipod: URL { appSupport.appendingPathComponent("ipod.json") }
    /// Before positions synced: `{videoID: seconds}`. Only read, to carry them over into `positionMarks`.
    static var positions: URL { appSupport.appendingPathComponent("positions.json") }
    static var positionMarks: URL { appSupport.appendingPathComponent("positionmarks.json") }
    static var nowPlaying: URL { appSupport.appendingPathComponent("nowplaying.json") }
    static var logs: URL {
        let url = appSupport.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static let defaultLibrary = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/Curated", isDirectory: true)
}

/// Short (TikTok, YouTube Shorts) or long (regular YouTube videos). Each has its own sidebar, mixes and library folder.
enum VideoForm: String, Codable, CaseIterable {
    case short, long
}

enum Platform: String, Codable, CaseIterable, Identifiable {
    /// Vine is only ever an author of the Vine classics (see Vine.swift), made up when the library is scanned. It's
    /// never in `Config.creators`, so older builds never meet it in config.json.
    case tiktok, youtube, vine
    var id: String { rawValue }
    var name: String {
        switch self {
        case .tiktok: "TikTok"
        case .youtube: "YouTube"
        case .vine: "Vine"
        }
    }
    /// The platforms a creator can be added from.
    static let addable: [Platform] = [.tiktok, .youtube]
}

struct Creator: Codable, Identifiable, Hashable {
    /// The TikTok username, or the YouTube handle (or "UC…" channel ID) without the @, or a YouTube playlist's ID.
    var username: String
    var days: Int
    var category: UUID? = nil
    var platform = Platform.tiktok
    /// Only videos with at least this many views are downloaded; nil downloads everything in the window. Videos under
    /// it aren't recorded as downloaded, so every run looks at them again and picks up any that have since caught on.
    var minViews: Int? = nil
    /// YouTube only: download the channel's Shorts, its long videos, or both (at least one). TikTok is always short.
    var shorts = true
    var longForm = false
    /// The highest resolution long videos are downloaded at (e.g. 720 for 720p); nil is Best, the highest H.264
    /// YouTube offers (which is 1080p). Builds before 1.7 read nil as 1080, the same thing in practice.
    var longFormHeight: Int? = nil
    /// A YouTube playlist rather than a channel: `username` is its ID ("PL…"). Long videos only, the whole playlist
    /// (no day window), in playlist order, in the Playlists group rather than a category.
    var playlist = false
    /// Playlists only: download just this many of its newest videos (by upload date, whatever the playlist's order);
    /// nil downloads them all.
    var playlistLimit: Int? = nil
    /// Short videos only: instead of everything from the last `days` days, keep this many unwatched videos. Each
    /// download tops the folder back up: new posts first (oldest of them first), then, with `keepHistorical`, older
    /// videos never downloaded (newest of them first). nil uses the day window. Long videos always use the window.
    var keepVideos: Int? = nil
    var keepHistorical = false

    static let playlistLimits = [5, 10, 25, 50, 100]

    static let longFormHeights = [1080, 720, 480, 144]

    /// Whether short videos are kept by count (`keepVideos`) rather than by age.
    var keepsByCount: Bool { keepVideos != nil && downloadsShorts }

    /// Unique across platforms; also the library folder name. TikTok usernames can't contain "@", so YouTube keys
    /// never clash with them, and TikTok keys stay plain usernames as they were before YouTube support.
    /// A playlist's key is "youtube-playlist@<ID>"; its folder holds its videos as well as its title.
    /// A Vine author's is "vine@<their Vine user ID>".
    var id: String {
        switch platform {
        case .tiktok: username
        case .vine: "vine@\(username)"
        case .youtube: playlist ? "youtube-playlist@\(username)" : "youtube@\(username)"
        }
    }

    /// The folder for a YouTube creator's long videos, kept apart from their Shorts (`id`). A playlist has only the one.
    var longFormFolderName: String { playlist ? id : "youtube-long@\(username)" }

    /// The Suggestions playlist: videos picked from the YouTube home feed (SuggestedPicker in LongPicker.swift) whose
    /// channel isn't followed with long videos on. Like Vine's authors it's never in `config.creators`, so older
    /// builds, Total and the overnight download never see it; `AppModel.reloadLibrary` adds it to `longLibraries`
    /// once its folder (`youtube-playlist@suggestions`) exists. Its `order.json` lists the newest picks first.
    static let suggestions = Creator(username: "suggestions", days: 1, platform: .youtube, playlist: true)

    /// Real playlist IDs are "PL…"/"UU…"-style, never this lowercase word.
    var isSuggestions: Bool { platform == .youtube && playlist && username == Creator.suggestions.username }

    var downloadsShorts: Bool { platform == .tiktok || (shorts && !playlist) }
    var downloadsLongForm: Bool { platform == .youtube && longForm }
    /// A channel with long videos on, whose older videos can be listed to pick from. A playlist's are all listed anyway.
    var canPickOlderLong: Bool { downloadsLongForm && !playlist }

    func downloads(_ form: VideoForm) -> Bool { form == .short ? downloadsShorts : downloadsLongForm }

    var profileURL: URL {
        switch platform {
        case .youtube where isSuggestions: URL(string: "https://www.youtube.com/")!
        case .youtube where playlist: URL(string: "https://www.youtube.com/playlist?list=\(username)")!
        case .tiktok: URL(string: "https://www.tiktok.com/@\(username)")!
        case .youtube where username.hasPrefix("UC"): URL(string: "https://www.youtube.com/channel/\(username)")!
        case .youtube: URL(string: "https://www.youtube.com/@\(username)")!
        case .vine: Vine.classicsURL
        }
    }

    init(username: String, days: Int, category: UUID? = nil, platform: Platform = .tiktok,
         shorts: Bool = true, longForm: Bool = false, playlist: Bool = false, playlistLimit: Int? = nil) {
        self.username = username
        self.days = days
        self.category = playlist ? nil : category
        self.platform = platform
        self.shorts = shorts && !playlist
        self.longForm = longForm || playlist
        self.playlist = playlist
        self.playlistLimit = playlist ? playlistLimit : nil
    }

    // Tolerate a missing platform so configs from before YouTube support still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decode(String.self, forKey: .username)
        days = try c.decode(Int.self, forKey: .days)
        category = try c.decodeIfPresent(UUID.self, forKey: .category)
        platform = try c.decodeIfPresent(Platform.self, forKey: .platform) ?? .tiktok
        minViews = try c.decodeIfPresent(Int.self, forKey: .minViews)
        shorts = try c.decodeIfPresent(Bool.self, forKey: .shorts) ?? true
        longForm = try c.decodeIfPresent(Bool.self, forKey: .longForm) ?? false
        longFormHeight = try c.decodeIfPresent(Int.self, forKey: .longFormHeight)
        playlist = try c.decodeIfPresent(Bool.self, forKey: .playlist) ?? false
        playlistLimit = try c.decodeIfPresent(Int.self, forKey: .playlistLimit)
        keepVideos = try c.decodeIfPresent(Int.self, forKey: .keepVideos)
        keepHistorical = try c.decodeIfPresent(Bool.self, forKey: .keepHistorical) ?? false
    }

    /// The ID in a YouTube playlist link ("…list=PL…"), if the input is one.
    static func playlistID(in input: String) -> String? {
        guard input.range(of: #"(youtube\.com|youtu\.be)/"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let range = input.range(of: #"[?&]list=[A-Za-z0-9_-]{10,}"#, options: .regularExpression) else { return nil }
        return String(input[range].drop { $0 != "=" }.dropFirst())
    }

    /// Accepts "name", "@name", or a full profile/video URL. Any YouTube link picks YouTube; otherwise `platform` is used.
    static func parse(_ input: String, platform: Platform) -> (username: String, platform: Platform)? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let isYouTube = platform == .youtube || s.range(of: #"(youtube\.com|youtu\.be)/"#, options: [.regularExpression, .caseInsensitive]) != nil
        if isYouTube {
            if let range = s.range(of: #"UC[A-Za-z0-9_-]{22}"#, options: .regularExpression) {
                return (String(s[range]), .youtube)
            }
            var handle = s
            if let range = s.range(of: #"@[A-Za-z0-9._-]+"#, options: .regularExpression) { handle = String(s[range]) }
            handle = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
            guard handle.range(of: #"^[a-z0-9._-]{3,30}$"#, options: .regularExpression) != nil else { return nil }
            return (handle, .youtube)
        }
        var name = s
        if let range = s.range(of: #"@[A-Za-z0-9._]+"#, options: .regularExpression) { name = String(s[range]) }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
        guard !name.isEmpty, name.range(of: #"^[a-z0-9._]+$"#, options: .regularExpression) != nil else { return nil }
        return (name, .tiktok)
    }
}

/// How a creator's short videos are kept: everything from the last `days` days, or `videos` unwatched ones (with
/// `historical`, older videos never downloaded fill in when there aren't enough new ones).
struct KeepRule: Equatable {
    var days: Int
    var videos: Int?
    var historical = false

    init(days: Int, videos: Int? = nil, historical: Bool = false) {
        self.days = days
        self.videos = videos
        self.historical = historical
    }

    init(_ creator: Creator) {
        self.init(days: creator.days, videos: creator.keepVideos, historical: creator.keepHistorical)
    }

    func apply(to creator: inout Creator) {
        creator.days = max(1, days)
        creator.keepVideos = videos.map { max(1, $0) }
        creator.keepHistorical = historical
    }
}

struct Category: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol = Category.defaultSymbol
    var collapsed = false
    /// Whether it got a shortcut icon beside Automix and Top 15 in the sidebar (before they became tiles). Unused; kept
    /// so the config still reads in older versions.
    var showInWatch = true

    static let defaultSymbol = "folder"

    init(name: String, symbol: String = Category.defaultSymbol) {
        self.name = name
        self.symbol = symbol
    }

    // Tolerate missing keys so configs from older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? Category.defaultSymbol
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        showInWatch = try c.decodeIfPresent(Bool.self, forKey: .showInWatch) ?? true
    }

    /// A curated set of SF Symbols to pick from; any not available on this macOS are hidden.
    static let symbolChoices: [String] = [
        "folder", "star", "heart", "sparkles", "flame", "bolt", "crown", "trophy",
        "newspaper", "globe.americas", "building.columns", "flag", "megaphone", "mic", "quote.bubble",
        "bubble.left.and.bubble.right", "person.2", "figure.2.and.child.holdinghands",
        "face.smiling", "theatermasks", "party.popper", "gamecontroller", "puzzlepiece",
        "film", "tv", "music.note", "guitars", "headphones", "camera", "paintpalette", "paintbrush",
        "book", "graduationcap", "lightbulb", "brain.head.profile", "atom", "flask", "cpu",
        "desktopcomputer", "iphone", "wrench.and.screwdriver", "hammer", "car", "airplane", "map",
        "sportscourt", "football", "basketball", "figure.run", "dumbbell", "bicycle",
        "fork.knife", "cup.and.saucer", "wineglass", "carrot", "leaf", "pawprint", "tree", "mountain.2",
        "sun.max", "moon", "cloud.sun", "house", "briefcase", "dollarsign.circle",
        "chart.line.uptrend.xyaxis", "cart", "bag", "tshirt", "stethoscope", "cross.case", "gift",
    ].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
}

enum CookieBrowser: String, Codable, CaseIterable, Identifiable {
    case none, safari, chrome, firefox, brave, edge
    var id: String { rawValue }
    var label: String { self == .none ? "Don't use cookies" : rawValue.capitalized }
}

/// A time of day the scheduled download runs.
struct ScheduleTime: Codable, Hashable {
    var hour: Int
    var minute: Int
}

/// What each category does in playback, shared with the phones: the newest change on any device wins, swapped through
/// `POST /positions` (API 8). Categories are named by the keys of a mix's `picked` cards: a category's id, `otherCard`,
/// `vineCard`, or (long videos, 1× only) `playlistCard`. Empty sets mean every category is in Automix and can be sped up.
struct PlaybackRules: Codable, Equatable {
    struct Cards: Codable, Equatable {
        /// Left out of Automix unless picked by holding its button. A category's own Automix still plays it.
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

    /// When these last changed. 1970 until they're first changed, so anything set on a phone wins.
    var at = Date(timeIntervalSince1970: 0)
    var short = Cards()
    var long = Cards()
    /// Long videos go back this far when they resume, to pick the thread up again.
    var resumeRewindSeconds = 0
    /// Only on the wire: the Mac keeps it in `AppSettings.timeLimitMinutes`, which older builds and the manifest read.
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
}

struct AppSettings: Codable, Equatable {
    var scheduleEnabled = true
    /// The first scheduled time. The others are in `extraScheduleTimes`, so older builds still read this one.
    var scheduleHour = 3
    var scheduleMinute = 0
    var extraScheduleTimes: [ScheduleTime] = []
    var defaultDays = 3
    var libraryPath = Paths.defaultLibrary.path
    /// For TikTok creators; the key predates YouTube support.
    var cookieBrowser: CookieBrowser = .none
    var youtubeCookieBrowser: CookieBrowser = .none
    var deleteOutsideWindow = false
    var timeLimitMinutes = 10
    var playbackRules = PlaybackRules()
    /// For TikTok creators; the key predates YouTube support.
    var downloadOnLaunch = false
    var downloadYouTubeOnLaunch = false
    var syncEnabled = false
    var syncDiscoverable = true
    /// Experimental: download Vine classics from divine.video and mix them into Automix (see Vine.swift).
    var vineEnabled = false
    /// How many new Vines each download fetches.
    var vineBatchSize = 25
    /// Rewrite short videos' audio to the same loudness after downloading them (see Loudness.swift).
    var evenOutVolume = true
    /// How much downloads write to logs/downloads.log (see DownloadLog.swift).
    var logLevel = LogLevel.normal
    /// Settings > iPod (see IPod.swift): which iPod exports are made for, the mix's length in minutes and the cards it
    /// draws from (a category's id or `otherCard`), and the folder exports go to (nil until one is chosen).
    var ipodModel = IPodModel.nano7
    var ipodMixMinutes = 30
    var ipodCategories: [String] = []
    var ipodExportPath: String?

    var libraryURL: URL { URL(fileURLWithPath: libraryPath, isDirectory: true) }

    /// Every time of day the scheduled download runs; there's always at least one.
    var scheduleTimes: [ScheduleTime] {
        get { [ScheduleTime(hour: scheduleHour, minute: scheduleMinute)] + extraScheduleTimes }
        set {
            guard let first = newValue.first else { return }
            scheduleHour = first.hour
            scheduleMinute = first.minute
            extraScheduleTimes = Array(newValue.dropFirst())
        }
    }

    init() {}

    // Tolerate missing keys so new settings don't wipe an existing config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        scheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? d.scheduleEnabled
        scheduleHour = try c.decodeIfPresent(Int.self, forKey: .scheduleHour) ?? d.scheduleHour
        scheduleMinute = try c.decodeIfPresent(Int.self, forKey: .scheduleMinute) ?? d.scheduleMinute
        extraScheduleTimes = try c.decodeIfPresent([ScheduleTime].self, forKey: .extraScheduleTimes) ?? d.extraScheduleTimes
        defaultDays = try c.decodeIfPresent(Int.self, forKey: .defaultDays) ?? d.defaultDays
        libraryPath = try c.decodeIfPresent(String.self, forKey: .libraryPath) ?? d.libraryPath
        cookieBrowser = try c.decodeIfPresent(CookieBrowser.self, forKey: .cookieBrowser) ?? d.cookieBrowser
        // Before it had its own setting, YouTube used the TikTok browser.
        youtubeCookieBrowser = try c.decodeIfPresent(CookieBrowser.self, forKey: .youtubeCookieBrowser) ?? cookieBrowser
        deleteOutsideWindow = try c.decodeIfPresent(Bool.self, forKey: .deleteOutsideWindow) ?? d.deleteOutsideWindow
        timeLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .timeLimitMinutes) ?? d.timeLimitMinutes
        playbackRules = (try? c.decodeIfPresent(PlaybackRules.self, forKey: .playbackRules)) ?? d.playbackRules
        downloadOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .downloadOnLaunch) ?? d.downloadOnLaunch
        downloadYouTubeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .downloadYouTubeOnLaunch) ?? d.downloadYouTubeOnLaunch
        syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? d.syncEnabled
        syncDiscoverable = try c.decodeIfPresent(Bool.self, forKey: .syncDiscoverable) ?? d.syncDiscoverable
        vineEnabled = try c.decodeIfPresent(Bool.self, forKey: .vineEnabled) ?? d.vineEnabled
        vineBatchSize = try c.decodeIfPresent(Int.self, forKey: .vineBatchSize) ?? d.vineBatchSize
        evenOutVolume = try c.decodeIfPresent(Bool.self, forKey: .evenOutVolume) ?? d.evenOutVolume
        logLevel = (try? c.decodeIfPresent(LogLevel.self, forKey: .logLevel)) ?? d.logLevel
        ipodModel = (try? c.decodeIfPresent(IPodModel.self, forKey: .ipodModel)) ?? d.ipodModel
        ipodMixMinutes = try c.decodeIfPresent(Int.self, forKey: .ipodMixMinutes) ?? d.ipodMixMinutes
        ipodCategories = try c.decodeIfPresent([String].self, forKey: .ipodCategories) ?? d.ipodCategories
        ipodExportPath = try c.decodeIfPresent(String.self, forKey: .ipodExportPath)
    }
}

struct Config: Codable {
    var settings = AppSettings()
    var creators: [Creator] = []
    var categories: [Category] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        creators = try c.decodeIfPresent([Creator].self, forKey: .creators) ?? []
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.config) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Never silently replace a config we couldn't read: keep a copy before starting fresh.
            let backup = Paths.appSupport.appendingPathComponent("config.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: backup)
            return Config()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Paths.config, options: .atomic)
    }
}

struct CreatorRunInfo: Codable {
    var date: Date
    var newVideos: Int
    var removed: Int
    var error: String?
    /// The last run that finished without an error, which decides download priority.
    var lastSuccess: Date?
    /// Videos in the window left for a later run because they had too few views (see Creator.minViews).
    var belowMinViews: Int?
}

/// Results of download runs. Written by whichever process (app or scheduled job) holds the download lock.
struct RunState: Codable {
    var lastRun: Date?
    /// When short and long videos were last downloaded (a run that included them and finished); nil from builds
    /// before these were kept, until the next download.
    var lastShortRun: Date?
    var lastLongRun: Date?
    var creators: [String: CreatorRunInfo] = [:]

    static func load() -> RunState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Paths.state),
              let state = try? decoder.decode(RunState.self, from: data) else { return RunState() }
        return state
    }

    /// Serializes read-modify-write so creators finishing at the same time don't lose each other's results.
    private static let lock = NSLock()

    static func update(_ body: (inout RunState) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var state = load()
        body(&state)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(state).write(to: Paths.state, options: .atomic)
    }

    static func record(_ result: DownloadResult, for username: String) {
        update {
            let now = Date()
            let lastSuccess = result.error == nil ? now : $0.creators[username]?.lastSuccess
            $0.creators[username] = CreatorRunInfo(date: now, newVideos: result.newVideos, removed: result.removed,
                                                   error: result.error, lastSuccess: lastSuccess,
                                                   belowMinViews: result.belowMinViews)
        }
    }
}

struct Video: Identifiable, Hashable {
    let id: String
    let creator: String
    let url: URL
    let date: Date
    let caption: String
    let duration: Int?
    let viewCount: Int?
    var form = VideoForm.short
    /// From yt-dlp's metadata; `caption` is the description, or the title when there's none. Long videos show both.
    var title = ""
    var details = ""
    /// The file's size in bytes, read when the library is scanned.
    var size: Int64 = 0

    /// For long videos: the title, or the caption if there's no title.
    var displayTitle: String { !title.isEmpty ? title : !caption.isEmpty ? caption : "Untitled" }
    /// A poster image yt-dlp saved beside a long video (same name, .jpg), if any.
    var posterURL: URL { url.deletingPathExtension().appendingPathExtension("jpg") }
}

/// One creator's videos of one form. A YouTube creator with both turned on has a short and a long library.
struct CreatorLibrary: Identifiable {
    let creator: Creator
    let nickname: String?
    let avatar: URL?
    let videos: [Video]
    var form = VideoForm.short
    var id: String { creator.id }
    var displayName: String { nickname ?? (creator.playlist ? "YouTube Playlist" : "@\(creator.username)") }
}

/// Whether a video has been started, and when that last changed. The time lets the Mac and the phone
/// merge their histories: the newest change wins, so "mark as unplayed" syncs too.
struct PlayedMark: Codable, Equatable {
    var played: Bool
    var at: Date
}

enum PlayedStore {
    static func load() -> [String: PlayedMark] {
        guard let data = try? Data(contentsOf: Paths.played) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let marks = try? decoder.decode([String: PlayedMark].self, from: data) { return marks }
        // Before 1.2 this was a plain list of played IDs. Date them long ago so any newer change wins.
        guard let ids = try? JSONDecoder().decode([String].self, from: data) else { return [:] }
        let old = Date(timeIntervalSince1970: 0)
        return Dictionary(ids.map { ($0, PlayedMark(played: true, at: old)) }, uniquingKeysWith: { a, _ in a })
    }

    static func save(_ marks: [String: PlayedMark]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try? encoder.encode(marks).write(to: Paths.played, options: .atomic)
    }
}

/// Whether a video is saved to Watch Later, and when that last changed, so the Mac and phone can merge
/// their lists the same way as watched state (newest change wins).
struct WatchLaterMark: Codable, Equatable {
    var saved: Bool
    var at: Date
}

enum WatchLaterStore {
    static func load(from url: URL = Paths.watchLater) -> [String: WatchLaterMark] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let marks = try? decoder.decode([String: WatchLaterMark].self, from: data) else { return [:] }
        return marks
    }

    static func save(_ marks: [String: WatchLaterMark], to url: URL = Paths.watchLater) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try? encoder.encode(marks).write(to: url, options: .atomic)
    }
}

/// Bookmarks use the same marks as Watch Later (bookmarked or not, and when that changed), in bookmarks.json.
/// Bookmarked videos stay out of Automix and are never deleted automatically.
enum BookmarkStore {
    static func load() -> [String: WatchLaterMark] { WatchLaterStore.load(from: Paths.bookmarks) }
    static func save(_ marks: [String: WatchLaterMark]) { WatchLaterStore.save(marks, to: Paths.bookmarks) }
    /// For the scheduled download, which deletes old videos without the app's model.
    static func bookmarkedIDs() -> Set<String> { Set(load().filter(\.value.saved).keys) }
}

/// Long videos picked by hand from a creator's older videos: `{videoID: ISO8601}`, in handpicked.json.
/// Videos exported for an iPod (Settings > iPod) use the same shape, in ipod.json.
enum HandPickedStore {
    static func load(from url: URL = Paths.handPicked) -> [String: Date] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([String: Date].self, from: $0) } ?? [:]
    }

    static func save(_ marks: [String: Date], to url: URL = Paths.handPicked) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(marks).write(to: url, options: .atomic)
    }
}

/// How far into a long video playback got, and when that last changed, so the Mac and phones can merge them: the
/// newest change wins. No `seconds` means it was cleared (the video was finished), which syncs too.
struct PositionMark: Codable, Equatable {
    var seconds: Double?
    var at: Date

    /// Whole seconds, because that's all the dates in the sync API carry.
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

enum PositionStore {
    static func load() -> [String: PositionMark] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Paths.positionMarks),
           let marks = try? decoder.decode([String: PositionMark].self, from: data) { return marks }
        // Before they synced these had no dates. Date them long ago so any newer change wins.
        guard let data = try? Data(contentsOf: Paths.positions),
              let positions = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        let old = Date(timeIntervalSince1970: 0)
        return positions.mapValues { PositionMark(seconds: $0, at: old) }
    }

    static func save(_ marks: [String: PositionMark]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try? encoder.encode(marks).write(to: Paths.positionMarks, options: .atomic)
    }
}

/// The long video last playing on any device, so the others can have it ready. No `id` means it was closed or finished.
struct NowPlayingMark: Codable, Equatable {
    var id: String?
    var at: Date

    static func now(_ id: String?) -> NowPlayingMark {
        NowPlayingMark(id: id, at: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)))
    }

    /// Newest wins. Within the same second, the larger id, so every device settles on the same mark.
    func supersedes(_ other: NowPlayingMark) -> Bool {
        at != other.at ? at > other.at : (id ?? "") > (other.id ?? "")
    }

    static func load() -> NowPlayingMark {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: Paths.nowPlaying)).flatMap { try? decoder.decode(NowPlayingMark.self, from: $0) }
            ?? NowPlayingMark(id: nil, at: Date(timeIntervalSince1970: 0))
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(self).write(to: Paths.nowPlaying, options: .atomic)
    }
}

/// A phone that has been paired for sync. Only a hash of its token is kept.
struct SyncDevice: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var tokenHash: String
    var pairedAt: Date
    var lastSync: Date?
}

enum SyncStore {
    static func load() -> [SyncDevice] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Paths.sync),
              let devices = try? decoder.decode([SyncDevice].self, from: data) else { return [] }
        return devices
    }

    static func save(_ devices: [SyncDevice]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try? encoder.encode(devices).write(to: Paths.sync, options: .atomic)
    }
}
