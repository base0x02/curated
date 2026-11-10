import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Short videos on a tape, as on the phones: a two-finger swipe up on the trackpad slides the next video up from
/// below, following the fingers, and a swipe down brings back the previous one. Past a quarter of the player, or
/// flicked, the neighbor finishes sliding in and plays; otherwise the tape springs back. A mouse wheel moves one
/// video per notch.
struct VideoTape: View {
    @Environment(Playback.self) private var playback
    /// Crops the video to fill the player, as on the phones (Phone view), instead of fitting it.
    var fill = false
    /// Off while something covers the tape (the phone's Up Next sheet).
    var swipes = true
    /// Lets the video float in AVKit's picture in picture (the main window's player).
    var pictureInPicture: PlayerFullScreen?
    /// How far the tape has moved up (negative) or down; the neighbor slides in alongside the playing video.
    @State private var offset: CGFloat = 0
    @State private var height: CGFloat = 600
    /// The video whose first frame covers the player after a swipe, until the player draws it.
    @State private var coverID: String?
    /// Moves the tape after the fingers lift; a new swipe waits for it.
    @State private var settleTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                TapePlayerView(player: playback.player, offset: offset, fill: fill, pictureInPicture: pictureInPicture) { coverID = nil }
                if offset < 0, let next = playback.upNext {
                    VideoStill(url: next.url, fill: fill).offset(y: h + offset)
                } else if offset > 0, let previous = playback.previousVideo {
                    VideoStill(url: previous.url, fill: fill).offset(y: -h + offset)
                }
                if let current = playback.current, coverID == current.id {
                    VideoStill(url: current.url, fill: fill).offset(y: offset)
                }
            }
            .frame(width: geo.size.width, height: h)
            .clipped()
            .onAppear { height = h }
            .onChange(of: h) { _, newHeight in height = newHeight }
        }
        .background(
            ScrollSwipeMonitor(
                canBegin: { swipes && settleTask == nil && playback.current != nil },
                changed: { offset = followFingers($0) },
                ended: endSwipe,
                step: step
            )
        )
        .task(id: playback.upNext?.id) {
            // Have the next video's first frame ready before a swipe starts.
            if let next = playback.upNext { await VideoStill.load(next.url) }
        }
        .task(id: playback.previousVideo?.id) {
            if let previous = playback.previousVideo { await VideoStill.load(previous.url) }
        }
        .onChange(of: playback.currentTime) { _, time in
            // Fallback in case the player never reports a new first frame.
            if time > 0.3 { coverID = nil }
        }
    }

    /// The tape follows the fingers, with rubber-band resistance where there's nothing to slide in.
    private func followFingers(_ travel: CGFloat) -> CGFloat {
        let hasNeighbor = travel < 0 ? playback.upNext != nil : playback.previousVideo != nil
        return hasNeighbor ? max(-height, min(height, travel)) : travel / 4
    }

    private func endSwipe(travel: CGFloat, velocity: CGFloat) {
        let goingUp = travel < 0
        let flicked = abs(velocity) > 600 && (velocity < 0) == goingUp
        let committed = abs(travel) > height * 0.25 || (abs(travel) > 20 && flicked)
        let incoming = goingUp ? playback.upNext : playback.previousVideo
        guard committed, incoming != nil else {
            // Swiping up past the last video still finishes the mix, as on the phones.
            if committed && goingUp { playback.next() }
            settle(to: 0, duration: 0.25)
            return
        }
        settle(to: goingUp ? -height : height, duration: 0.25) {
            if goingUp { playback.next() } else { playback.previous() }
            // The incoming frame stays in place until the player draws the same frame underneath it.
            coverID = playback.current?.id
            offset = 0
        }
    }

    /// One video per mouse-wheel notch.
    private func step(up: Bool) {
        guard settleTask == nil, (up ? playback.upNext : playback.previousVideo) != nil else { return }
        offset = up ? -1 : 1
        endSwipe(travel: up ? -height : height, velocity: 0)
    }

    /// Moves the tape to `target`, easing out. Stepped by hand rather than with a SwiftUI animation, so the player
    /// (an AppKit view) and the stills beside it move together, frame for frame.
    private func settle(to target: CGFloat, duration: TimeInterval, then completion: (() -> Void)? = nil) {
        settleTask?.cancel()
        let start = offset
        let began = Date()
        settleTask = Task { @MainActor in
            while !Task.isCancelled {
                let t = min(1, Date().timeIntervalSince(began) / duration)
                let eased = 1 - pow(1 - t, 3)
                offset = start + (target - start) * eased
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled else { return }
            completion?()
            settleTask = nil
        }
    }
}

/// The player in a clipping container that slides it by `offset`, so it can move with the tape without drawing over
/// the toolbar or the queue beside it.
struct TapePlayerView: NSViewRepresentable {
    let player: AVPlayer
    var offset: CGFloat
    var fill = false
    var pictureInPicture: PlayerFullScreen?
    /// The player has drawn the first frame of a new video.
    var onReadyForDisplay: () -> Void

    func makeNSView(context: Context) -> Container {
        let container = Container()
        container.playerView.player = player
        // PlayerControls draws the controls.
        container.playerView.controlsStyle = .none
        container.playerView.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        container.playerView.allowsPictureInPicturePlayback = pictureInPicture != nil
        pictureInPicture?.view = container.playerView
        container.playerView.delegate = pictureInPicture
        container.playerView.pictureInPictureDelegate = pictureInPicture
        container.observation = container.playerView.observe(\.isReadyForDisplay, options: [.new]) { view, _ in
            guard view.isReadyForDisplay else { return }
            DispatchQueue.main.async { container.onReadyForDisplay?() }
        }
        return container
    }

    func updateNSView(_ container: Container, context: Context) {
        if container.playerView.player !== player { container.playerView.player = player }
        container.onReadyForDisplay = onReadyForDisplay
        container.playerView.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        container.offset = offset
    }

    final class Container: NSView {
        let playerView = AVPlayerView()
        var observation: NSKeyValueObservation?
        var onReadyForDisplay: (() -> Void)?
        var offset: CGFloat = 0 {
            didSet { if offset != oldValue { needsLayout = true } }
        }

        override var isFlipped: Bool { true }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            clipsToBounds = true
            addSubview(playerView)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            playerView.frame = bounds.offsetBy(dx: 0, dy: offset)
        }

        // Clicks go to the SwiftUI controls over the video.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Turns two-finger vertical scrolls over its area into a swipe: `changed` with the travel so far (negative is up,
/// following the fingers, so it respects the natural scrolling setting), then `ended` with the travel and velocity
/// (points per second). The momentum scrolling after it is swallowed. A mouse wheel, which has no gesture phases,
/// calls `step` once per notch. Sideways scrolls, and scrolls over a caption long enough to scroll, pass through.
struct ScrollSwipeMonitor: NSViewRepresentable {
    var canBegin: () -> Bool
    var changed: (CGFloat) -> Void
    var ended: (_ travel: CGFloat, _ velocity: CGFloat) -> Void
    var step: (_ up: Bool) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.canBegin = canBegin
        view.changed = changed
        view.ended = ended
        view.step = step
    }

    final class MonitorView: NSView {
        var canBegin: () -> Bool = { false }
        var changed: (CGFloat) -> Void = { _ in }
        var ended: (CGFloat, CGFloat) -> Void = { _, _ in }
        var step: (Bool) -> Void = { _ in }

        private enum State { case idle, deciding, swiping, ignoring }
        private var state = State.idle
        private var travel = CGPoint.zero
        private var velocity: CGFloat = 0
        private var lastChange: TimeInterval = 0
        /// The momentum after a swipe, which would otherwise scroll whatever is under the pointer.
        private var swallowingMomentum = false
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }

        /// Whether the event was used.
        private func handle(_ event: NSEvent) -> Bool {
            if !event.momentumPhase.isEmpty {
                let swallow = swallowingMomentum
                if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                    swallowingMomentum = false
                }
                return swallow
            }
            let phase = event.phase
            if phase.contains(.began) || phase.contains(.mayBegin) {
                swallowingMomentum = false
                travel = .zero
                velocity = 0
                state = isOver(event) ? .deciding : .ignoring
                return state == .deciding
            }
            if phase.contains(.changed) {
                return changed(by: event)
            }
            if phase.contains(.ended) || phase.contains(.cancelled) {
                defer { state = .idle }
                guard state == .swiping else { return state == .deciding }
                // Fingers that stopped before lifting aren't a flick.
                if event.timestamp - lastChange > 0.1 { velocity = 0 }
                swallowingMomentum = true
                ended(travel.y, velocity)
                return true
            }
            // A mouse wheel: no phases.
            if phase.isEmpty, isOver(event), abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), event.scrollingDeltaY != 0 {
                if canBegin() { step(event.scrollingDeltaY < 0) }
                return true
            }
            return false
        }

        private func changed(by event: NSEvent) -> Bool {
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            switch state {
            case .idle, .ignoring:
                return false
            case .deciding:
                travel.x += dx
                travel.y += dy
                if abs(travel.x) > 4 && abs(travel.x) >= abs(travel.y) {
                    state = .ignoring
                } else if abs(travel.y) > 4 {
                    state = canBegin() ? .swiping : .ignoring
                    if state == .swiping {
                        travel.x = 0
                        lastChange = event.timestamp
                        changed(travel.y)
                    }
                }
                return state != .ignoring
            case .swiping:
                travel.y += dy
                let dt = event.timestamp - lastChange
                if dt > 0 { velocity = 0.6 * (dy / dt) + 0.4 * velocity }
                lastChange = event.timestamp
                changed(travel.y)
                return true
            }
        }

        /// Whether the event is over this view and not over a caption that scrolls on its own.
        private func isOver(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, !isHiddenOrHasHiddenAncestor,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            var view = window.contentView?.hitTest(event.locationInWindow)
            while let current = view {
                if let scroll = current as? NSScrollView, let document = scroll.documentView,
                   document.frame.height > scroll.contentView.bounds.height + 1 {
                    return false
                }
                view = current.superview
            }
            return true
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

/// A video's first frame, fitted over black like the player, for the videos sliding in on the tape.
struct VideoStill: View {
    let url: URL
    var fill = false
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                if fill {
                    Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }.clipped()
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }
        }
        .task(id: url) { image = await Self.load(url) }
    }

    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 8
        return cache
    }()

    /// Loads (or returns the cached) first frame. Call it ahead of time so a swipe has it ready.
    @discardableResult
    static func load(_ url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1080, height: 1920)
        guard let (cg, _) = try? await generator.image(at: .zero) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
