import AVFoundation
import AVKit
import MediaPlayer
import Observation
import UIKit

/// One player for the whole app, like the Mac's Playback.
@MainActor @Observable
final class Playback: NSObject {
    /// Holds the playing video plus the next one, which AVFoundation gets ready to play so a swipe starts it at once.
    let player = AVQueuePlayer()
    private let app: AppState

    private(set) var queue: [Video] = []
    private(set) var index: Int?
    private(set) var mode: PlaybackMode?
    private(set) var finished = false
    private(set) var isPlaying = false
    /// Set when the queue was cut to a time budget (Automix "Time Limit").
    private(set) var timeLimitMinutes: Int?
    /// Position in the current video, updated a few times a second.
    private(set) var position: Double = 0
    /// Counts videos loaded from another device, so the wide layout can select where they live.
    private(set) var syncedVideoLoads = 0
    /// When a position last went to the Mac while playing with the screen locked.
    @ObservationIgnored private var lastBackgroundSend = Date.distantPast
    /// The chosen speed; stays the same from video to video.
    private(set) var speed: Float = 1
    /// The current video's category always plays at 1× (see `PlaybackRules`), so the chosen speed waits for the next one.
    private(set) var speedLocked = false
    /// The speed the current video plays at, apart from a held 2×.
    var shownSpeed: Float { speedLocked ? 1 : speed }
    /// True while the video is held down for a temporary 2×.
    private(set) var isHoldingFast = false
    private(set) var isPipActive = false
    /// Clear mode: nothing over a short video until it's tapped; then the controls come up for 3 seconds after the last
    /// touch. For this session only, as on Android.
    var clearMode = false
    /// AVKit's word that picture in picture can start now (a player layer is attached and its video is ready).
    private(set) var isPipPossible = false
    /// The video that has played its first moments, so its picture is surely on screen (the player layer doesn't
    /// report a new first frame when the queue moves on).
    private(set) var startedID: String?
    /// Width over height of the playing video, once AVFoundation knows it.
    private(set) var videoAspect: CGFloat?
    /// A long video ended with autoplay off, and there's another to play: the player waits on the Up Next card.
    private(set) var awaitingNext = false
    /// A long video is full screen in the stock player (which turns an upright iPhone sideways itself).
    var isStockFullscreen = false
    /// The lock screen's picture for the current video, once it's loaded.
    @ObservationIgnored private var artwork: (id: String, image: MPMediaItemArtwork?)?
    @ObservationIgnored private var lastSavedPosition: Double = 0
    /// While the player is moving to a position from the Mac, its time is still the old one, which mustn't be saved.
    @ObservationIgnored private var movingToSyncedPosition = false
    /// Waits for a resumed long video to be ready, then seeks to where it was left off.
    @ObservationIgnored private var resumeObservation: NSKeyValueObservation?

    static let speeds: [Float] = [1, 1.5, 2]

    @ObservationIgnored private var pipController: AVPictureInPictureController?
    @ObservationIgnored private weak var pipLayer: AVPlayerLayer?
    @ObservationIgnored private var pipPossibleObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [Any] = []
    @ObservationIgnored private var itemStatus: NSKeyValueObservation?
    @ObservationIgnored private var startObserver: Any?
    @ObservationIgnored private var itemSize: NSKeyValueObservation?
    /// Every layer drawing the player. Locking the screen takes the video off them so the sound can play on: iOS
    /// pauses a player that's attached to a layer once the app is in the background.
    @ObservationIgnored private let layers = NSHashTable<AVPlayerLayer>.weakObjects()
    /// Long videos' stock players, which also let go of the player while the screen is locked.
    @ObservationIgnored private let stockPlayers = NSHashTable<AVPlayerViewController>.weakObjects()
    @ObservationIgnored private var lockedAt: Date?
    /// The previous video's item, its file already open, for a swipe back.
    @ObservationIgnored private var preloaded: [String: AVPlayerItem] = [:]
    /// The video queued in `player` behind the current one.
    @ObservationIgnored private var queuedID: String?
    @ObservationIgnored private var wasPlayingWhenLeft = false
    /// A queue started while the app was in the background, which waits paused until the app is on screen.
    @ObservationIgnored private var playWhenActive = false
    /// When the player last stopped playing; nil while it plays.
    @ObservationIgnored private var pausedAt: Date?
    /// The current video's item is being replaced by `reopenAndResume`, and should play once it's back in place.
    @ObservationIgnored private var playAfterReopen = false

    var current: Video? { index.flatMap { queue.indices.contains($0) ? queue[$0] : nil } }
    var hasPrevious: Bool { (index ?? 0) > 0 }

    init(app: AppState) {
        self.app = app
        super.init()
        player.preventsDisplaySleepDuringVideoPlayback = true
        // Every video is a local file, so there's nothing to buffer: start the moment a frame is decoded.
        player.automaticallyWaitsToMinimizeStalling = false
        // The end of a video is handled in videoEnded, not by moving on to the queued one.
        player.actionAtItemEnd = .pause
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                if began { self?.audioInterrupted = true }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.videoEnded()
            }
        })
        observers.append(player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                self?.isPlaying = playing
                self?.pausedAt = playing ? nil : self?.pausedAt ?? Date()
                if !playing {
                    self?.savePosition()
                    self?.app.sendPositionsSoon()
                }
                self?.updateNowPlayingInfo()
                self?.updateScreenAwake()
            }
        })
        observers.append(player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                // While a resumed or fresh item is still moving to its place, its time isn't where the video is.
                guard let self, time.seconds.isFinite, self.resumeObservation == nil else { return }
                self.position = time.seconds
                if abs(time.seconds - self.lastSavedPosition) >= 5 { self.savePosition() }
                // Playing on with the screen locked, there's no pause to send it on.
                if UIApplication.shared.applicationState == .background, Date().timeIntervalSince(self.lastBackgroundSend) >= 60 {
                    self.lastBackgroundSend = Date()
                    self.app.sendPositionsSoon()
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.newErrorLogEntryNotification, object: nil, queue: .main
        ) { note in
            guard let event = (note.object as? AVPlayerItem)?.errorLog()?.events.last else { return }
            Diagnostics.log("Player error: \(event.errorStatusCode) \(event.errorDomain) \(event.errorComment ?? "")")
        })
        setUpRemoteCommands()
        observeScreenLock()
        app.onLibraryChanged = { [weak self] in
            self?.refreshAfterSync()
            self?.loadSyncedVideo()
        }
        app.onPositionsMerged = { [weak self] ids in self?.positionsMerged(ids) }
        app.onNowPlayingMerged = { [weak self] in self?.loadSyncedVideo() }
        app.onPlaybackRulesChanged = { [weak self] in
            self?.adoptStockSpeed()
            self?.applySpeed()
        }
        app.onSwitchedToLong = { [weak self] in self?.loadSyncedVideo(switching: true) }
    }

    // MARK: Queue

    func start(_ queue: [Video], at index: Int = 0, mode: PlaybackMode, timeLimitMinutes: Int? = nil) {
        // Save the old video's place while `index` still points into the old queue.
        savePosition()
        self.index = nil
        self.queue = queue
        self.mode = mode
        self.timeLimitMinutes = timeLimitMinutes
        guard queue.indices.contains(index) else {
            stop()
            return
        }
        // iOS can launch the app in the background (for a background sync, while the phone charges), and a launch
        // opens Automix: without this it would start playing on the locked phone.
        playWhenActive = UIApplication.shared.applicationState == .background
        play(at: index, autoplay: !playWhenActive)
    }

    /// Loads the long video last playing on any device, paused where it was left, while long videos are showing.
    /// Never replaces a long video that's playing; a short one that's playing only when `switching` to long videos.
    private func loadSyncedVideo(switching: Bool = false) {
        guard switching || app.form == .long, let id = app.nowPlayingMark.id, current?.id != id,
              let library = app.longLibraries.first(where: { $0.videos.contains { $0.id == id } }),
              let at = library.videos.firstIndex(where: { $0.id == id }), !app.isPlayed(library.videos[at]) else { return }
        if let current, isPlaying, !finished, current.isLong || !switching { return }
        savePosition()
        index = nil
        queue = library.videos
        mode = .longCreator(library.id)
        timeLimitMinutes = nil
        playWhenActive = false
        play(at: at, autoplay: false)
        syncedVideoLoads += 1
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
        preloadNeighbors()
    }

    func play(at i: Int, autoplay: Bool = true) {
        guard queue.indices.contains(i) else { return }
        savePosition()
        adoptStockSpeed()
        if autoplay, queue[i].isLong { app.setNowPlaying(queue[i]) }
        app.sendPositionsSoon()
        index = i
        finished = false
        awaitingNext = false
        position = 0
        lastSavedPosition = 0
        resumeObservation = nil
        endReopen()
        let isQueued = queuedID == queue[i].id && player.items().count > 1
        let item: AVPlayerItem
        if isQueued {
            item = player.items()[1]
        } else {
            dropQueued()
            item = preloaded.removeValue(forKey: queue[i].id) ?? makeItem(queue[i])
        }
        queuedID = nil
        // A long video picks up where it was left off, once it's ready to seek.
        if queue[i].isLong, let saved = app.resumePosition(queue[i]) {
            let resume = max(0, saved - Double(app.playbackRules.resumeRewindSeconds))
            position = resume
            lastSavedPosition = resume
            resumeObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                guard item.status == .readyToPlay else { return }
                Task { @MainActor in
                    guard let self, self.player.currentItem === item, self.resumeObservation != nil else { return }
                    self.resumeObservation = nil
                    self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
        }
        watch(item)
        if isQueued { player.advanceToNextItem() } else { player.replaceCurrentItem(with: item) }
        if let startObserver { player.removeTimeObserver(startObserver) }
        let id = queue[i].id
        let start = player.currentTime() + CMTime(value: 1, timescale: 30)
        startObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: start)], queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.startedID = id }
        }
        applySpeed()
        if autoplay {
            activateAudio()
            player.play()
        } else {
            player.pause()
        }
        updateNowPlayingInfo()
        updateScreenAwake()
        preloadNeighbors()
    }

    /// Follows `item` while it's the current one.
    private func watch(_ item: AVPlayerItem) {
        // A missing or unreadable file shouldn't stall the queue.
        itemStatus = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                Diagnostics.log("Player item failed: \(item.error.map { "\($0)" } ?? "no error given")")
                self.advance(markingPlayed: false)
            }
        }
        itemSize = item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
            let size = item.presentationSize
            guard size.width > 0, size.height > 0 else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.videoAspect = size.width / size.height
            }
        }
    }

    private func makeItem(_ video: Video) -> AVPlayerItem {
        AVPlayerItem(asset: AVURLAsset(url: app.store.videoFile(video)),
                     automaticallyLoadedAssetKeys: [.isPlayable, .duration, .tracks, .preferredTransform])
    }

    /// Queues the next video behind the current one and opens the previous one, ahead of a swipe.
    private func preloadNeighbors() {
        let previous = previousVideo
        preloaded = preloaded.filter { id, _ in id == previous?.id }
        if let previous, preloaded[previous.id] == nil { preloaded[previous.id] = makeItem(previous) }
        guard let next = upNext, player.currentItem != nil else { return dropQueued() }
        guard queuedID != next.id else { return }
        dropQueued()
        let item = makeItem(next)
        guard player.canInsert(item, after: player.currentItem) else { return }
        player.insert(item, after: player.currentItem)
        queuedID = next.id
    }

    /// Takes everything but the current video out of the player's queue.
    private func dropQueued() {
        for item in player.items().dropFirst() { player.remove(item) }
        queuedID = nil
    }

    /// Activating the audio session can wait on the system, so it happens off the main thread. `done` runs on the main
    /// thread once it's over, however it went.
    private func activateAudio(then done: (@MainActor @Sendable () -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                if done != nil {
                    Diagnostics.log("Audio session active after an interruption, in \(Int(Date().timeIntervalSince(started) * 1000)) ms; \(Diagnostics.audioState)")
                }
            } catch {
                Diagnostics.log("Activating the audio session failed: \(error); \(Diagnostics.audioState)")
            }
            if let done { Task { @MainActor in done() } }
        }
    }

    /// After a sync, rebuilds the loaded queue from what's on the phone now: deleted and newly watched videos drop out,
    /// new ones come in, and mixes are reshuffled. The current video keeps playing if it's still here; nothing starts
    /// playing that was paused (a sync can run in the background), and a finished mix stays finished.
    private func refreshAfterSync() {
        guard let mode, !finished else { return }  // The end card stays up.
        let wasPlaying = player.timeControlStatus != .paused
        let current = current.flatMap { video in app.allVideos.contains { $0.id == video.id } ? video : nil }
        var fresh = Queues.build(mode, app)
        if mode.creatorUsername != nil {
            // A creator's list keeps its order; just find our place in it again.
            queue = fresh
            if let current, let at = fresh.firstIndex(where: { $0.id == current.id }) {
                index = at
                preloadNeighbors()
            } else if fresh.isEmpty {
                stop()
            } else {
                play(at: fresh.indices.first { !app.isPlayed(fresh[$0]) } ?? 0, autoplay: wasPlaying)
            }
            return
        }
        fresh.removeAll { $0.id == current?.id }
        // A time-limited mix keeps its remaining budget.
        if timeLimitMinutes != nil { fresh = Queues.limit(fresh, toSeconds: max(0, secondsUntilEnd - currentRemaining)) }
        if let current {
            queue = [current] + fresh
            index = 0
            preloadNeighbors()
        } else {
            queue = fresh
            if fresh.isEmpty {
                player.pause()
                player.removeAllItems()
                queuedID = nil
                index = nil
                updateNowPlayingInfo()
                updateScreenAwake()
            } else {
                play(at: 0, autoplay: wasPlaying)
            }
        }
    }

    /// Advances to the next unplayed video. A creator's list wraps around; mixes only move forward.
    /// Called when a video plays to the end or is skipped, which is what counts as watching it.
    func next() { advance(markingPlayed: true) }

    /// A video played to the end. A short one with autoplay off is marked watched and plays again; a long one with
    /// autoplay off is marked watched and waits; otherwise on to the next.
    private func videoEnded() {
        if let index, queue.indices.contains(index), !queue[index].isLong, !app.autoplayShort {
            app.setPlayed(queue[index], true)
            player.seek(to: .zero)
            resume()
            return
        }
        guard let index, queue.indices.contains(index), queue[index].isLong, !app.autoplayLong else { return next() }
        app.setPlayed(queue[index], true)
        if nextIndex(after: index) != nil { awaitingNext = true } else { finished = true }
        updateScreenAwake()
    }

    /// From the Up Next card.
    func playNext() {
        guard let index, let next = nextIndex(after: index) else { return }
        play(at: next)
    }

    /// From the Up Next card: the video that just ended, from the start.
    func replay() {
        awaitingNext = false
        player.seek(to: .zero)
        resume()
    }

    func seek(to seconds: Double) {
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Remembers how far into the current long video playback is. Only positions worth resuming from are kept, and
    /// one is forgotten once the video is nearly over, so a finished video starts from the top next time.
    func savePosition() {
        guard let video = current, video.isLong, !app.isPlayed(video), !finished, resumeObservation == nil,
              !movingToSyncedPosition else { return }
        let time = player.currentTime().seconds
        // Sitting still isn't news: re-saving an old place with a new date would beat the Mac's newer one.
        guard time.isFinite, abs(time - lastSavedPosition) >= 1 else { return }
        lastSavedPosition = time
        let itemLength = player.currentItem?.duration.seconds
        let length = video.duration ?? (itemLength?.isFinite == true ? itemLength! : 0)
        if length > 0 && time > length - 20 {
            app.setResumePosition(nil, for: video)
        } else if time > 10 {
            app.setResumePosition(time, for: video)
        }
    }

    /// Another device moved on in a video that's loaded here: a paused player follows it. One that's playing carries
    /// on, and its next save wins.
    private func positionsMerged(_ ids: Set<String>) {
        guard let video = current, video.isLong, ids.contains(video.id), !finished, resumeObservation == nil,
              player.timeControlStatus == .paused else { return }
        guard let seconds = app.resumePosition(video) else {
            lastSavedPosition = player.currentTime().seconds
            return
        }
        movingToSyncedPosition = true
        position = seconds
        lastSavedPosition = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.movingToSyncedPosition = false }
        }
    }

    func toggleBookmark() {
        guard let video = current else { return }
        app.setBookmarked(video, !app.isBookmarked(video))
    }

    /// Saves the current video to Watch Later and moves on without marking it watched.
    func saveForLater() {
        guard let video = current, !finished else { return }
        app.setWatchLater([video], true)
        advance(markingPlayed: false)
    }

    /// Where `next()` goes from `index`: the next unplayed video, wrapping around in a creator's list.
    private func nextIndex(after index: Int) -> Int? {
        var candidates = Array(queue.indices[min(index + 1, queue.count)...])
        if mode?.creatorUsername != nil { candidates += queue.indices[..<min(index, queue.count)] }
        // Bookmarks are for rewatching, so they play straight through, watched or not.
        if mode?.isBookmarks == true { return candidates.first }
        return candidates.first { !app.isPlayed(queue[$0]) }
    }

    /// The video a swipe up would bring in, shown sliding up under the finger. Nil at the end of a mix.
    var upNext: Video? {
        guard let index, !finished else { return nil }
        return nextIndex(after: index).map { queue[$0] }
    }

    /// The video a swipe down would bring back.
    var previousVideo: Video? {
        guard let index, index > 0, queue.indices.contains(index - 1) else { return nil }
        return queue[index - 1]
    }

    private func advance(markingPlayed: Bool) {
        guard let index else { return }
        if markingPlayed, queue.indices.contains(index) { app.setPlayed(queue[index], true) }
        if let i = nextIndex(after: index) {
            play(at: i)
        } else {
            player.pause()
            finished = true
            awaitingNext = false
            updateNowPlayingInfo()
            updateScreenAwake()
        }
    }

    func previous() {
        guard let index, index > 0 else { return }
        play(at: index - 1)
    }

    func togglePlayPause() {
        if player.timeControlStatus == .paused && !playAfterReopen { resume() } else { pause() }
    }

    func resume() {
        guard let current, !finished else { return }
        if current.isLong {
            app.setNowPlaying(current)
            app.sendPositionsSoon()
        }
        // An interruption doesn't always say when it's over, and sound has gone missing after one, so playing waits for
        // the session then rather than racing it.
        let afterInterruption = audioInterrupted && !reopening
        audioInterrupted = false
        if !afterInterruption { activateAudio() }
        // For sound that goes missing after resuming: whether the item has audio, and where it's going.
        let audioTracks = player.currentItem?.tracks.filter { $0.assetTrack?.mediaType == .audio } ?? []
        let pausedFor = pausedAt.map { Date().timeIntervalSince($0) } ?? 0
        let reopen = shouldReopen(pausedFor: pausedFor)
        Diagnostics.log("Resumed\(reopen ? " with a fresh item" : ""): paused \(Int(pausedFor)) s, muted \(player.isMuted), "
            + "volume \(player.volume), audio tracks \(audioTracks.count) (enabled \(audioTracks.filter(\.isEnabled).count)), "
            + "app \(UIApplication.shared.applicationState.rawValue); " + Diagnostics.audioState)
        if reopening {
            playAfterReopen = true
        } else if afterInterruption {
            awaitingAudio = true
            activateAudio { [weak self] in
                guard let self, self.awaitingAudio else { return }
                self.awaitingAudio = false
                if reopen { self.reopenAndResume() } else { self.player.play() }
            }
        } else if reopen {
            reopenAndResume()
        } else {
            player.play()
        }
    }

    func pause() {
        awaitingAudio = false
        playAfterReopen = false
        player.pause()
    }

    /// After a while paused with the app off screen, the item can come back with its sound gone for good: a second or
    /// two plays, then the picture carries on in silence, and only a new item brings it back. So a resume from the lock
    /// screen or headphones after more than a moment's pause (locking the screen itself pauses for less) starts a new
    /// item, as does one on screen after a long pause.
    private func shouldReopen(pausedFor: Double) -> Bool {
        guard player.currentItem != nil, !awaitingNext else { return false }
        return pausedFor >= (UIApplication.shared.applicationState == .active ? 60 : 2)
    }

    /// The audio session was interrupted since it was last activated.
    @ObservationIgnored private var audioInterrupted = false
    /// `resume` is waiting on the audio session after an interruption, and should play once it's active.
    @ObservationIgnored private var awaitingAudio = false
    /// Whether `reopenAndResume` is waiting on a new item.
    @ObservationIgnored private var reopening = false
    /// Keeps the app running until the new item plays: without playing, it could be suspended first.
    @ObservationIgnored private var reopenBackgroundTask = UIBackgroundTaskIdentifier.invalid

    private func endReopen() {
        reopening = false
        playAfterReopen = false
        guard reopenBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(reopenBackgroundTask)
        reopenBackgroundTask = .invalid
    }

    /// Replaces the current video's item with a new one at the same spot, and plays once it's there.
    private func reopenAndResume() {
        guard let video = current else { return }
        let time = player.currentTime()
        let item = makeItem(video)
        endReopen()
        reopenBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Curated resume") { [weak self] in
            MainActor.assumeIsolated { self?.endReopen() }
        }
        reopening = true
        playAfterReopen = true
        dropQueued()
        watch(item)
        // Also keeps savePosition from saving the new item's time before it has moved.
        resumeObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard item.status != .unknown else { return }
            Task { @MainActor in
                guard let self, self.player.currentItem === item, self.reopening else { return }
                // A failed item moves on to the next video (`watch`).
                guard item.status == .readyToPlay else { return self.endReopen() }
                self.player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.player.currentItem === item, self.reopening else { return }
                        self.resumeObservation = nil
                        let play = self.playAfterReopen
                        self.endReopen()
                        guard play else { return }
                        self.applySpeed()
                        self.player.play()
                    }
                }
            }
        }
        player.replaceCurrentItem(with: item)
        preloadNeighbors()
    }

    /// Back to the start of the current video.
    func restart() {
        guard current != nil, !finished else { return }
        player.seek(to: .zero)
        resume()
    }

    func stop() {
        savePosition()
        if let current, current.isLong { app.clearNowPlaying(current) }
        app.sendPositionsSoon()
        playWhenActive = false
        endReopen()
        awaitingNext = false
        player.pause()
        player.removeAllItems()
        queuedID = nil
        index = nil
        queue = []
        mode = nil
        applySpeed()
        timeLimitMinutes = nil
        finished = false
        preloaded = [:]
        updateNowPlayingInfo()
        updateScreenAwake()
    }

    /// Stops the screen sleeping while a video plays, on any screen (full player, mini player or picture in picture).
    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = isPlaying && current != nil && !finished
    }

    // MARK: Speed

    /// 1× → 1.5× → 2× → 1×.
    func cycleSpeed() {
        let i = Self.speeds.firstIndex(of: speed) ?? 0
        speed = Self.speeds[(i + 1) % Self.speeds.count]
        applySpeed()
    }

    func holdFast(_ holding: Bool) {
        guard holding != isHoldingFast else { return }
        isHoldingFast = holding
        applySpeed()
    }

    /// A speed picked in the stock player's menu counts as the chosen one, so it survives a 1× only video too.
    private func adoptStockSpeed() {
        guard current?.isLong == true, !speedLocked, !isHoldingFast, player.defaultRate > 0 else { return }
        speed = player.defaultRate
    }

    private func applySpeed() {
        let locked = current.map { app.playsAtNormalSpeed($0, from: mode) } ?? false
        if locked != speedLocked {
            speedLocked = locked
            for controller in stockPlayers.allObjects { updateStockSpeeds(controller) }
        }
        let rate = isHoldingFast ? 2 : shownSpeed
        player.defaultRate = rate
        if player.timeControlStatus != .paused { player.rate = rate }
    }

    // MARK: Time left

    private var currentRemaining: Double {
        guard let video = current, !finished else { return 0 }
        let itemLength = player.currentItem?.duration.seconds
        let length = video.duration ?? (itemLength?.isFinite == true ? itemLength! : 0)
        return max(0, length - position)
    }

    /// Queued videos that haven't been watched yet, not counting the one playing.
    var unwatched: [Video] { queue.filter { $0.id != current?.id && !app.isPlayed($0) } }

    /// The rest of the current video plus every unwatched video in the queue.
    var unwatchedSecondsLeft: Double { currentRemaining + unwatched.reduce(0) { $0 + ($1.duration ?? 0) } }

    /// How long until the queue runs out on its own: the rest of this video plus the unplayed ones after it.
    var secondsUntilEnd: Double {
        guard let index else { return 0 }
        let upcoming = queue.dropFirst(index + 1).filter { !app.isPlayed($0) }
        return currentRemaining + upcoming.reduce(0) { $0 + ($1.duration ?? 0) }
    }

    // MARK: Leaving the app

    /// Draws the player into `layer`, unless the screen is locked.
    func show(on layer: AVPlayerLayer) {
        layers.add(layer)
        layer.player = lockedAt == nil ? player : nil
    }

    /// The stock player's speed menu goes away while the video stays at 1×.
    private func updateStockSpeeds(_ controller: AVPlayerViewController) {
        controller.speeds = speedLocked ? [] : AVPlaybackSpeed.systemDefaultSpeeds
    }

    /// Plays in a long video's stock player, unless the screen is locked.
    func show(in controller: AVPlayerViewController) {
        stockPlayers.add(controller)
        updateStockSpeeds(controller)
        controller.player = lockedAt == nil ? player : nil
    }

    func hide(from controller: AVPlayerViewController) {
        stockPlayers.remove(controller)
        controller.player = nil
    }

    /// The stock player's own picture in picture, which counts like ours (playback goes on when leaving the app).
    func setStockPip(_ active: Bool) { isPipActive = active }

    /// The app is about to leave the screen (or Control Center is coming down over it).
    func willLeave() {
        wasPlayingWhenLeft = player.timeControlStatus != .paused
    }

    /// Leaving the app pauses, except in picture in picture, which starts as the app leaves the screen, and when the
    /// screen locks: then the sound plays on, as on Android.
    func didEnterBackground() {
        guard !isPipActive else { return }
        guard let lockedAt, Date().timeIntervalSince(lockedAt) < 3 else {
            pause()
            return
        }
        for layer in layers.allObjects { layer.player = nil }
        for controller in stockPlayers.allObjects { controller.player = nil }
        if wasPlayingWhenLeft { resume() }
    }

    func didBecomeActive() {
        lockedAt = nil
        if playWhenActive {
            playWhenActive = false
            resume()
        }
        // Only the layers taken off at lock; touching the one picture in picture is showing could disturb it.
        for layer in layers.allObjects where layer.player == nil { layer.player = player }
        for controller in stockPlayers.allObjects where controller.player == nil { controller.player = player }
    }

    /// SpringBoard's notice that the screen locked; the only way to tell locking from leaving the app.
    private func observeScreenLock() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let playback = Unmanaged<Playback>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { MainActor.assumeIsolated { playback.lockedAt = Date() } }
            },
            "com.apple.springboard.lockcomplete" as CFString, nil, .deliverImmediately
        )
    }

    // MARK: Picture in picture

    // Observed rather than read off pipController, which views can't see change: the controller only appears once the
    // player layer is on screen, after the buttons have drawn.
    var canStartPip: Bool { isPipPossible && current != nil }

    /// The on-screen player layer that PiP (including automatic PiP when leaving the app) uses.
    func attachPip(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported(), pipLayer !== layer else { return }
        pipLayer = layer
        let controller = AVPictureInPictureController(playerLayer: layer)
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
        controller?.delegate = self
        pipController = controller
        pipPossibleObservation = controller?.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.isPipPossible = possible }
        }
    }

    func detachPip(from layer: AVPlayerLayer) {
        guard pipLayer === layer, !isPipActive else { return }
        pipController = nil
        pipLayer = nil
        pipPossibleObservation = nil
        isPipPossible = false
    }

    func startPip() {
        guard let pipController else {
            Diagnostics.log("PiP button: no PiP controller (no player layer on screen)")
            return
        }
        let layer = pipLayer
        Diagnostics.log("PiP button: possible \(pipController.isPictureInPicturePossible), layer in window "
            + "\((layer?.delegate as? UIView)?.window != nil), "
            + "layer has player \(layer?.player != nil), ready \(layer?.isReadyForDisplay ?? false), "
            + "playing \(player.timeControlStatus != .paused)")
        pipController.startPictureInPicture()
    }

    // MARK: Lock screen and Control Center

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        // Headphones: one click plays or pauses, two skip ahead, three go back (at the first video, to its start).
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .success }
            if self.hasPrevious { self.previous() } else { self.restart() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let video = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.isLong ? video.displayTitle : video.caption.isEmpty ? "Video" : video.caption,
            MPMediaItemPropertyArtist: app.library(video.creator, form: video.isLong ? .long : .short)?.creator.displayName
                ?? "@\(creatorHandle(video.creator))",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(player.rate) : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let duration = video.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if artwork?.id != video.id { loadArtwork(for: video) }
        if let image = artwork?.image { info[MPMediaItemPropertyArtwork] = image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Off the main thread, so a video starts at once; the picture joins the lock screen when it's ready.
    private func loadArtwork(for video: Video) {
        artwork = (video.id, nil)
        let id = video.id
        let poster = video.isLong && video.hasPoster == true ? app.store.posterFile(video) : nil
        let file = app.store.videoFile(video)
        let avatar = app.store.avatarFile(video.creator)
        Task { [weak self] in
            let image = await Task.detached(priority: .utility) {
                await Self.artworkImage(poster: poster, video: file, avatar: avatar)
            }.value
            guard let self, self.current?.id == id else { return }
            self.artwork = (id, image.map(Self.makeArtwork))
            self.updateNowPlayingInfo()
        }
    }

    /// A long video's poster, or a frame from the video (short videos have no poster), or else the creator's picture.
    nonisolated static func artworkImage(poster: URL?, video: URL, avatar: URL) async -> UIImage? {
        if let poster, let image = UIImage(contentsOfFile: poster.path) { return image }
        if let frame = await videoFrame(video) { return frame }
        return UIImage(contentsOfFile: avatar.path)
    }

    /// A frame a moment in, cropped square when upright, since upright video would be a sliver beside the controls.
    private nonisolated static func videoFrame(_ file: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        guard let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return nil }
        guard frame.height > frame.width else { return UIImage(cgImage: frame) }
        let square = CGRect(x: 0, y: (frame.height - frame.width) / 2, width: frame.width, height: frame.width)
        return UIImage(cgImage: frame.cropping(to: square) ?? frame)
    }

    /// Off the main actor, because MediaPlayer calls the handler on a thread of its own.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

extension Playback: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPipActive = true }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        Task { @MainActor in self.isPipActive = false }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        Diagnostics.log("PiP failed to start: \(error); \(Diagnostics.audioState)")
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
