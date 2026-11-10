import AppKit
import AVFoundation
import Foundation
import Observation

enum CreatorStatus: Equatable {
    case idle, queued, downloading
}

@MainActor @Observable
final class AppModel {
    var config = Config.load() {
        didSet { config.save() }
    }
    /// Every creator's short videos (TikTok, YouTube Shorts). Creators & Downloads and phone sync use these.
    var libraries: [CreatorLibrary] = []
    /// Long YouTube videos, for creators who have them turned on. Not synced to phones (yet).
    var longLibraries: [CreatorLibrary] = []
    /// Vine authors (see Vine.swift), while Vine is turned on. Short videos, but kept apart from `libraries` so they
    /// stay out of Top lists, Creators & Downloads' creator list and phones that don't ask for them.
    var vineLibraries: [CreatorLibrary] = []
    /// Which sidebar is showing: short or long videos. Always short at launch.
    #if DEBUG
    var form: VideoForm = ProcessInfo.processInfo.environment["CURATED_TEST_FORM"] == "long" ? .long : .short  // for tests
    #else
    var form = VideoForm.short
    #endif
    var runState = RunState.load()
    /// The saved history, with when each video's state last changed (for syncing with the phone).
    private(set) var playedMarks = PlayedStore.load() {
        didSet { PlayedStore.save(playedMarks) }
    }
    /// IDs of videos that have been started at least once.
    private(set) var played: Set<String> = []
    /// Watch Later history, including removals (for syncing with the phone).
    private(set) var watchLaterMarks = WatchLaterStore.load() {
        didSet { WatchLaterStore.save(watchLaterMarks) }
    }
    /// Bookmarks, including removals (for syncing with the phone).
    private(set) var bookmarkMarks = BookmarkStore.load() {
        didSet { BookmarkStore.save(bookmarkMarks) }
    }
    /// Where each long video was left off (see `Playback.savePosition`).
    private(set) var positionMarks = PositionStore.load() {
        didSet { PositionStore.save(positionMarks) }
    }
    /// Long videos picked by hand from a creator's older videos, and when.
    private(set) var handPicked = HandPickedStore.load() {
        didSet { HandPickedStore.save(handPicked) }
    }
    /// Videos exported for an iPod (Settings > iPod), and when: the sidebar's iPod list. Mac only, not synced.
    private(set) var ipodExports = HandPickedStore.load(from: Paths.ipod) {
        didSet { HandPickedStore.save(ipodExports, to: Paths.ipod) }
    }
    /// Called with the videos whose position just changed because of a phone, so a paused player can move there.
    @ObservationIgnored var onPositionsMerged: ((Set<String>) -> Void)?
    /// The long video last playing on any device.
    private(set) var nowPlayingMark = NowPlayingMark.load() {
        didSet { nowPlayingMark.save() }
    }
    /// A phone's newer now playing mark just arrived.
    @ObservationIgnored var onNowPlayingMerged: (() -> Void)?
    /// The playback rules changed, here or on a phone, so the playing video can change speed.
    @ObservationIgnored var onPlaybackRulesChanged: (() -> Void)?

    var isDownloading = false
    /// What the running download covers (short, long or both), so its button in Creators & Downloads can animate.
    private(set) var downloadingForms: Set<VideoForm> = []
    /// Whether the running download includes Vine.
    private(set) var downloadingVine = false
    var statuses: [String: CreatorStatus] = [:]
    /// The running download's creators (plus one for Vine), and how many of them have finished.
    private(set) var downloadUnits = 0
    private(set) var downloadUnitsDone = 0
    /// The long-video picker (see LongPicker.swift), from its listing until its download finishes.
    var longPick: LongPick?
    var log: [String] = []
    var lastActivity: String?
    var downloadMessage: String?
    /// Lengths read from the files themselves, for videos whose metadata has none.
    var loadedDurations: [String: TimeInterval] = [:]
    @ObservationIgnored private var loadingDurations: Set<String> = []

    // Phone sync (see PhoneSync.swift)
    var syncDevices = SyncStore.load() {
        didSet { SyncStore.save(syncDevices) }
    }
    /// Shown on the Mac while a phone can pair; nil otherwise.
    var pairingCode: String?
    var pairingExpires: Date?
    var syncError: String?
    @ObservationIgnored var syncServer: SyncServer?
    @ObservationIgnored var failedPairings = 0
    @ObservationIgnored var pairingTimeout: Task<Void, Never>?
    /// USB sync through `adb reverse` (see UsbSync.swift). On at every launch rather than saved.
    var usbSyncEnabled = true {
        didSet { updateUsbSync() }
    }
    /// Connected Android phones, and whether each one's USB sync reaches this Mac.
    var usbDevices: [AdbReverse.Device] = []
    @ObservationIgnored var usbSyncTask: Task<Void, Never>?

    private var runner: ProcessRunner?

    var settings: AppSettings {
        get { config.settings }
        set {
            let scheduleChanged = newValue.scheduleEnabled != config.settings.scheduleEnabled
                || newValue.scheduleTimes != config.settings.scheduleTimes
            let libraryChanged = newValue.libraryPath != config.settings.libraryPath
                || newValue.vineEnabled != config.settings.vineEnabled
            let syncChanged = newValue.syncEnabled != config.settings.syncEnabled
                || newValue.syncDiscoverable != config.settings.syncDiscoverable
            config.settings = newValue
            if scheduleChanged { Scheduler.sync(newValue) }
            if libraryChanged { reloadLibrary() }
            if syncChanged { updateSyncServer() }
        }
    }

    init() {
        played = Set(playedMarks.filter(\.value.played).keys)
        Scheduler.sync(config.settings)  // keeps the LaunchAgent pointing at this copy of the app
        reloadLibrary()
        updateSyncServer()
        #if DEBUG
        // Lets a test pair without clicking through the UI. Compiled out of release builds.
        if let code = ProcessInfo.processInfo.environment["CURATED_TEST_PAIRING_CODE"] { startPairing(code: code) }
        #endif
        download(config.creators.filter {
            $0.platform == .tiktok ? config.settings.downloadOnLaunch : config.settings.downloadYouTubeOnLaunch
        })
    }

    func reloadLibrary() {
        let settings = config.settings
        libraries = config.creators.map { Library.scan($0, settings: settings) }
        longLibraries = config.creators.filter(\.downloadsLongForm).map { Library.scan($0, form: .long, settings: settings) }
        // The Suggestions playlist, after the real ones, once anything has been downloaded to it.
        if FileManager.default.fileExists(atPath: Library.folder(for: Creator.suggestions.id, settings: settings).path) {
            longLibraries.append(Library.scan(.suggestions, form: .long, settings: settings))
        }
        vineLibraries = settings.vineEnabled ? Vine.scan(settings: settings) : []
        runState = RunState.load()
        loadMissingDurations()
    }

    /// A video's length in seconds, or nil while it's still being read from the file.
    func duration(of video: Video) -> TimeInterval? {
        video.duration.map(TimeInterval.init) ?? loadedDurations[video.id]
    }

    func totalDuration(_ videos: some Sequence<Video>) -> TimeInterval {
        videos.reduce(0) { $0 + (duration(of: $1) ?? 0) }
    }

    private func loadMissingDurations() {
        let missing = (libraries + longLibraries + vineLibraries).flatMap(\.videos)
            .filter { $0.duration == nil && loadedDurations[$0.id] == nil && !loadingDurations.contains($0.id) }
        guard !missing.isEmpty else { return }
        loadingDurations.formUnion(missing.map(\.id))
        Task {
            for video in missing {
                loadedDurations[video.id] = await Library.duration(of: video)
            }
        }
    }

    func library(for creatorID: String, form: VideoForm = .short) -> CreatorLibrary? {
        (form == .short ? libraries + vineLibraries : longLibraries).first { $0.id == creatorID }
    }

    /// The creators shown in a form's sidebar: everyone with that form turned on, or only those in `category`.
    /// A YouTube creator with long videos turned on and no short videos on disk stays out of the short sidebar (and
    /// phone sync), even with Shorts on.
    func watchLibraries(_ form: VideoForm, in category: UUID? = nil) -> [CreatorLibrary] {
        let all = form == .long ? longLibraries : libraries.filter {
            $0.creator.downloadsShorts && !($0.creator.downloadsLongForm && $0.videos.isEmpty)
        }
        guard let category else { return all }
        return all.filter { $0.creator.category == category }
    }

    /// Uncategorized creators, for the "Other Creators" card. Playlists have their own card.
    func uncategorizedWatchLibraries(_ form: VideoForm) -> [CreatorLibrary] {
        watchLibraries(form).filter { category($0.creator.category) == nil && !$0.creator.playlist }
    }

    /// What the mixes (Automix, Latest, Top) draw from: playlists are watched on their own, in order, so they stay out.
    func mixLibraries(_ form: VideoForm, in category: UUID? = nil) -> [CreatorLibrary] {
        watchLibraries(form, in: category).filter { !$0.creator.playlist }
    }

    /// What Automix draws from: `mixLibraries`, plus every Vine as one more creator in the main short Automix and a
    /// Funny category's.
    /// With no `category` it's the main Automix, which leaves out the cards turned off in Settings.
    func automixLibraries(_ form: VideoForm, in category: UUID? = nil) -> [CreatorLibrary] {
        let off = category == nil ? settings.playbackRules.cards(form).automixOff : []
        let libraries = mixLibraries(form, in: category).filter { !off.contains(cardKey($0.creator)) }
        guard form == .short, !vineLibraries.isEmpty, !off.contains(vineCard),
              category == nil || self.category(category).map({ Vine.categoryNames.contains($0.name.lowercased()) }) == true
        else { return libraries }
        return libraries + [Vine.mixLibrary(vineLibraries)]
    }

    /// The sidebar card a creator is under, as named in a mix's `picked` and the playback rules.
    func cardKey(_ creator: Creator) -> String {
        if creator.platform == .vine { return vineCard }
        if creator.playlist { return playlistCard }
        return category(creator.category)?.id.uuidString ?? otherCard
    }

    /// Whether `video`, played from `mode`, stays at 1×. A long video in a playlist's queue goes by the playlist.
    func playsAtNormalSpeed(_ video: Video, from mode: PlaybackMode?) -> Bool {
        var creator = library(for: video.creator, form: video.form)?.creator
        if video.form == .long, case .creator(let id) = mode, let queued = library(for: id, form: .long)?.creator, queued.playlist {
            creator = queued
        }
        return settings.playbackRules.cards(video.form).normalSpeed.contains(creator.map(cardKey) ?? otherCard)
    }

    /// Changes the playback rules from here, dated so the phones take them.
    func updatePlaybackRules(_ change: (inout PlaybackRules) -> Void) {
        var rules = settings.playbackRules
        change(&rules)
        guard rules != settings.playbackRules else { return }
        rules.at = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        settings.playbackRules = rules
        onPlaybackRulesChanged?()
    }

    func setTimeLimit(_ minutes: Int) {
        guard minutes != settings.timeLimitMinutes else { return }
        settings.timeLimitMinutes = minutes
        settings.playbackRules.at = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    /// Keeps the newer rules, and returns them for the phone with the time limit.
    func mergePlaybackRules(_ incoming: PlaybackRules?) -> PlaybackRules {
        if let incoming, incoming.at > settings.playbackRules.at {
            var rules = incoming
            if let minutes = rules.timeLimitMinutes { settings.timeLimitMinutes = max(1, minutes) }
            rules.timeLimitMinutes = nil
            settings.playbackRules = rules
            onPlaybackRulesChanged?()
        }
        var reply = settings.playbackRules
        reply.timeLimitMinutes = settings.timeLimitMinutes
        return reply
    }

    /// `mixLibraries` for a pick of the sidebar's cards (a mix's `picked`).
    func mixLibraries(_ form: VideoForm, picked: Set<String>) -> [CreatorLibrary] {
        mixLibraries(form).filter { picked.contains(category($0.creator.category)?.id.uuidString ?? otherCard) }
    }

    /// Automix for a pick of the sidebar's cards: Vines only when their card is picked.
    func automixLibraries(_ form: VideoForm, picked: Set<String>) -> [CreatorLibrary] {
        let libraries = mixLibraries(form, picked: picked)
        guard form == .short, !vineLibraries.isEmpty, picked.contains(vineCard) else { return libraries }
        return libraries + [Vine.mixLibrary(vineLibraries)]
    }

    /// `videos` with the unwatched ones picked by hand first, latest pick first: an old video someone chose shouldn't
    /// wait behind every newer one. Once watched it goes back to its place.
    func handPickedFirst(_ videos: [Video]) -> [Video] {
        guard !handPicked.isEmpty else { return videos }
        let first = videos.filter { handPicked[$0.id] != nil && !played.contains($0.id) }
        guard !first.isEmpty else { return videos }
        let ids = Set(first.map(\.id))
        return first.sorted { handPicked[$0.id]! > handPicked[$1.id]! } + videos.filter { !ids.contains($0.id) }
    }

    /// YouTube playlists, for the long sidebar's Playlists card.
    var playlistLibraries: [CreatorLibrary] { longLibraries.filter(\.creator.playlist) }

    func isPlayed(_ video: Video) -> Bool { played.contains(video.id) }

    func setPlayed(_ video: Video, _ value: Bool) {
        mark([video.id], played: value)
    }

    func setPlayed(_ videos: [Video], _ value: Bool) {
        mark(videos.map(\.id), played: value)
    }

    func markAllUnplayed() {
        mark(Array(played), played: false)
    }

    private func mark(_ ids: [String], played value: Bool) {
        let changed = ids.filter { played.contains($0) != value }
        guard !changed.isEmpty else { return }
        let now = Date()
        var marks = playedMarks
        for id in changed { marks[id] = PlayedMark(played: value, at: now) }
        playedMarks = marks
        if value { played.formUnion(changed) } else { played.subtract(changed) }
        // A watched video starts from the beginning next time.
        if value, changed.contains(where: { positionMarks[$0]?.seconds != nil }) {
            var positions = positionMarks
            for id in changed where positions[id]?.seconds != nil { positions[id] = .now(nil) }
            positionMarks = positions
        }
        if value, let id = nowPlayingMark.id, changed.contains(id) { nowPlayingMark = .now(nil) }
        // Watching a saved video takes it off Watch Later.
        if value { setWatchLater(changed, false) }
    }

    // MARK: Resume

    func resumePosition(of video: Video) -> TimeInterval? { positionMarks[video.id]?.seconds }

    func setResumePosition(_ seconds: TimeInterval?, for video: Video) {
        if positionMarks[video.id]?.seconds != seconds { positionMarks[video.id] = .now(seconds) }
        if seconds == nil { clearNowPlaying(video) }
    }

    /// `video` started or resumed here.
    func setNowPlaying(_ video: Video) { nowPlayingMark = .now(video.id) }

    /// `video` was closed or finished, so no other device should offer it.
    func clearNowPlaying(_ video: Video) {
        if nowPlayingMark.id == video.id { nowPlayingMark = .now(nil) }
    }

    /// Keeps the newest now playing mark, and returns it for the phone.
    func mergeNowPlaying(_ incoming: NowPlayingMark?) -> NowPlayingMark {
        if let incoming, incoming.supersedes(nowPlayingMark) {
            nowPlayingMark = incoming
            onNowPlayingMerged?()
        }
        return nowPlayingMark
    }

    /// Keeps the newest position of each video. One saved before the video was last marked watched is cleared, so a
    /// watched video starts from the top on every device. Returns the merged marks for the phone.
    func mergePositions(_ incoming: [String: PositionMark]) -> [String: PositionMark] {
        var marks = positionMarks
        for (id, mark) in incoming where mark.supersedes(marks[id]) { marks[id] = mark }
        for (id, mark) in marks where mark.seconds != nil {
            if let played = playedMarks[id], played.played, played.at >= mark.at {
                marks[id] = PositionMark(seconds: nil, at: played.at)
            }
        }
        guard marks != positionMarks else { return marks }
        let changed = Set(marks.keys.filter { marks[$0]?.seconds != positionMarks[$0]?.seconds })
        positionMarks = marks
        onPositionsMerged?(changed)
        return marks
    }

    /// How much of a long video has been watched, 0...1, while it has somewhere to resume from.
    func progress(of video: Video) -> Double? {
        guard let position = positionMarks[video.id]?.seconds, let length = duration(of: video), length > 0 else { return nil }
        return min(1, position / length)
    }

    // MARK: Watch Later

    func isSavedForLater(_ video: Video) -> Bool { watchLaterMarks[video.id]?.saved == true }

    func setWatchLater(_ video: Video, _ saved: Bool) { setWatchLater([video.id], saved) }

    private func setWatchLater(_ ids: [String], _ saved: Bool) {
        let changed = ids.filter { (watchLaterMarks[$0]?.saved == true) != saved }
        guard !changed.isEmpty else { return }
        let now = Date()
        var marks = watchLaterMarks
        for id in changed { marks[id] = WatchLaterMark(saved: saved, at: now) }
        watchLaterMarks = marks
    }

    /// A form's videos, once each: a long video can be both a creator's and in a playlist.
    private func uniqueVideos(_ form: VideoForm) -> [Video] {
        var seen: Set<String> = []
        let vines = form == .short ? vineLibraries : []
        return (watchLibraries(form) + vines).flatMap(\.videos).filter { seen.insert($0.id).inserted }
    }

    /// Saved, unwatched videos of `form` that are still on disk, oldest save first.
    func watchLaterVideos(_ form: VideoForm) -> [Video] {
        uniqueVideos(form)
            .filter { isSavedForLater($0) && !isPlayed($0) }
            .sorted { (watchLaterMarks[$0.id]?.at ?? .distantPast) < (watchLaterMarks[$1.id]?.at ?? .distantPast) }
    }

    /// Like `mergePlayed`, for Watch Later.
    func mergeWatchLater(_ incoming: [String: WatchLaterMark]) -> [String: WatchLaterMark] {
        var marks = watchLaterMarks
        for (id, mark) in incoming where mark.at > (marks[id]?.at ?? .distantPast) {
            marks[id] = mark
        }
        if marks != watchLaterMarks { watchLaterMarks = marks }
        return marks
    }

    // MARK: iPod list

    /// Videos of `form` exported for an iPod and still on disk, watched or not, most recently exported first.
    func ipodVideos(_ form: VideoForm) -> [Video] {
        guard !ipodExports.isEmpty else { return [] }
        return (form == .short ? libraries : longLibraries).flatMap(\.videos)
            .filter { ipodExports[$0.id] != nil }
            .sorted { (ipodExports[$0.id] ?? .distantPast) > (ipodExports[$1.id] ?? .distantPast) }
    }

    func addToIPodList(_ videos: [Video]) {
        guard !videos.isEmpty else { return }
        var marks = ipodExports
        let now = Date()
        // In the order exported: the first gets the latest date, so the list reads in mix order.
        for (i, video) in videos.enumerated() { marks[video.id] = now.addingTimeInterval(-Double(i) * 0.001) }
        ipodExports = marks
    }

    /// Empties the iPod list for `form`.
    func clearIPodList(_ form: VideoForm) {
        let ids = Set(ipodVideos(form).map(\.id))
        ipodExports = ipodExports.filter { !ids.contains($0.key) }
    }

    // MARK: Bookmarks

    func isBookmarked(_ video: Video) -> Bool { bookmarkMarks[video.id]?.saved == true }

    var bookmarkedIDs: Set<String> { Set(bookmarkMarks.filter(\.value.saved).keys) }

    func setBookmarked(_ video: Video, _ bookmarked: Bool) {
        guard isBookmarked(video) != bookmarked else { return }
        bookmarkMarks[video.id] = WatchLaterMark(saved: bookmarked, at: Date())
    }

    /// Bookmarked videos of `form` still on disk, watched or not, most recently bookmarked first.
    func bookmarkedVideos(_ form: VideoForm) -> [Video] {
        uniqueVideos(form)
            .filter(isBookmarked)
            .sorted { (bookmarkMarks[$0.id]?.at ?? .distantPast) > (bookmarkMarks[$1.id]?.at ?? .distantPast) }
    }

    /// Like `mergePlayed`, for bookmarks.
    func mergeBookmarks(_ incoming: [String: WatchLaterMark]) -> [String: WatchLaterMark] {
        var marks = bookmarkMarks
        for (id, mark) in incoming where mark.at > (marks[id]?.at ?? .distantPast) {
            marks[id] = mark
        }
        if marks != bookmarkMarks { bookmarkMarks = marks }
        return marks
    }

    /// Moves one video to the Trash, bookmarked or not. The creator's download archive still lists it, so it's never
    /// downloaded again; phones drop it on their next sync.
    func trash(_ video: Video) {
        guard (try? FileManager.default.trashItem(at: video.url, resultingItemURL: nil)) != nil else { return }
        try? FileManager.default.trashItem(at: video.posterURL, resultingItemURL: nil)
        setBookmarked(video, false)
        reloadLibrary()
    }

    /// For creators kept by count: the unwatched short videos past their count, which Trim would take away. The ones
    /// kept are the oldest unwatched (the next to come up), as many as the count; bookmarked videos are never trimmed
    /// and don't count, since they stay out of the mixes.
    /// With `vine`, Vine too (while it's on), under `Vine.feedID`: the ones kept are the first downloaded.
    func trimmableVideos(_ creators: [Creator], vine: Bool = false) -> [String: [Video]] {
        var plan: [String: [Video]] = [:]
        if vine && settings.vineEnabled {
            let order = Vine.downloadOrder(settings: settings)
            let unwatched = vineLibraries.flatMap(\.videos).filter { !isPlayed($0) && !isBookmarked($0) }
                .sorted { (order[$0.id] ?? .max, $0.id) < (order[$1.id] ?? .max, $1.id) }
            if unwatched.count > settings.vineBatchSize { plan[Vine.feedID] = Array(unwatched.dropFirst(settings.vineBatchSize)) }
        }
        for creator in creators where creator.keepsByCount {
            guard let keep = creator.keepVideos, let library = library(for: creator.id) else { continue }
            let unwatched = library.videos.filter { !isPlayed($0) && !isBookmarked($0) }.sorted { $0.date < $1.date }
            if unwatched.count > keep { plan[creator.id] = Array(unwatched.dropFirst(keep)) }
        }
        return plan
    }

    /// Moves the videos `trimmableVideos` lists to the Trash and takes them out of their creators' download history,
    /// so they download again in their turn (new posts oldest first, or with Historical). Returns how many were
    /// trimmed, or nil if a download is running.
    @discardableResult
    func trimToKeep(_ creators: [Creator], vine: Bool = false) -> Int? {
        guard !isDownloading else { return nil }
        let lock = DownloadLock()
        guard lock.tryAcquire() else { return nil }
        defer { lock.release() }
        var trimmed = 0
        for (creatorID, videos) in trimmableVideos(creators, vine: vine) {
            let gone = videos.filter { (try? FileManager.default.trashItem(at: $0.url, resultingItemURL: nil)) != nil }
            for video in gone { try? FileManager.default.trashItem(at: video.posterURL, resultingItemURL: nil) }
            if creatorID == Vine.feedID {
                Vine.forget(gone, settings: config.settings)
            } else {
                Library.forget(Set(gone.map(\.id)), in: Library.folder(for: creatorID, settings: config.settings))
            }
            trimmed += gone.count
            let name = creatorID == Vine.feedID ? "Vine" : library(for: creatorID)?.displayName ?? creatorID
            if !gone.isEmpty { appendLog("\(name): trimmed \(gone.count) to Trash, to download again later") }
        }
        reloadLibrary()
        return trimmed
    }

    /// Watched videos still on disk that Delete All Watched Videos would remove (bookmarks are kept).
    var watchedVideoCount: Int {
        (libraries + longLibraries + vineLibraries).reduce(0) { $0 + $1.videos.count { isPlayed($0) && !isBookmarked($0) } }
    }

    /// Deletes the files of every watched video except bookmarked ones. Each creator's download archive still lists
    /// them, so they're never downloaded again, and their watched state is kept. Phones drop them on their next sync.
    @discardableResult
    func deleteWatchedVideos() -> Int {
        var removed = 0
        for video in (libraries + longLibraries + vineLibraries).flatMap(\.videos) where isPlayed(video) && !isBookmarked(video) {
            if (try? FileManager.default.removeItem(at: video.url)) != nil { removed += 1 }
            try? FileManager.default.removeItem(at: video.posterURL)
        }
        reloadLibrary()
        return removed
    }

    /// Takes the newer of each video's state from the phone and the Mac. Returns the merged history.
    func mergePlayed(_ incoming: [String: PlayedMark]) -> [String: PlayedMark] {
        var marks = playedMarks
        for (id, mark) in incoming where mark.at > (marks[id]?.at ?? .distantPast) {
            marks[id] = mark
        }
        if marks != playedMarks {
            playedMarks = marks
            played = Set(marks.filter(\.value.played).keys)
        }
        return marks
    }

    /// Short videos outside each creator's own download window (e.g. >3 days old for a 3-day creator).
    /// Long videos are never deleted for their age.
    func oldVideoCount() -> Int { oldVideos().count }

    /// The files `deleteOldVideos` would remove.
    func oldVideos() -> [URL] {
        config.creators.filter { !$0.playlist && !$0.keepsByCount }.flatMap {
            Library.videos(in: Library.folder(for: $0.id, settings: config.settings),
                           olderThan: Library.cutoff(for: $0), keeping: bookmarkedIDs)
        }
    }

    /// Every folder in the library that Curated made: each creator's (short and long), playlists' and Vines'. Anything
    /// else someone keeps in there is left alone.
    func libraryFolders() -> [URL] {
        let names = Set(config.creators.flatMap { [$0.id, $0.longFormFolderName] })
        let prefixes = ["youtube@", "youtube-long@", "youtube-playlist@", Vine.folderPrefix]
        let entries = (try? FileManager.default.contentsOfDirectory(at: settings.libraryURL, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { url in
            let name = url.lastPathComponent
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && (names.contains(name) || prefixes.contains { name.hasPrefix($0) })
        }
    }

    /// Moves every creator's folder to the Trash: the videos, posters, avatars and download history. Creators,
    /// categories, settings and watched marks stay, so the next download starts the library afresh. Returns how many
    /// videos went, or nil while a download runs.
    @discardableResult
    func deleteLibrary() -> Int? {
        guard !isDownloading else { return nil }
        let count = (libraries + longLibraries + vineLibraries).reduce(0) { $0 + $1.videos.count }
        for folder in libraryFolders() { try? FileManager.default.trashItem(at: folder, resultingItemURL: nil) }
        reloadLibrary()
        return count
    }

    /// Back to a fresh install: the library's folders and the whole data folder (config, creators, history, Watch
    /// Later, bookmarks, positions, paired phones, logs) go to the Trash, the preferences and the overnight job are
    /// removed, and Curated starts again as if new. A test run (`CURATED_DATA_DIR`) only touches its own folders.
    func resetEverything(stopping playback: Playback) {
        cancelDownloads()
        playback.player.pause()
        playback.frozen = true
        syncServer?.stop()
        syncServer = nil
        for folder in libraryFolders() { try? FileManager.default.trashItem(at: folder, resultingItemURL: nil) }
        try? FileManager.default.trashItem(at: Paths.appSupport, resultingItemURL: nil)
        Scheduler.remove()
        // The bare debug binary's domain is its process name ("Curated"), never the real app's.
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
        UserDefaults.standard.synchronize()
        // Opens again once this one has quit; a bare binary (a test run) just quits.
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", bundle.path]
            try? relaunch.run()
        }
        NSApp.terminate(nil)
    }

    @discardableResult
    func deleteOldVideos() -> Int {
        // A playlist's folder holds long videos, which are never deleted for their age. Nor are short videos kept by
        // count.
        let removed = config.creators.filter { !$0.playlist && !$0.keepsByCount }.reduce(0) {
            $0 + Library.deleteVideos(in: Library.folder(for: $1.id, settings: config.settings),
                                      olderThan: Library.cutoff(for: $1), keeping: bookmarkedIDs)
        }
        reloadLibrary()
        return removed
    }

    func unplayedCount(_ library: CreatorLibrary) -> Int {
        library.videos.lazy.filter { !self.played.contains($0.id) }.count
    }

    // MARK: Categories

    var categories: [Category] { config.categories }

    func category(_ id: UUID?) -> Category? {
        id.flatMap { id in config.categories.first { $0.id == id } }
    }

    /// Libraries in a category, or all of them for nil.
    func libraries(in category: UUID?) -> [CreatorLibrary] {
        guard let category else { return libraries }
        return libraries.filter { $0.creator.category == category }
    }

    /// Creators in no category. Playlists are their own group.
    var uncategorizedLibraries: [CreatorLibrary] {
        libraries.filter { category($0.creator.category) == nil && !$0.creator.playlist }
    }

    /// Playlists as Creators & Downloads lists them.
    var playlistManageLibraries: [CreatorLibrary] { libraries.filter(\.creator.playlist) }

    @discardableResult
    /// Creates (id nil) or updates a category. Returns an error message, or nil on success.
    func saveCategory(_ id: UUID?, name: String, symbol: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Give the category a name." }
        guard !config.categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return "There's already a category called \(name)."
        }
        if let id, let i = config.categories.firstIndex(where: { $0.id == id }) {
            config.categories[i].name = name
            config.categories[i].symbol = symbol
        } else {
            config.categories.append(Category(name: name, symbol: symbol))
        }
        return nil
    }

    func setCollapsed(_ collapsed: Bool, for id: UUID) {
        guard let i = config.categories.firstIndex(where: { $0.id == id }),
              config.categories[i].collapsed != collapsed else { return }
        config.categories[i].collapsed = collapsed
    }

    /// For the mixes' counts, so playlists aren't included (and Vines are, where Automix plays them).
    func unplayedCount(in category: UUID?, form: VideoForm) -> Int {
        automixLibraries(form, in: category).reduce(0) { $0 + unplayedCount($1) }
    }

    /// Puts the categories in this order (the sidebar's and the phones'); any not listed keep their place at the end.
    func setCategoryOrder(_ ids: [UUID]) {
        let ordered = ids.compactMap { id in config.categories.first { $0.id == id } }
        let rest = config.categories.filter { !ids.contains($0.id) }
        if ordered + rest != config.categories { config.categories = ordered + rest }
    }

    /// Creators in a deleted category become uncategorized; nothing is removed from disk.
    func deleteCategory(_ id: UUID) {
        config.categories.removeAll { $0.id == id }
        for i in config.creators.indices where config.creators[i].category == id {
            config.creators[i].category = nil
        }
        reloadLibrary()
    }

    func setCategory(_ category: UUID?, for creatorID: String) {
        guard let i = config.creators.firstIndex(where: { $0.id == creatorID }) else { return }
        config.creators[i].category = category
        reloadLibrary()
    }

    // MARK: Creators

    @discardableResult
    func addCreator(_ input: String, platform: Platform, keep: KeepRule, category: UUID? = nil,
                    shorts: Bool = true, longForm: Bool = false, playlistLimit: Int? = nil) -> String? {
        let days = keep.days
        if let playlistID = Creator.playlistID(in: input) {
            let playlist = Creator(username: playlistID, days: max(1, days), platform: .youtube, playlist: true,
                                   playlistLimit: playlistLimit)
            guard !config.creators.contains(where: { $0.id == playlist.id }) else {
                return "That playlist is already in your list."
            }
            config.creators.append(playlist)
            reloadLibrary()
            return nil
        }
        guard let (username, platform) = Creator.parse(input, platform: platform) else {
            let youTube = platform == .youtube || input.localizedCaseInsensitiveContains("youtu")
            return youTube ? "That doesn't look like a YouTube handle or channel link (use the channel, not a video)."
                           : "That doesn't look like a TikTok username."
        }
        var creator = Creator(username: username, days: max(1, days), category: category, platform: platform,
                              shorts: shorts || !longForm, longForm: longForm)
        keep.apply(to: &creator)
        guard !config.creators.contains(where: { $0.id == creator.id }) else {
            return "@\(username) on \(platform.name) is already in your list."
        }
        config.creators.append(creator)
        reloadLibrary()
        return nil
    }

    /// Short videos from the last `days` days, or (with `videos`) that many unwatched ones. Long videos always use `days`.
    func setKeep(_ rule: KeepRule, for creatorID: String) {
        guard let i = config.creators.firstIndex(where: { $0.id == creatorID }) else { return }
        var creator = config.creators[i]
        rule.apply(to: &creator)
        guard creator != config.creators[i] else { return }
        config.creators[i] = creator
        reloadLibrary()
    }

    func setMinViews(_ minViews: Int?, for creatorID: String) {
        guard let i = config.creators.firstIndex(where: { $0.id == creatorID }) else { return }
        config.creators[i].minViews = minViews
        reloadLibrary()
    }

    /// YouTube only: which kinds of video to download. At least one stays on. Turning one off hides its videos but
    /// leaves the files on disk.
    func setForms(shorts: Bool, longForm: Bool, for creatorID: String) {
        guard shorts || longForm, let i = config.creators.firstIndex(where: { $0.id == creatorID }),
              config.creators[i].platform == .youtube, !config.creators[i].playlist else { return }
        config.creators[i].shorts = shorts
        config.creators[i].longForm = longForm
        reloadLibrary()
    }

    /// The highest resolution to download this creator's long videos at. Videos already downloaded stay as they are.
    /// nil is Best.
    func setLongFormHeight(_ height: Int?, for creatorID: String) {
        guard let i = config.creators.firstIndex(where: { $0.id == creatorID }) else { return }
        config.creators[i].longFormHeight = height
        reloadLibrary()
    }

    /// How many of a playlist's newest videos to download (nil: all). Videos already downloaded stay.
    func setPlaylistLimit(_ limit: Int?, for creatorID: String) {
        guard let i = config.creators.firstIndex(where: { $0.id == creatorID }), config.creators[i].playlist else { return }
        config.creators[i].playlistLimit = limit
        reloadLibrary()
    }

    func removeCreator(_ creatorID: String, deleteFiles: Bool) {
        let creator = config.creators.first { $0.id == creatorID }
        config.creators.removeAll { $0.id == creatorID }
        if deleteFiles {
            try? FileManager.default.removeItem(at: Library.folder(for: creatorID, settings: config.settings))
            if let creator, creator.platform == .youtube {
                try? FileManager.default.removeItem(at: Library.folder(for: creator, form: .long, settings: config.settings))
            }
        }
        reloadLibrary()
    }

    // MARK: Downloads

    func downloadAll() { download(config.creators, vine: settings.vineEnabled) }

    /// Just the next batch of Vines.
    func downloadVine() { download([], forms: [], vine: true) }

    func setVineBatchSize(_ size: Int) {
        settings.vineBatchSize = max(1, size)
    }

    /// Just the short videos: TikTok, and YouTube Shorts for those who have them turned on.
    func downloadShortForm() { download(config.creators.filter(\.downloadsShorts), forms: [.short]) }

    /// Downloads `creators` (their `forms`), and with `vine` the next batch of Vines first.
    /// How far the running download is, 0 to 1; nil while nothing downloads. A creator being downloaded counts as a
    /// quarter done, so the bar moves while the first ones run.
    var downloadProgress: Double? {
        guard isDownloading, downloadUnits > 0 else { return nil }
        let running = statuses.values.count { $0 == .downloading }
        return min(1, (Double(downloadUnitsDone) + 0.25 * Double(running)) / Double(downloadUnits))
    }

    /// With `only` (from the long-video picker), just those long videos of each creator listed there.
    func download(_ creators: [Creator], forms: Set<VideoForm> = Set(VideoForm.allCases), vine: Bool = false,
                  only: [String: Set<String>]? = nil, heights: [String: Int?] = [:]) {
        let vine = vine && settings.vineEnabled
        guard !isDownloading, !creators.isEmpty || vine else { return }
        let lock = DownloadLock()
        guard lock.tryAcquire() else {
            downloadMessage = "A scheduled download is already running. Try again when it finishes."
            return
        }
        isDownloading = true
        downloadingForms = creators.isEmpty ? [] : forms
        downloadingVine = vine
        downloadMessage = nil
        lastActivity = nil
        downloadUnits = creators.count + (vine ? 1 : 0)
        downloadUnitsDone = 0
        for c in creators { statuses[c.id] = .queued }
        if vine { statuses[Vine.feedID] = .queued }
        let runner = ProcessRunner()
        self.runner = runner
        let settings = config.settings

        Task {
            var total = 0
            DownloadLog.beginRun("Download from the app" + (vine ? ", with Vines" : ""), settings: settings)
            let log = DownloadLog.tee { line in Task { @MainActor in self.appendLog(line) } }
            if vine {
                statuses[Vine.feedID] = .downloading
                let began = Date()
                let result = await Vine.download(keep: settings.vineBatchSize, settings: settings, runner: runner, log: log)
                DownloadLog.result(Vine.feedID, result, seconds: Date().timeIntervalSince(began))
                RunState.record(result, for: Vine.feedID)
                total += result.newVideos
                statuses[Vine.feedID] = .idle
                downloadUnitsDone += 1
                reloadLibrary()
            }
            let onVideo: ((String, PendingVideo.State) -> Void)? = only == nil ? nil : { id, state in
                Task { @MainActor in self.longPick?.states[id] = state }
            }
            await DownloadEngine.downloadAll(creators, forms: forms, settings: settings, runner: runner, log: log,
                                             only: only, heights: heights, onVideo: onVideo, onStart: { @MainActor creator in
                self.statuses[creator.id] = .downloading
            }, onFinish: { @MainActor creator, result in
                total += result.newVideos
                self.statuses[creator.id] = .idle
                if let picked = only?[creator.id], !runner.isCancelled { self.longPick?.finish(picked) }
                self.downloadUnitsDone += 1
                self.reloadLibrary()
            })
            if !runner.isCancelled {
                let now = Date()
                RunState.update { state in
                    state.lastRun = now
                    if forms.contains(.short) && creators.contains(where: \.downloadsShorts) { state.lastShortRun = now }
                    if forms.contains(.long) && creators.contains(where: \.downloadsLongForm) { state.lastLongRun = now }
                }
            }
            for c in creators { statuses[c.id] = .idle }
            statuses[Vine.feedID] = nil
            lock.release()
            self.runner = nil
            isDownloading = false
            downloadingForms = []
            downloadingVine = false
            downloadMessage = runner.isCancelled ? "Stopped." : "Done — \(total) new video\(total == 1 ? "" : "s")."
            if only != nil {
                // Minimized, the picker is done with; open, it shows how it went until it's closed.
                if longPick?.shown == false { longPick = nil } else { longPick?.finished = true }
            }
            reloadLibrary()
        }
    }

    // MARK: Picking long videos

    /// Opens the long-video picker on every new long video `creators` (or everyone with long videos) have, to pick
    /// which to download. While its download runs, opens it again.
    func pickLongDownload(_ creators: [Creator]? = nil) {
        if longPick != nil {
            longPick?.shown = true
            return
        }
        let creators = (creators ?? config.creators).filter(\.downloadsLongForm)
        guard !isDownloading, !creators.isEmpty else { return }
        let runner = ProcessRunner()
        longPick = LongPick(runner: runner)
        let settings = config.settings
        Task {
            DownloadLog.beginRun("Listing new long videos to pick from", settings: settings)
            let log = DownloadLog.tee { line in Task { @MainActor in self.appendLog(line) } }
            await DownloadEngine.pendingLong(creators, settings: settings, runner: runner, log: log) { @MainActor creator, result in
                guard self.longPick?.runner === runner else { return }
                let name = self.library(for: creator.id, form: .long)?.displayName ?? creator.username
                self.longPick?.add(result.pending, error: result.error.map { "\(name): \($0)" })
            }
            if longPick?.runner === runner { longPick?.loading = false }
        }
    }

    /// Opens the picker on the long videos suggested on the YouTube home feed. Each goes to its creator's long videos
    /// when that channel is followed with long videos on, or else to the Suggestions playlist. Videos already
    /// downloaded, watched or skipped are left out. While its download runs, opens it again.
    func pickSuggested() {
        if longPick != nil {
            longPick?.shown = true
            return
        }
        guard !isDownloading else { return }
        let runner = ProcessRunner()
        longPick = LongPick(runner: runner, kind: .suggested)
        let settings = config.settings
        // Followed channels by handle and by "UC…" id (channel_id.txt, or a creator added by id).
        var following: [String: Creator] = [:]
        for creator in config.creators where creator.platform == .youtube && !creator.playlist && creator.downloadsLongForm {
            following[creator.username.lowercased()] = creator
            if let id = try? String(contentsOf: Library.folder(for: creator.id, settings: settings)
                .appendingPathComponent("channel_id.txt"), encoding: .utf8) {
                following[id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = creator
            }
        }
        let have = Set((libraries + longLibraries).flatMap(\.videos).map(\.id))
        Task {
            DownloadLog.beginRun("Listing suggested videos to pick from", settings: settings)
            let log = DownloadLog.tee { line in Task { @MainActor in self.appendLog(line) } }
            let (found, error) = await DownloadEngine.suggestions(settings: settings, runner: runner, log: log)
            guard longPick?.runner === runner else { return }
            var archived: [String: Set<String>] = [:]
            func isArchived(_ id: String, in creator: Creator) -> Bool {
                if archived[creator.id] == nil {
                    let file = Library.folder(for: creator, form: .long, settings: settings).appendingPathComponent("archive.txt")
                    archived[creator.id] = Set(((try? String(contentsOf: file, encoding: .utf8)) ?? "")
                        .split(separator: "\n").compactMap { $0.split(separator: " ").last.map(String.init) })
                }
                return archived[creator.id]!.contains(id)
            }
            let pending: [PendingVideo] = found.compactMap { entry in
                let creator = entry.handle.flatMap { following[$0] }
                    ?? entry.channel_id.flatMap { following[$0.lowercased()] } ?? .suggestions
                guard !have.contains(entry.id), !played.contains(entry.id), !isArchived(entry.id, in: creator) else { return nil }
                return PendingVideo(id: entry.id, creatorID: creator.id, title: entry.title,
                                    date: entry.timestamp.map(Date.init(timeIntervalSince1970:)),
                                    channel: entry.channel, duration: entry.duration.map { Int($0) })
            }
            longPick?.add(pending, error: error == "Cancelled" ? nil : error)
            longPick?.loading = false
            #if DEBUG
            // CURATED_TEST_START_PICK=<height> downloads everything listed at that resolution, for tests.
            if let height = ProcessInfo.processInfo.environment["CURATED_TEST_START_PICK"].flatMap(Int.init) {
                for video in pending { longPick?.setHeight(height, for: video.id, creatorHeight: nil) }
                startPickedDownload()
            }
            #endif
        }
    }

    /// Opens the picker on `creator`'s long videos not downloaded yet, whatever their Keep window, with none selected.
    /// Their whole list is read once, here; Load More only reveals more of it. Leaves out what's downloaded, watched,
    /// skipped or deleted. Long videos are never deleted for their age, so an old one picked here stays until it's
    /// watched and deleted, and until it's watched it comes first (`handPickedFirst`). While a download runs, opens that.
    func pickOlderLong(_ creator: Creator) {
        if longPick != nil {
            longPick?.shown = true
            return
        }
        guard !isDownloading, creator.canPickOlderLong else { return }
        let runner = ProcessRunner()
        var pick = LongPick(runner: runner, kind: .older)
        pick.creatorName = library(for: creator.id, form: .long)?.displayName ?? "@\(creator.username)"
        longPick = pick
        let settings = config.settings
        let excluding = played.union((libraries + longLibraries).flatMap(\.videos).map(\.id))
        Task {
            DownloadLog.beginRun("Listing \(pick.creatorName ?? creator.username)'s long videos to pick from", settings: settings)
            let log = DownloadLog.tee { line in Task { @MainActor in self.appendLog(line) } }
            let error = await DownloadEngine.olderLong(creator, excluding: excluding, settings: settings,
                                                       runner: runner, log: log) { @MainActor found in
                guard self.longPick?.runner === runner, self.longPick?.started == false else { return }
                self.longPick?.add(found, error: nil, selecting: false)
            }
            // Closed, or its download started, which stops the listing.
            guard longPick?.runner === runner, longPick?.started == false else { return }
            longPick?.add([], error: error, selecting: false)
            longPick?.loading = false
            #if DEBUG
            // CURATED_TEST_START_PICK=<height> downloads what's listed at that resolution, and CURATED_TEST_LOAD_MORE=1
            // presses Load More once, for tests.
            if let height = ProcessInfo.processInfo.environment["CURATED_TEST_START_PICK"].flatMap(Int.init) {
                longPick?.selectAll()
                for video in longPick?.videos ?? [] { longPick?.setHeight(height, for: video.id, creatorHeight: nil) }
                startPickedDownload()
            } else if ProcessInfo.processInfo.environment["CURATED_TEST_LOAD_MORE"] != nil {
                longPick?.loadMore()
            }
            #endif
        }
    }

    /// Marked watched, and kept from ever downloading.
    func applySkipped(_ ids: [String], for creator: Creator) {
        guard !ids.isEmpty else { return }
        mark(ids, played: true)
        let folder = Library.folder(for: creator, form: .long, settings: settings)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Library.archive(ids, in: folder)
    }

    /// Picked by hand from a creator's older videos, so they come first until watched, however old they are.
    func markHandPicked(_ ids: [String]) {
        let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        var marks = handPicked
        for id in ids { marks[id] = now }
        handPicked = marks
    }

    /// Marks the skipped videos watched (and keeps them from ever downloading), then downloads the picked ones. With
    /// nothing picked, just closes the picker.
    func startPickedDownload() {
        guard var pick = longPick, !pick.loading || pick.kind == .older, !pick.started else { return }
        // Picking needn't wait for Load More: this stops the listing.
        if pick.loading {
            pick.runner.cancel()
            pick.loading = false
        }
        let skipped = pick.videos.filter { pick.skipped.contains($0.id) }
        let creators = config.creators + [.suggestions]
        for (creatorID, videos) in Dictionary(grouping: skipped, by: \.creatorID) {
            guard let creator = creators.first(where: { $0.id == creatorID }) else { continue }
            applySkipped(videos.map(\.id), for: creator)
        }
        // A video in both a creator's list and a playlist downloads to both, as it would without the picker.
        let picked = pick.videos.filter { pick.picked.contains($0.id) }
        let only = Dictionary(grouping: picked, by: \.creatorID).mapValues { Set($0.map(\.id)) }
        let downloading = creators.filter { only[$0.id] != nil }
        guard !downloading.isEmpty, !isDownloading else {
            longPick = nil
            reloadLibrary()
            return
        }
        if pick.kind == .older { markHandPicked(picked.map(\.id)) }
        if let ids = only[Creator.suggestions.id] { addToSuggestions(picked.map(\.id).filter(ids.contains)) }
        pick.started = true
        pick.states = Dictionary(picked.map { ($0.id, .queued) }) { first, _ in first }
        longPick = pick
        download(downloading, forms: [.long], only: only, heights: pick.heights)
    }

    /// Gets the Suggestions playlist's folder ready for `ids`: its name, and the ids at the front of its order, so
    /// the newest picks come first.
    private func addToSuggestions(_ ids: [String]) {
        let folder = Library.folder(for: Creator.suggestions.id, settings: settings)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Library.saveProfile(nickname: "Suggestions", in: folder)
        let old = (try? Data(contentsOf: folder.appendingPathComponent("order.json")))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        Library.savePlaylistOrder(ids + old.filter { !ids.contains($0) }, in: folder)
    }

    /// Closing the picker: stops its listing, or minimizes it to the download bar while its download runs.
    func closeLongPick() {
        guard let pick = longPick else { return }
        if pick.started && !pick.finished {
            longPick?.shown = false
        } else {
            pick.runner.cancel()
            longPick = nil
        }
    }

    func cancelDownloads() {
        runner?.cancel()
    }

    private func appendLog(_ line: String) {
        lastActivity = line
        let stamp = Date().formatted(date: .omitted, time: .standard)
        log.append("\(stamp)  \(line)")
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}

enum PlaybackMode: Hashable {
    case creator(String)
    /// A nil category means all creators. `picked`, from holding Automix or Top (or Option-clicking it), limits it to
    /// some of the sidebar's cards instead: category ids (`uuidString`), `otherCard` and `vineCard`.
    case automix(UUID?, picked: Set<String>? = nil)
    /// Long videos: every unplayed one, newest first.
    case latest(UUID?)
    case top(UUID?, picked: Set<String>? = nil)
    case watchLater
    case bookmarks
    /// Videos exported for an iPod.
    case ipod
    /// Every Vine, round-robin across their authors.
    case vineAutomix

    /// Top 15 (5 per category) for short videos; Top 5 (3 per category) for long ones.
    static func topCount(_ category: UUID?, form: VideoForm = .short) -> Int {
        switch form {
        case .short: category == nil ? 15 : 5
        case .long: category == nil ? 5 : 3
        }
    }

    var isAutomix: Bool {
        switch self {
        case .automix, .vineAutomix: true
        default: false
        }
    }
    /// A generated mix that runs on until it's out of unplayed videos.
    var isOpenMix: Bool {
        switch self {
        case .automix, .vineAutomix, .latest: true
        default: false
        }
    }
    func topLimit(_ form: VideoForm) -> Int? { if case .top(let c, _) = self { PlaybackMode.topCount(c, form: form) } else { nil } }
}

/// The sidebar's "Other Creators" and Vine cards, alongside the category ids, in a mix's `picked` cards.
let otherCard = "other"
let vineCard = "vine"
/// Long videos' Playlists card, which is never in a mix, in the playback rules.
let playlistCard = "playlists"

@MainActor @Observable
final class Playback {
    let player = AVPlayer()
    private let model: AppModel
    private(set) var queue: [Video] = []
    private(set) var index: Int?
    private(set) var mode: PlaybackMode?
    /// Whether the loaded queue is short or long videos.
    private(set) var form = VideoForm.short
    /// Counts videos loaded from another device, so the window can select where they live.
    private(set) var syncedVideoLoads = 0
    /// Counts Close Video, so the window can hold the mix back as it does at launch.
    private(set) var closedVideos = 0
    private(set) var finished = false
    private(set) var isPlaying = false
    /// Set when the queue was cut to a time budget (Automix "Time Limit").
    private(set) var timeLimitMinutes: Int?
    /// Playback position in the current video, updated a few times a second.
    private(set) var currentTime: TimeInterval = 0
    /// The chosen speed; stays the same from video to video.
    private(set) var speed: Float = 1
    /// The current video's category always plays at 1× (see `PlaybackRules`), so the chosen speed waits for the next one.
    private(set) var speedLocked = false
    /// The speed the current video plays at.
    var shownSpeed: Float { speedLocked ? 1 : speed }
    /// The playing video's width over its height, kept while the next one loads; nil until one has loaded.
    private(set) var videoAspect: CGFloat?
    /// Long videos: start the next one when a video ends. Off by default, since long videos are mostly picked one at
    /// a time; with it off the player stops at the end and offers the next one.
    var autoplayLong = UserDefaults.standard.bool(forKey: "longAutoplay") {
        didSet { UserDefaults.standard.set(autoplayLong, forKey: "longAutoplay") }
    }
    /// Short videos: go on to the next one when a video ends (on by default), or play it again.
    var autoplayShort = UserDefaults.standard.object(forKey: "shortAutoplay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoplayShort, forKey: "shortAutoplay") }
    }
    /// A long video ended with autoplay off, and there's another one to play.
    private(set) var awaitingNext = false
    /// Long videos' clear mode: nothing over the video until it's clicked (see `PlayerControls`). Kept until turned off.
    var clearMode = false

    static let speeds: [Float] = [1, 1.5, 2]

    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var sizeObservation: NSKeyValueObservation?
    /// Waits for a resumed long video to be ready, then seeks to where it was left off.
    @ObservationIgnored private var resumeObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastSavedPosition: TimeInterval = 0
    /// While the player is moving to a position from a phone, its time is still the old one, which mustn't be saved.
    @ObservationIgnored private var movingToSyncedPosition = false
    @ObservationIgnored private var quitObserver: NSObjectProtocol?
    /// Set by Reset Everything, so nothing more is saved into the data folder it just moved to the Trash.
    @ObservationIgnored var frozen = false

    var current: Video? { index.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var hasPrevious: Bool { (index ?? 0) > 0 }

    init(model: AppModel) {
        self.model = model
        model.onPositionsMerged = { [weak self] ids in self?.positionsMerged(ids) }
        model.onNowPlayingMerged = { [weak self] in _ = self?.loadSyncedVideo() }
        model.onPlaybackRulesChanged = { [weak self] in self?.applySpeed() }
        #if DEBUG
        if let rate = ProcessInfo.processInfo.environment["CURATED_TEST_SPEED"].flatMap(Float.init) {
            speed = rate
            // The launch mix waits for a click; this doesn't.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if let self, self.current == nil, !self.queue.isEmpty { self.play(at: 0) }
            }
        }
        #endif
        statusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            DispatchQueue.main.async {
                self?.isPlaying = playing
                if !playing { self?.savePosition() }
            }
        }
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            let item = player.currentItem
            DispatchQueue.main.async {
                self?.sizeObservation = item?.observe(\.presentationSize, options: [.initial, .new]) { item, _ in
                    let size = item.presentationSize
                    guard size.width > 0, size.height > 0 else { return }
                    DispatchQueue.main.async {
                        let aspect = size.width / size.height
                        if self?.videoAspect != aspect { self?.videoAspect = aspect }
                    }
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.videoEnded()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, time.seconds.isFinite else { return }
                self.currentTime = time.seconds
                if abs(time.seconds - self.lastSavedPosition) >= 5 { self.savePosition() }
            }
        }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.savePosition() }
        }
    }

    /// Remembers how far into the current long video playback is. Only saves positions worth resuming from, and
    /// forgets one once the video is nearly over, so a finished video starts from the top next time.
    func savePosition() {
        guard !frozen, let video = current, video.form == .long, !model.isPlayed(video), resumeObservation == nil,
              !movingToSyncedPosition else { return }
        let length = model.duration(of: video) ?? player.currentItem?.duration.seconds ?? 0
        let time = currentTime
        // Sitting still isn't news: re-saving an old place with a new date would beat a phone's newer one.
        guard abs(time - lastSavedPosition) >= 1 else { return }
        lastSavedPosition = time
        if length.isFinite && length > 0 && time > length - 20 {
            model.setResumePosition(nil, for: video)
        } else if time > 10 {
            model.setResumePosition(time, for: video)
        }
    }

    /// A phone moved on in a video that's loaded here: a paused player follows it. One that's playing carries on, and
    /// its next save wins.
    private func positionsMerged(_ ids: Set<String>) {
        guard let video = current, video.form == .long, ids.contains(video.id), !finished, resumeObservation == nil,
              player.timeControlStatus == .paused else { return }
        guard let seconds = model.resumePosition(of: video) else {
            lastSavedPosition = currentTime
            return
        }
        movingToSyncedPosition = true
        currentTime = seconds
        lastSavedPosition = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.movingToSyncedPosition = false }
        }
    }

    /// What's left of the current video, in seconds.
    private var currentRemaining: TimeInterval {
        guard let video = current, !finished else { return 0 }
        let length = model.duration(of: video) ?? player.currentItem?.duration.seconds ?? 0
        return length.isFinite ? max(0, length - currentTime) : 0
    }

    /// Queued videos that haven't been started yet.
    var unwatched: [Video] {
        queue.filter { $0.id != current?.id && !model.isPlayed($0) }
    }

    /// The rest of the current video plus every unwatched video in the queue.
    var unwatchedSecondsLeft: TimeInterval {
        currentRemaining + model.totalDuration(unwatched)
    }

    /// How long until the queue runs out on its own: the rest of the current video plus
    /// the unplayed videos after it (the ones `next()` will reach).
    var secondsUntilEnd: TimeInterval {
        guard let index else { return 0 }
        let upcoming = queue[(index + 1)...].filter { !model.isPlayed($0) }
        return currentRemaining + model.totalDuration(upcoming)
    }

    /// Whether this queue is the one loaded.
    func isLoaded(_ mode: PlaybackMode, form: VideoForm) -> Bool { self.mode == mode && self.form == form }

    /// Loads `queue` and plays from `index`; with `autoplay` off, just loads it, so it's listed with nothing playing
    /// until a video is picked.
    func start(_ queue: [Video], at index: Int = 0, mode: PlaybackMode, form: VideoForm = .short,
               timeLimitMinutes: Int? = nil, autoplay: Bool = true) {
        // Save the old video's place while `index` still points into the old queue.
        savePosition()
        self.index = nil
        self.queue = queue
        self.mode = mode
        self.form = form
        self.timeLimitMinutes = timeLimitMinutes
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        guard autoplay else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            finished = false
            awaitingNext = false
            return
        }
        play(at: index)
    }

    /// Swaps in a new queue, keeping the current video playing at the top of it.
    func continueWith(_ queue: [Video], mode: PlaybackMode) {
        guard let current, !finished else {
            start(queue, mode: mode)
            return
        }
        self.queue = [current] + queue.filter { $0.id != current.id }
        self.mode = mode
        timeLimitMinutes = nil
        index = 0
    }

    func play(at i: Int, autoplay: Bool = true) {
        guard queue.indices.contains(i) else { return }
        savePosition()
        if autoplay, queue[i].form == .long { model.setNowPlaying(queue[i]) }
        index = i
        finished = false
        awaitingNext = false
        currentTime = 0
        lastSavedPosition = 0
        resumeObservation = nil
        let video = queue[i]
        let item = AVPlayerItem(url: video.url)
        player.replaceCurrentItem(with: item)
        applySpeed()
        guard video.form == .long, let saved = model.resumePosition(of: video) else {
            if autoplay { player.play() } else { player.pause() }
            return
        }
        let resume = max(0, saved - TimeInterval(model.settings.playbackRules.resumeRewindSeconds))
        // Pick up where it was left off: seek once the item is ready, then play.
        resumeObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status != .unknown else { return }
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item, self.resumeObservation != nil else { return }
                self.resumeObservation = nil
                if item.status == .readyToPlay {
                    self.seek(to: resume)
                    self.lastSavedPosition = resume
                }
                if autoplay { self.player.play() } else { self.player.pause() }
            }
        }
    }

    /// Loads the long video last playing on any device, paused where it was left, while the long sidebar is showing.
    /// Never replaces a long video that's playing; a short one that's playing only when `switching` to the long
    /// sidebar. Returns whether that video is now the loaded one.
    @discardableResult
    func loadSyncedVideo(switching: Bool = false) -> Bool {
        guard switching || model.form == .long, let id = model.nowPlayingMark.id else { return false }
        if current?.id == id { return true }
        guard let library = model.longLibraries.first(where: { $0.videos.contains { $0.id == id } }),
              let at = library.videos.firstIndex(where: { $0.id == id }), !model.isPlayed(library.videos[at]) else { return false }
        if let current, isPlaying, !finished, current.form == .long || !switching { return false }
        savePosition()
        index = nil
        queue = library.videos
        mode = .creator(library.id)
        form = .long
        timeLimitMinutes = nil
        play(at: at, autoplay: false)
        syncedVideoLoads += 1
        return true
    }

    /// A video played to the end. A short one with autoplay off is marked watched and plays again. A long one with
    /// autoplay off is marked watched and the player stops there, offering the next one (or, with none left, finishes).
    private func videoEnded() {
        if let index, queue[index].form == .short, !autoplayShort {
            model.setPlayed(queue[index], true)
            seek(to: 0)
            player.play()
            return
        }
        guard let index, queue[index].form == .long, !autoplayLong else { return next() }
        model.setPlayed(queue[index], true)
        if nextIndex != nil { awaitingNext = true } else { finished = true }
    }

    /// Where `next()` would go: the next unplayed video (any next one, for Bookmarks). In a creator's tab this wraps
    /// around to newer videos above the current one; the mixes only move forward.
    private var nextIndex: Int? {
        guard let index else { return nil }
        var candidates = Array(queue.indices[(index + 1)...])
        if case .creator = mode { candidates += queue.indices[..<index] }
        // Bookmarks are for rewatching, so they play straight through, watched or not.
        return mode == .bookmarks || mode == .ipod ? candidates.first : candidates.first { !model.isPlayed(queue[$0]) }
    }

    /// The video after this one, for the Up Next card.
    var upNext: Video? { nextIndex.map { queue[$0] } }

    /// The video `previous()` would go back to, shown sliding down on the tape.
    var previousVideo: Video? {
        guard let index, index > 0, queue.indices.contains(index - 1) else { return nil }
        return queue[index - 1]
    }

    /// From the Up Next card.
    func playNext() {
        if let nextIndex { play(at: nextIndex) }
    }

    /// From the Up Next card: the video that just ended, from the start.
    func replay() {
        awaitingNext = false
        seek(to: 0)
        player.play()
    }

    /// Advances to the next unplayed video. In a creator's tab this wraps around to newer videos
    /// above the current one; Automix only moves forward.
    /// Called when a video plays to the end or is skipped, which is what counts as watching it.
    func next() {
        advance(markingPlayed: true)
    }

    /// Saves the current video to Watch Later and moves on without marking it watched.
    func toggleBookmark() {
        guard let current else { return }
        model.setBookmarked(current, !model.isBookmarked(current))
    }

    /// Saves the current video to Watch Later and moves on without marking it watched; if it's already saved, takes
    /// it off Watch Later and keeps playing it.
    func toggleWatchLater() {
        guard let current else { return }
        if model.isSavedForLater(current) {
            model.setWatchLater(current, false)
        } else if !finished {
            model.setWatchLater(current, true)
            advance(markingPlayed: false)
        }
    }

    private func advance(markingPlayed: Bool) {
        guard let index else { return }
        if markingPlayed { model.setPlayed(queue[index], true) }
        if let i = nextIndex {
            play(at: i)
        } else {
            player.pause()
            finished = true
            awaitingNext = false
        }
    }

    func previous() {
        guard let index, index > 0 else { return }
        play(at: index - 1)
    }

    func seek(to seconds: TimeInterval) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 1× → 1.5× → 2× → 1×.
    func cycleSpeed() {
        setSpeed(Self.speeds[((Self.speeds.firstIndex(of: speed) ?? 0) + 1) % Self.speeds.count])
    }

    func setSpeed(_ speed: Float) {
        self.speed = speed
        applySpeed()
    }

    /// Plays at the chosen speed, or 1× if the current video's category stays there.
    private func applySpeed() {
        speedLocked = current.map { model.playsAtNormalSpeed($0, from: mode) } ?? false
        // play() starts at the default rate, so later videos keep the speed too.
        player.defaultRate = shownSpeed
        if player.timeControlStatus != .paused { player.rate = shownSpeed }
        #if DEBUG
        // CURATED_TEST_SPEED=<rate> starts at that speed and prints what each video really plays at, for tests.
        if ProcessInfo.processInfo.environment["CURATED_TEST_SPEED"] != nil, let id = current?.id {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                print("speed test: \(id) locked \(self.speedLocked) chosen \(self.speed) playing at \(self.player.rate)")
                fflush(stdout)
            }
        }
        #endif
    }

    func togglePlayPause() {
        if player.timeControlStatus == .paused {
            if let current, current.form == .long { model.setNowPlaying(current) }
            player.play()
        } else {
            player.pause()
        }
    }

    /// Stops the video and goes back to what the app shows at launch: the logo, with the queue still listed to pick
    /// from. A long video's place is kept, and it's no longer offered to other devices.
    func closeVideo() {
        savePosition()
        if let current, current.form == .long { model.clearNowPlaying(current) }
        awaitingNext = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        resumeObservation = nil
        index = nil
        applySpeed()
        finished = false
        timeLimitMinutes = nil
        closedVideos += 1
    }

    func stop() {
        savePosition()
        if let current, current.form == .long { model.clearNowPlaying(current) }
        awaitingNext = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        index = nil
        queue = []
        mode = nil
        applySpeed()
        timeLimitMinutes = nil
        finished = false
    }
}
