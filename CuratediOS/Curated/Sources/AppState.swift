import BackgroundTasks
import Foundation
import Observation
import UIKit

/// The library on this phone, watched history, and syncing with the Mac.
@MainActor @Observable
final class AppState {
    static let backgroundSyncID = "local.curated.ios.sync"

    let store = Store()
    private(set) var manifest: Manifest?
    /// Short videos, by creator (playlists aren't here).
    private(set) var libraries: [CreatorLibrary] = []
    /// Long videos, by creator and playlist.
    private(set) var longLibraries: [CreatorLibrary] = []
    /// Vine authors with Vines on this device. Short videos, kept apart from `libraries` (no category, no Top list).
    private(set) var vineLibraries: [CreatorLibrary] = []
    /// Which Home is showing: short or long videos. Always short at launch, as on the Mac.
    var form = VideoForm.short {
        didSet { if form == .long && oldValue != .long { onSwitchedToLong?() } }
    }
    /// Called as Home switches to long videos, before any view hears of it.
    @ObservationIgnored var onSwitchedToLong: (() -> Void)?
    /// What Sync, automatic sync and pull to refresh download: short videos, long ones, or both.
    var syncForms = SyncForms(rawValue: UserDefaults.standard.string(forKey: "syncForms") ?? "") ?? .short {
        didSet { UserDefaults.standard.set(syncForms.rawValue, forKey: "syncForms") }
    }
    /// Long videos: start the next one when a video ends. Off by default, as on the Mac.
    var autoplayLong = UserDefaults.standard.bool(forKey: "autoplayLong") {
        didSet { UserDefaults.standard.set(autoplayLong, forKey: "autoplayLong") }
    }
    /// Short videos: go on to the next one when a video ends (on by default), or play it again.
    var autoplayShort = UserDefaults.standard.object(forKey: "autoplayShort") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoplayShort, forKey: "autoplayShort") }
    }
    /// A lighter aurora, and no blurred fill behind short videos, to use less battery. Off by default.
    var lowPower = UserDefaults.standard.bool(forKey: "lowPower") {
        didSet { UserDefaults.standard.set(lowPower, forKey: "lowPower") }
    }
    /// Where each long video was left off, including ones cleared (for syncing with the Mac).
    private(set) var positionMarks: [String: PositionMark] = [:]
    /// Called with the videos whose position just changed because of the Mac, so a paused player can move there.
    @ObservationIgnored var onPositionsMerged: ((Set<String>) -> Void)?
    /// The long video last playing on any device.
    private(set) var nowPlayingMark = NowPlayingMark.none
    /// A newer now playing mark just arrived from the Mac.
    @ObservationIgnored var onNowPlayingMerged: (() -> Void)?
    /// Which categories Automix leaves out or keep to 1×, and the time limit. Shared with the Mac.
    private(set) var playbackRules = PlaybackRules()
    /// The rules changed, here or from the Mac, so the playing video can change speed.
    @ObservationIgnored var onPlaybackRulesChanged: (() -> Void)?
    /// A position changed here since the Mac last heard.
    @ObservationIgnored private var positionsChanged = false
    /// Old avatars are being replaced, behind a sync.
    @ObservationIgnored private var refreshingAvatars = false
    @ObservationIgnored private var positionsSend: Task<Void, Never>?
    @ObservationIgnored private var exchangingPositions = false
    private var marks: [String: PlayedMark]
    private(set) var played: Set<String>
    /// Watch Later history, including removals (for syncing with the Mac).
    private(set) var watchLaterMarks: [String: WatchLaterMark]
    /// Bookmarks, including removals (for syncing with the Mac).
    private(set) var bookmarkMarks: [String: WatchLaterMark]
    private(set) var pairing: Pairing?
    var appearance = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    /// What's behind Home, and the palette each style uses. Kept on this device only.
    var backgroundStyle = BackgroundStyle(rawValue: UserDefaults.standard.string(forKey: "background") ?? "") ?? .aurora {
        didSet { UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "background") }
    }
    var auroraPalette = UserDefaults.standard.string(forKey: "auroraPalette") ?? AuroraPalette.curated.id {
        didSet { UserDefaults.standard.set(auroraPalette, forKey: "auroraPalette") }
    }
    var holidayPalette = UserDefaults.standard.string(forKey: "holidayPalette") ?? AuroraPalette.holiday[0].id {
        didSet { UserDefaults.standard.set(holidayPalette, forKey: "holidayPalette") }
    }
    /// Home's wordmark becomes the season's holiday one (`Holiday.current`).
    var holidayWordmarks = UserDefaults.standard.bool(forKey: "holidayWordmarks") {
        didSet { UserDefaults.standard.set(holidayWordmarks, forKey: "holidayWordmarks") }
    }

    /// The aurora's palette for the chosen style.
    var palette: AuroraPalette {
        AuroraPalette.named(backgroundStyle == .holiday ? holidayPalette : auroraPalette, in: backgroundStyle.palettes)
    }

    /// The current Home's wordmark: the season's holiday one while those are on, otherwise the usual logo (the long
    /// Home has its own, with landscape cards).
    var logoName: String {
        let long = form == .long
        return (holidayWordmarks ? Holiday.current()?.imageName(long: long) : nil) ?? (long ? "LogoLong" : "Logo")
    }

    private(set) var isSyncing = false
    private(set) var syncStep = ""
    /// 0–1 while downloading videos; nil while there's nothing to measure.
    private(set) var syncProgress: Double?
    private(set) var lastSyncMessage: String? = UserDefaults.standard.string(forKey: "lastSyncMessage")
    private(set) var lastSyncAt: Date? = UserDefaults.standard.object(forKey: "lastSyncAt") as? Date
    private(set) var isRequestingDownload = false
    /// Why the Mac didn't start a Force Download, or couldn't be asked, until Settings closes.
    private(set) var forceDownloadMessage: String?
    /// The Mac's download while Settings is following it; nil when nothing's downloading.
    private(set) var macDownload: MacDownloadProgress?
    /// A download seen on the Mac finished, and no sync has fetched it yet: Settings shows a checkmark.
    private(set) var macDownloadFinished = UserDefaults.standard.bool(forKey: "macDownloadFinished") {
        didSet { UserDefaults.standard.set(macDownloadFinished, forKey: "macDownloadFinished") }
    }
    /// The Mac's last download time when one was seen running (distantPast if none): a newer time afterwards means it
    /// finished, and the same one that it was stopped. Saved, since it can finish with this app closed.
    private var macDownloadBaseline = UserDefaults.standard.object(forKey: "macDownloadBaseline") as? Date {
        didSet { UserDefaults.standard.set(macDownloadBaseline, forKey: "macDownloadBaseline") }
    }
    private var macDownloadWatch: Task<Void, Never>?
    /// Videos asked for from the Mac (Older Videos) and not fetched yet. The Mac's download is followed until they are,
    /// wherever you are in the app, and a sync brings them whichever kinds it's syncing. Saved, since it can finish with
    /// this app closed.
    private(set) var requestedVideoIDs = Set(UserDefaults.standard.stringArray(forKey: "requestedVideoIDs") ?? []) {
        didSet { UserDefaults.standard.set(Array(requestedVideoIDs), forKey: "requestedVideoIDs") }
    }
    private var followedDownloadAt: Date?
    /// When the Mac last finished a download: from the last sync, or newer while following its downloads.
    var lastMacDownloadAt: Date? { [manifest?.lastDownloadAt, followedDownloadAt].compactMap { $0 }.max() }
    var autoSync: Bool = UserDefaults.standard.bool(forKey: "autoSync") {
        didSet {
            UserDefaults.standard.set(autoSync, forKey: "autoSync")
            scheduleBackgroundSync()
        }
    }

    /// Home-screen cards the user collapsed, by category id (or "other"). Kept on the phone only.
    private(set) var collapsedCards = Set(UserDefaults.standard.stringArray(forKey: "collapsedCards") ?? [])

    /// Called when a sync removes or adds videos, so the playing queue can be rebuilt.
    @ObservationIgnored var onLibraryChanged: (() -> Void)?

    init() {
        let loaded = store.loadPlayed()
        marks = loaded
        played = Set(loaded.filter(\.value.played).keys)
        watchLaterMarks = store.loadWatchLater()
        bookmarkMarks = store.loadBookmarks()
        pairing = store.loadPairing()
        manifest = store.loadManifest()
        positionMarks = store.loadPositions()
        nowPlayingMark = store.loadNowPlaying()
        playbackRules = store.loadPlaybackRules()
        rebuildLibraries()
    }

    var timeLimitMinutes: Int { playbackRules.timeLimitMinutes ?? manifest?.timeLimitMinutes ?? 10 }
    var categories: [Category] { manifest?.categories ?? [] }

    func category(_ id: String?) -> Category? { id.flatMap { id in categories.first { $0.id == id } } }
    func library(_ username: String, form: VideoForm = .short) -> CreatorLibrary? {
        (form == .short ? libraries + vineLibraries : longLibraries).first { $0.id == username }
    }

    /// Long-video creators and playlists, or only those in `category`.
    func longLibraries(in category: String?) -> [CreatorLibrary] {
        guard let category else { return longLibraries }
        return longLibraries.filter { $0.creator.category == category }
    }

    /// A form's libraries, or only those in `category`.
    func libraries(in category: String?, form: VideoForm) -> [CreatorLibrary] {
        form == .short ? libraries(in: category) : longLibraries(in: category)
    }

    /// What the mixes draw from: playlists are watched on their own, in order, so they stay out.
    func mixLibraries(in category: String?, form: VideoForm) -> [CreatorLibrary] {
        libraries(in: category, form: form).filter { !$0.creator.isPlaylist }
    }

    /// What Automix draws from: the short creators, plus every Vine as one more creator in the main Automix and the
    /// categories the Mac names (a Funny category's). With no `category` it's the main Automix, which leaves out the
    /// cards turned off in Settings.
    func automixLibraries(in category: String?) -> [CreatorLibrary] {
        let off = category == nil ? playbackRules.short.automixOff : []
        let mix = libraries(in: category).filter { !off.contains(cardKey($0.creator)) }
        guard !vineLibraries.isEmpty, !off.contains(vineCard), category.map({ manifest?.vineCategories?.contains($0) == true }) ?? true else { return mix }
        return mix + [allVines]
    }

    /// What long videos' Automix draws from, by the same rule.
    func longAutomixLibraries(in category: String?) -> [CreatorLibrary] {
        let off = category == nil ? playbackRules.long.automixOff : []
        return mixLibraries(in: category, form: .long).filter { !off.contains(cardKey($0.creator)) }
    }

    /// Home's card a creator is under, as named in a mix's `picked` and the playback rules.
    func cardKey(_ creator: Creator) -> String {
        if creator.username.hasPrefix(vineKeyPrefix) { return vineCard }
        if creator.isPlaylist { return playlistCard }
        return category(creator.category)?.id ?? otherCard
    }

    /// Whether `video`, played from `mode`, stays at 1×. A long video in a playlist's queue goes by the playlist.
    func playsAtNormalSpeed(_ video: Video, from mode: PlaybackMode?) -> Bool {
        let form: VideoForm = video.isLong ? .long : .short
        var creator = library(video.creator, form: form)?.creator
        if video.isLong, let id = mode?.creatorUsername, let queued = library(id, form: .long)?.creator, queued.isPlaylist {
            creator = queued
        }
        return playbackRules.cards(form).normalSpeed.contains(creator.map(cardKey) ?? otherCard)
    }

    /// Changes the playback rules from here, dated so the Mac takes them.
    func updatePlaybackRules(_ change: (inout PlaybackRules) -> Void) {
        var rules = playbackRules
        change(&rules)
        guard rules != playbackRules else { return }
        rules.at = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        playbackRules = rules
        store.savePlaybackRules(rules)
        onPlaybackRulesChanged?()
        positionsChanged = true
        sendPositionsSoon()
    }

    /// `videos` with the unwatched ones picked by hand first, latest pick first. Once watched they go back to their place.
    func handPickedFirst(_ videos: [Video]) -> [Video] {
        let first = videos.filter { $0.pickedAt != nil && !isPlayed($0) }
        guard !first.isEmpty else { return videos }
        let ids = Set(first.map(\.id))
        return first.sorted { $0.pickedAt! > $1.pickedAt! } + videos.filter { !ids.contains($0.id) }
    }

    /// A client that's reached the Mac, for asking it things. Nil if it can't be reached or this isn't paired.
    func macClient() async -> SyncClient? {
        guard let pairing else { return nil }
        return await connect(pairing)
    }

    /// A long creator's videos as they're shown and queued. A playlist keeps its own order.
    func longVideos(_ library: CreatorLibrary) -> [Video] {
        library.creator.isPlaylist ? library.videos : handPickedFirst(library.videos)
    }

    /// `mixLibraries` for a pick of Home's cards (a mix's `picked`).
    func mixLibraries(picked: Set<String>, form: VideoForm) -> [CreatorLibrary] {
        mixLibraries(in: nil, form: form).filter { picked.contains(category($0.creator.category)?.id ?? otherCard) }
    }

    /// Automix for a pick of Home's cards: Vines only when their card is picked.
    func automixLibraries(picked: Set<String>) -> [CreatorLibrary] {
        let mix = mixLibraries(picked: picked, form: .short)
        guard !vineLibraries.isEmpty, picked.contains(vineCard) else { return mix }
        return mix + [allVines]
    }

    /// Every Vine as one creator, so they take about one creator's share of a mix.
    private var allVines: CreatorLibrary {
        let all = Creator(username: vineKeyPrefix + "classics", nickname: "Vine", days: 1, category: nil, hasAvatar: false,
                          vine: true)
        return CreatorLibrary(creator: all, videos: vineLibraries.flatMap(\.videos).shuffled())
    }

    /// For the long "Other Creators" card. Playlists have their own card.
    var uncategorizedLongLibraries: [CreatorLibrary] {
        longLibraries.filter { category($0.creator.category) == nil && !$0.creator.isPlaylist }
    }

    var playlistLibraries: [CreatorLibrary] { longLibraries.filter(\.creator.isPlaylist) }

    /// A form's videos on the device, once each (a long video can be both a creator's and in a playlist).
    func videos(_ form: VideoForm) -> [Video] {
        var seen: Set<String> = []
        let vines = form == .short ? vineLibraries : []
        return (libraries(in: nil, form: form) + vines).flatMap(\.videos).filter { seen.insert($0.id).inserted }
    }

    /// Libraries in a category, or all of them for nil.
    func libraries(in category: String?) -> [CreatorLibrary] {
        guard let category else { return libraries }
        return libraries.filter { $0.creator.category == category }
    }

    var uncategorizedLibraries: [CreatorLibrary] { libraries.filter { category($0.creator.category) == nil } }
    /// Every video on the device, short and long, once each.
    var allVideos: [Video] { videos(.short) + videos(.long) }

    func isPlayed(_ video: Video) -> Bool { played.contains(video.id) }
    func unplayedCount(_ library: CreatorLibrary) -> Int { library.videos.lazy.filter { !self.played.contains($0.id) }.count }
    func unplayedCount(in category: String?) -> Int { automixLibraries(in: category).reduce(0) { $0 + unplayedCount($1) } }

    // MARK: Resume

    func resumePosition(_ video: Video) -> Double? { positionMarks[video.id]?.seconds }

    func setResumePosition(_ seconds: Double?, for video: Video) {
        guard positionMarks[video.id]?.seconds != seconds else { return }
        positionMarks[video.id] = .now(seconds)
        positionsChanged = true
        store.savePositions(positionMarks)
        if seconds == nil { clearNowPlaying(video) }
    }

    /// `video` started or resumed here.
    func setNowPlaying(_ video: Video) { updateNowPlaying(.now(video.id)) }

    /// `video` was closed or finished, so no other device should offer it.
    func clearNowPlaying(_ video: Video) {
        if nowPlayingMark.id == video.id { updateNowPlaying(.now(nil)) }
    }

    private func updateNowPlaying(_ mark: NowPlayingMark) {
        nowPlayingMark = mark
        positionsChanged = true
        store.saveNowPlaying(mark)
    }

    /// Takes what the Mac sent back for `/positions`: positions first, since a now playing video resumes from them.
    private func merge(_ reply: SyncClient.PositionsReply) {
        mergePositions(reply.positions)
        if let incoming = reply.nowPlaying, incoming.supersedes(nowPlayingMark) {
            nowPlayingMark = incoming
            store.saveNowPlaying(incoming)
            onNowPlayingMerged?()
        }
        // The Mac sends back the newest it knows. Older means this changed while the swap was under way.
        if let incoming = reply.playback, incoming.at >= playbackRules.at, incoming != playbackRules {
            playbackRules = incoming
            store.savePlaybackRules(incoming)
            onPlaybackRulesChanged?()
        }
    }

    /// Keeps the newest position of each video. One saved before the video was last marked watched is cleared, so a
    /// watched video starts from the top on every device.
    private func mergePositions(_ incoming: [String: PositionMark]) {
        var merged = positionMarks
        for (id, mark) in incoming where mark.supersedes(merged[id]) { merged[id] = mark }
        for (id, mark) in merged where mark.seconds != nil {
            if let played = marks[id], played.played, played.at >= mark.at {
                merged[id] = PositionMark(seconds: nil, at: played.at)
            }
        }
        guard merged != positionMarks else { return }
        let changed = Set(merged.keys.filter { merged[$0]?.seconds != positionMarks[$0]?.seconds })
        positionMarks = merged
        store.savePositions(merged)
        onPositionsMerged?(changed)
    }

    /// Tells the Mac about a position changed here, in a moment: pausing and switching videos come in bursts.
    func sendPositionsSoon() {
        guard positionsChanged, pairing != nil else { return }
        positionsSend?.cancel()
        positionsSend = Task {
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Curated positions")
            defer { UIApplication.shared.endBackgroundTask(backgroundTask) }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { await exchangePositions() }
        }
    }

    /// Swaps positions with the Mac, so a video picks up here where another device left it. Small and quick, so it runs
    /// whenever the app opens or leaves a video, whatever the auto-sync setting. If the Mac can't be reached, the next
    /// time will do.
    func exchangePositions() async {
        guard let saved = pairing, !exchangingPositions else { return }
        exchangingPositions = true
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Curated positions")
        defer {
            exchangingPositions = false
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        let client = await connect(saved)
        if !isSyncing { syncStep = "" }
        guard let client else { return }
        positionsChanged = false
        do {
            merge(try await client.positions(positionMarks, nowPlaying: nowPlayingMark, playback: playbackRules))
        } catch {
            positionsChanged = true
        }
    }

    /// How much of a long video has been watched, 0–1, while there's somewhere to resume from.
    func progress(_ video: Video) -> Double? {
        guard let position = positionMarks[video.id]?.seconds, let length = video.duration, length > 0 else { return nil }
        return min(1, position / length)
    }

    // MARK: Watched history

    func setPlayed(_ video: Video, _ value: Bool) { setPlayed([video], value) }

    func setPlayed(_ videos: [Video], _ value: Bool) {
        let changed = videos.filter { played.contains($0.id) != value }
        guard !changed.isEmpty else { return }
        let mark = PlayedMark.now(value)
        for video in changed { marks[video.id] = mark }
        if value { played.formUnion(changed.map(\.id)) } else { played.subtract(changed.map(\.id)) }
        store.savePlayed(marks)
        // A watched video starts from the beginning next time.
        if value, changed.contains(where: { positionMarks[$0.id]?.seconds != nil }) {
            for video in changed where positionMarks[video.id]?.seconds != nil { positionMarks[video.id] = .now(nil) }
            positionsChanged = true
            store.savePositions(positionMarks)
        }
        if value { for video in changed { clearNowPlaying(video) } }
        // Watching a saved video takes it off Watch Later.
        if value { setWatchLater(changed, false) }
    }

    // MARK: Watch Later

    func isSavedForLater(_ video: Video) -> Bool { watchLaterMarks[video.id]?.saved == true }

    func setWatchLater(_ videos: [Video], _ saved: Bool) {
        let changed = videos.filter { isSavedForLater($0) != saved }
        guard !changed.isEmpty else { return }
        let mark = WatchLaterMark.now(saved)
        for video in changed { watchLaterMarks[video.id] = mark }
        store.saveWatchLater(watchLaterMarks)
    }

    /// Saved, unwatched videos of `form` on this device, oldest save first.
    func watchLaterVideos(_ form: VideoForm = .short) -> [Video] {
        videos(form).filter { isSavedForLater($0) && !isPlayed($0) }
            .sorted { (watchLaterMarks[$0.id]?.at ?? .distantPast) < (watchLaterMarks[$1.id]?.at ?? .distantPast) }
    }

    private func mergeWatchLater(_ incoming: [String: WatchLaterMark]) {
        for (id, mark) in incoming where mark.at > (watchLaterMarks[id]?.at ?? .distantPast) {
            watchLaterMarks[id] = mark
        }
        store.saveWatchLater(watchLaterMarks)
    }

    // MARK: Bookmarks

    func isBookmarked(_ video: Video) -> Bool { bookmarkMarks[video.id]?.saved == true }

    var bookmarkedIDs: Set<String> { Set(bookmarkMarks.filter(\.value.saved).keys) }

    func setBookmarked(_ video: Video, _ bookmarked: Bool) {
        guard isBookmarked(video) != bookmarked else { return }
        bookmarkMarks[video.id] = WatchLaterMark.now(bookmarked)
        store.saveBookmarks(bookmarkMarks)
    }

    /// Bookmarked videos of `form` on this device, watched or not, most recently bookmarked first.
    func bookmarkedVideos(_ form: VideoForm = .short) -> [Video] {
        videos(form).filter(isBookmarked)
            .sorted { (bookmarkMarks[$0.id]?.at ?? .distantPast) > (bookmarkMarks[$1.id]?.at ?? .distantPast) }
    }

    private func mergeBookmarks(_ incoming: [String: WatchLaterMark]) {
        for (id, mark) in incoming where mark.at > (bookmarkMarks[id]?.at ?? .distantPast) {
            bookmarkMarks[id] = mark
        }
        store.saveBookmarks(bookmarkMarks)
    }

    /// What Automix will play: unwatched videos that aren't bookmarked (and, for long videos, not in a playlist).
    func automixCount(in category: String?, form: VideoForm = .short) -> Int {
        (form == .short ? automixLibraries(in: category) : longAutomixLibraries(in: category)).reduce(0) { $0 + $1.videos.count { !isPlayed($0) && !isBookmarked($0) } }
    }

    /// What Latest will play: unwatched long videos, not counting playlists.
    func latestCount(in category: String?) -> Int {
        mixLibraries(in: category, form: .long).reduce(0) { $0 + unplayedCount($1) }
    }

    /// Keeps the newer state of each video.
    private func mergePlayed(_ incoming: [String: PlayedMark]) {
        for (id, mark) in incoming where mark.at > (marks[id]?.at ?? .distantPast) {
            marks[id] = mark
        }
        played = Set(marks.filter(\.value.played).keys)
        store.savePlayed(marks)
    }

    /// Short libraries: every creator that isn't a playlist, except YouTube creators the Mac only sends long videos
    /// for. Long libraries: creators with long videos, and playlists. The Mac sends each video once, so a playlist is
    /// built from its `order`: every long video on the device in it, whichever creator it came under.
    private func rebuildLibraries() {
        guard let manifest else {
            libraries = []
            longLibraries = []
            vineLibraries = []
            return
        }
        let downloaded = manifest.videos.filter { store.isDownloaded($0) }
        let short = Dictionary(grouping: downloaded.filter { !$0.isLong }, by: \.creator)
        let long = Dictionary(grouping: downloaded.filter(\.isLong), by: \.creator)
        let sentLong = Set(manifest.videos.filter(\.isLong).map(\.creator))
        let sentShort = Set(manifest.videos.filter { !$0.isLong }.map(\.creator))
        libraries = manifest.creators
            .filter { !$0.isPlaylist && !$0.isVine && (sentShort.contains($0.username) || !sentLong.contains($0.username)) }
            .map { CreatorLibrary(creator: $0, videos: (short[$0.username] ?? []).sorted { $0.date > $1.date }) }
        longLibraries = manifest.creators
            .filter { $0.isPlaylist || sentLong.contains($0.username) }
            .map { creator in
                if creator.isPlaylist {
                    let position = Dictionary((creator.order ?? []).enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
                    var seen: Set<String> = []
                    let videos = downloaded.filter { $0.isLong && position[$0.id] != nil && seen.insert($0.id).inserted }
                        .sorted { position[$0.id]! < position[$1.id]! }
                    return CreatorLibrary(creator: creator, videos: videos, form: .long)
                }
                return CreatorLibrary(creator: creator, videos: (long[creator.username] ?? []).sorted { $0.date > $1.date },
                                      form: .long)
            }
        // Only authors with a Vine downloaded here: the rest would be empty avatars.
        vineLibraries = manifest.creators.filter(\.isVine)
            .map { CreatorLibrary(creator: $0, videos: (short[$0.username] ?? []).sorted { $0.date > $1.date }) }
            .filter { !$0.videos.isEmpty }
    }

    // MARK: Pairing

    /// Returns an error message, or nil once paired.
    func pair(host: String, port: Int, code: String) async -> String? {
        do {
            let response = try await SyncClient(host: host, port: port)
                .pair(code: code.filter(\.isNumber), deviceName: UIDevice.current.name)
            let newPairing = Pairing(host: host, port: port, token: response.token, macName: response.macName ?? "Mac")
            store.savePairing(newPairing)
            pairing = newPairing
            return nil
        } catch {
            return friendlyMessage(error)
        }
    }

    /// Forgets the Mac. Downloaded videos stay.
    /// Forgets the Mac and everything that came from it: videos, avatars, the manifest, and the watched, Watch Later
    /// and bookmark history (the Mac keeps its own, so pairing again brings them back). Appearance and the other
    /// settings for this device stay.
    func unpair() {
        store.savePairing(nil)
        pairing = nil
        store.removeAllVideos()
        manifest = nil
        marks = [:]
        played = []
        watchLaterMarks = [:]
        bookmarkMarks = [:]
        positionMarks = [:]
        nowPlayingMark = .none
        playbackRules = PlaybackRules()
        onPlaybackRulesChanged?()
        positionsChanged = false
        store.savePlayed([:])
        store.saveWatchLater([:])
        store.saveBookmarks([:])
        collapsedCards = []
        lastSyncMessage = nil
        lastSyncAt = nil
        stopWatchingMacDownload()
        macDownloadFinished = false
        macDownloadBaseline = nil
        requestedVideoIDs = []
        followedDownloadAt = nil
        for key in ["collapsedCards", "lastSyncMessage", "lastSyncAt"] { UserDefaults.standard.removeObject(forKey: key) }
        rebuildLibraries()
        onLibraryChanged?()
    }

    // MARK: Syncing

    /// Starts a sync that keeps going if the screen that asked for it goes away.
    func syncInBackground(_ forms: SyncForms? = nil) {
        Task { await sync(forms) }
    }

    /// On launch/foreground: syncs when automatic sync is on and it's been a while, and otherwise just swaps positions.
    func syncIfDue() {
        guard pairing != nil, !isSyncing else { return }
        if autoSync, lastSyncAt.map({ Date().timeIntervalSince($0) >= 15 * 60 }) ?? true {
            syncInBackground()
        } else {
            Task { await exchangePositions() }
        }
    }

    /// Pulls new videos, drops ones the Mac deleted, and swaps watched history. Returns a summary. Any sync but the one
    /// a finished Mac download starts (`afterMacDownload`) removes that download's checkmark.
    @discardableResult
    func sync(_ forms: SyncForms? = nil, afterMacDownload: Bool = false) async -> String {
        guard !isSyncing else { return "Already syncing" }
        isSyncing = true
        syncProgress = nil
        // Keep going for a bit if the app is sent to the background mid-sync.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Curated sync")
        defer {
            isSyncing = false
            syncStep = ""
            syncProgress = nil
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        let message: String
        do {
            message = try await runSync(forms ?? syncForms, afterMacDownload: afterMacDownload)
        } catch {
            message = friendlyMessage(error)
        }
        lastSyncMessage = message
        UserDefaults.standard.set(message, forKey: "lastSyncMessage")
        return message
    }

    /// Asks the Mac to download everything now. The new videos and the time it finished arrive with a later sync.
    func forceDownload() async {
        guard let saved = pairing, !isRequestingDownload else { return }
        isRequestingDownload = true
        defer {
            isRequestingDownload = false
            if !isSyncing { syncStep = "" }
        }
        macDownloadFinished = false
        forceDownloadMessage = nil
        do {
            guard let client = await connect(saved) else {
                throw SyncError(message: "Couldn't reach \(saved.macName). Make sure Curated is open on your Mac with phone sync turned on, and that you're on the same Wi-Fi.")
            }
            let reply = try await client.forceDownload()
            if !reply.started { forceDownloadMessage = reply.message }
            // Again from the start, in case the last look at the Mac is just ending.
            macDownloadWatch?.cancel()
            macDownloadWatch = nil
            watchMacDownload()
        } catch let error as SyncError where error.status == 404 {
            forceDownloadMessage = "Update Curated on your Mac to use Force Download."
        } catch {
            forceDownloadMessage = friendlyMessage(error)
        }
    }

    /// Follows the Mac's download on a connection the Mac closes when it's over; with nothing downloading, that's at once.
    /// If the connection breaks mid-download it tries again a few times, then waits for the next call.
    func watchMacDownload() {
        guard let saved = pairing, macDownloadWatch == nil else { return }
        macDownloadWatch = Task {
            var failures = 0
            while !Task.isCancelled {
                do {
                    guard let client = await connect(saved) else { throw SyncError(message: "") }
                    if !isSyncing { syncStep = "" }
                    try await client.followDownload { self.apply($0) }
                    break
                } catch {
                    failures += 1
                    if error is SyncError && (error as? SyncError)?.status != 0 { break }  // An older Mac, or unpaired.
                    guard macDownload != nil, failures < 3 else { break }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            // Stopping already cleared these, and a new watch may have started.
            guard !Task.isCancelled else { return }
            macDownload = nil
            macDownloadWatch = nil
        }
    }

    /// The Mac started downloading these: fetches them when it's done.
    func followRequestedVideos(_ ids: [String]) {
        requestedVideoIDs.formUnion(ids)
        // Again from the start, in case the last look at the Mac is just ending.
        macDownloadWatch?.cancel()
        macDownloadWatch = nil
        watchMacDownload()
    }

    /// Back on screen: videos asked for earlier may be ready, or still coming.
    func resumeFollowingRequestedVideos() {
        if !requestedVideoIDs.isEmpty { watchMacDownload() }
    }

    /// Closes the connection, for when the app leaves the screen or, unless videos asked for are on their way
    /// (`keepingRequested`), when Settings closes.
    func stopWatchingMacDownload(keepingRequested: Bool = false) {
        forceDownloadMessage = nil
        if keepingRequested && !requestedVideoIDs.isEmpty { return }
        macDownloadWatch?.cancel()
        macDownloadWatch = nil
        macDownload = nil
    }

    private func apply(_ event: MacDownloadProgress) {
        if let at = event.lastDownloadAt { followedDownloadAt = at }
        if event.downloading {
            if macDownloadBaseline == nil { macDownloadBaseline = event.lastDownloadAt ?? .distantPast }
            macDownload = event
            macDownloadFinished = false
            forceDownloadMessage = nil
        } else {
            macDownload = nil
            // The Mac had started on videos asked for when it said so, so not downloading now means it's over.
            var fetch = !requestedVideoIDs.isEmpty
            if let baseline = macDownloadBaseline {
                macDownloadBaseline = nil
                if (event.lastDownloadAt ?? .distantPast) != baseline {
                    macDownloadFinished = true
                    fetch = true
                }
            }
            if fetch { syncAfterMacDownload() }
        }
    }

    /// Fetches what the Mac just downloaded, after any sync under way, which may have listed the videos too early.
    private func syncAfterMacDownload() {
        Task {
            while isSyncing { try? await Task.sleep(for: .seconds(1)) }
            await sync(afterMacDownload: true)
        }
    }

    /// How many videos download at once. Each new connection starts slowly, so small videos gain from several: on real
    /// Wi-Fi, 12 MB videos went at 204 Mbps one at a time, 274 three at a time and 315 six at a time.
    static let parallelDownloads = 6

    /// Fetches the Mac's whole list (short and long; it's small), but only downloads `forms`. Nothing is removed for
    /// being a kind that wasn't picked: only videos the Mac no longer has leave the device.
    private func runSync(_ forms: SyncForms, afterMacDownload: Bool) async throws -> String {
        guard let saved = pairing else { return "Pair with your Mac first" }
        // Where a sync's time goes, in diagnostics.log.
        let syncStarted = Date()
        var lapStarted = syncStarted
        func lap(_ step: String) {
            Diagnostics.log("Sync timing: \(step) \(Int(Date().timeIntervalSince(lapStarted) * 1000)) ms")
            lapStarted = Date()
        }
        syncStep = "Looking for your Mac…"
        guard let client = await connect(saved, lookUp: true) else {
            throw SyncError(message: "Couldn't reach \(saved.macName). Make sure Curated is open on your Mac with phone sync turned on, and that you're on the same Wi-Fi.")
        }

        lap("find Mac (\(client.host))")

        syncStep = "Checking for new videos…"
        // Vines come with the short videos: listed every time, downloaded when short videos are.
        let manifestData = try await client.manifest(forms: .all, vine: true)
        lap("video list request (\(manifestData.count / 1024) KB)")
        let newManifest = try Manifest.decode(manifestData)
        lap("video list decode (\(newManifest.videos.count) videos)")

        syncStep = "Syncing watched videos…"
        let merged = try await client.played(marks, watchLater: watchLaterMarks, bookmarks: bookmarkMarks)
        mergePlayed(merged.marks)
        mergeWatchLater(merged.watchLater)
        mergeBookmarks(merged.bookmarks)
        lap("watched marks (\(marks.count) marks)")
        // After the watched marks, which can clear positions. An older Mac doesn't have this.
        positionsChanged = false
        if let reply = try? await client.positions(positionMarks, nowPlaying: nowPlayingMark, playback: playbackRules) { merge(reply) }
        lap("positions")

        store.saveManifest(manifestData)
        let removed = store.removeVideos(except: newManifest.videos)
        lap("save list, remove \(removed) old videos")
        manifest = newManifest
        rebuildLibraries()
        // Deleted videos (and ones the Mac marked watched) leave the queue now, not after the downloads.
        onLibraryChanged?()
        lap("rebuild libraries")

        // Only new ones hold the sync up; the rest get a fresh copy about once a day, behind it.
        var staleAvatars: [String] = []
        for creator in newManifest.creators where creator.hasAvatar {
            let dest = store.avatarFile(creator.username)
            if let fetched = (try? dest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                if Date().timeIntervalSince(fetched) > 24 * 60 * 60 { staleAvatars.append(creator.username) }
            } else {
                try? await client.download("/avatar/\(creator.username)",
                                           partial: dest.appendingPathExtension("part"), to: dest) { _ in }
            }
        }
        refreshAvatars(staleAvatars, from: client)
        lap("avatars")
        // Long videos' thumbnails, for their galleries and lists. Small, and kept once fetched.
        let requested = requestedVideoIDs
        for video in newManifest.videos where (forms.includesLong || requested.contains(video.id)) && video.hasPoster == true
            && !FileManager.default.fileExists(atPath: store.posterFile(video).path) {
            let dest = store.posterFile(video)
            try? await client.download("/poster/\(video.id)", partial: dest.appendingPathExtension("part"), to: dest) { _ in }
        }

        lap("posters")
        // Only the kinds asked for this time, and videos asked for from the Mac; a video in a playlist and a creator's is sent once.
        var queued: Set<String> = []
        let missing = newManifest.videos.filter { (forms.includes($0) || requested.contains($0.id)) && !store.isDownloaded($0) && queued.insert($0.id).inserted }
            .sorted { $0.date > $1.date }
        lap("check downloaded (\(missing.count) missing)")
        let total = max(1, missing.reduce(0) { $0 + max(1, $1.size - (store.fileSize(store.partialFile($1)) ?? 0)) })
        // Bytes received, overall and since the speed was last shown.
        let done = LockedBox(0)
        let started = Date()
        var added = 0, failed = 0, next = 0
        var unauthorized: Error?
        /// "Downloading 4 of 12 · 256 Mbps": the videos finished or under way, and the speed so far.
        func showStep() {
            let elapsed = Date().timeIntervalSince(started)
            let speed = elapsed > 1 ? Double(done.get()) * 8 / elapsed / 1_000_000 : 0
            let current = min(missing.count, added + failed + 1)
            syncStep = "Downloading \(current) of \(missing.count)…" + (speed >= 1 ? String(format: " · %.0f Mbps", speed) : "")
            syncProgress = min(1, max(0, Double(done.get()) / Double(total)))
        }
        // A few at a time: one by one left the Wi-Fi idle between and during each file's requests.
        await withTaskGroup(of: (Video, Error?).self) { group in
            func startNext() {
                guard next < missing.count else { return }
                let video = missing[next]
                next += 1
                let partial = store.partialFile(video), file = store.videoFile(video)
                group.addTask {
                    do {
                        try await client.download("/video/\(video.id)", partial: partial, to: file) { n in
                            done.update { $0 += n }
                        }
                        return (video, nil)
                    } catch {
                        return (video, error)
                    }
                }
            }
            for _ in 0..<Self.parallelDownloads { startNext() }
            // The speed and progress, twice a second while downloading.
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    showStep()
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            defer { ticker.cancel() }
            while let (_, error) = await group.next() {
                if let error = error as? SyncError, error.status == 401 {
                    unauthorized = error
                    group.cancelAll()
                    break
                }
                if error == nil {
                    added += 1
                    rebuildLibraries()
                } else {
                    failed += 1
                }
                showStep()
                startNext()
            }
        }
        if let unauthorized { throw unauthorized }

        if added > 0 { onLibraryChanged?() }
        lap("downloads (\(added) added)")
        Diagnostics.log("Sync timing: total \(Int(Date().timeIntervalSince(syncStarted) * 1000)) ms")
        lastSyncAt = Date()
        UserDefaults.standard.set(lastSyncAt, forKey: "lastSyncAt")
        if !afterMacDownload { macDownloadFinished = false }
        // What the Mac finished is all here. One it couldn't download isn't waited for, since it isn't coming.
        if afterMacDownload && failed == 0 { requestedVideoIDs.subtract(requested) }
        let kind = forms == .all || !requested.isEmpty ? "" : "\(forms.rawValue) "
        var parts = [added == 0 ? "Up to date" : "\(added) new \(kind)video\(added == 1 ? "" : "s")"]
        if removed > 0 { parts.append("\(removed) removed") }
        if failed > 0 { parts.append("\(failed) couldn't download") }
        return parts.joined(separator: " · ")
    }

    private func refreshAvatars(_ usernames: [String], from client: SyncClient) {
        guard !usernames.isEmpty, !refreshingAvatars else { return }
        refreshingAvatars = true
        Task {
            defer { refreshingAvatars = false }
            for username in usernames where pairing != nil {
                let dest = store.avatarFile(username)
                try? await client.download("/avatar/\(username)", partial: dest.appendingPathExtension("part"), to: dest) { _ in }
            }
        }
    }

    /// With `lookUp` (full syncs), finds the Mac by Bonjour and uses its best address, wired first. Otherwise, or if
    /// that finds nothing (some networks block Bonjour), tries where the Mac was last seen, then looks for any Mac.
    private func connect(_ saved: Pairing, lookUp: Bool = false) async -> SyncClient? {
        func reachable(_ host: String, _ port: Int) async -> Bool {
            (try? await SyncClient(host: host, port: port).info(timeout: 2)) != nil
        }
        var target: (String, Int)?
        if lookUp,
           // The same port too, so a test copy of the Mac app with the same name is never mistaken for it.
           let mac = await Discovery.find(for: 1.5, name: saved.macName).first(where: { $0.port == saved.port }),
           let info = try? await SyncClient(host: mac.host, port: mac.port).info() {
            let addresses = (info["addresses"] ?? "").split(separator: ",").map(String.init)
            for host in addresses + [mac.host] where await reachable(host, mac.port) {
                target = (host, mac.port)
                break
            }
        }
        if target != nil {
            // Found above.
        } else if await reachable(saved.host, saved.port) {
            target = (saved.host, saved.port)
        } else {
            syncStep = "Looking for your Mac on this network…"
            // The Mac this phone paired with first, then any other Curated on the network.
            let found = await Discovery.find().sorted { $0.name == saved.macName && $1.name != saved.macName }
            for mac in found where await reachable(mac.host, mac.port) {
                target = (mac.host, mac.port)
                break
            }
        }
        guard let (host, port) = target else { return nil }
        if host != saved.host || port != saved.port {
            var moved = saved
            moved.host = host
            moved.port = port
            store.savePairing(moved)
            pairing = moved
        }
        return SyncClient(host: host, port: port, token: saved.token)
    }

    // MARK: Home

    func setCollapsed(_ card: String, _ collapsed: Bool) {
        if collapsed { collapsedCards.insert(card) } else { collapsedCards.remove(card) }
        UserDefaults.standard.set(Array(collapsedCards), forKey: "collapsedCards")
    }

    // MARK: Background sync

    /// Asks iOS for a sync while charging on a network. iOS decides when (if ever) it runs.
    func scheduleBackgroundSync() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundSyncID)
        guard autoSync, pairing != nil else { return }
        let request = BGProcessingTaskRequest(identifier: Self.backgroundSyncID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func friendlyMessage(_ error: Error) -> String {
        if let error = error as? SyncError {
            return error.status == 401 ? "Your Mac doesn't recognize this phone anymore. Unpair and pair again." : error.message
        }
        if let error = error as? URLError {
            switch error.code {
            case .cannotConnectToHost, .timedOut, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "Couldn't connect. Check that phone sync is on in Curated on your Mac."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// Light, dark, or whatever the device is set to. The player stays dark either way.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}
