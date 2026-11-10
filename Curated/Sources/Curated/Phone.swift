import AppKit
import AVKit
import SwiftUI

/// Phone view: the main window steps aside for a floating phone that plays the loaded queue the way the iPhone app
/// does. Videos fill the screen and a two-finger swipe moves along the tape. The buttons sit on the screen, and the
/// queue slides up from the bottom. The laptop button on the phone brings the window back.
@MainActor
final class PhoneMode {
    static let shared = PhoneMode()

    private var window: NSWindow?
    private weak var desktop: NSWindow?
    private var fullScreenObserver: NSObjectProtocol?
    private var afterFullScreen: (() -> Void)?
    /// The phone's screen height the last time it was resized.
    nonisolated static let heightKey = "phoneScreenHeight"

    var isOn: Bool { window != nil }

    /// Hides `desktop` (leaving full screen first) and puts the phone where it was. `toggleTimeLimit` is the Time Limit
    /// button's action from the loaded Automix, if any.
    func enter(from desktop: NSWindow?, model: AppModel, playback: Playback, toggleTimeLimit: EnvironmentAction?) {
        guard window == nil else { return }
        if let desktop, desktop.styleMask.contains(.fullScreen) {
            // Out of full screen first; then on into the phone.
            afterFullScreen = { [weak self] in
                self?.enter(from: desktop, model: model, playback: playback, toggleTimeLimit: toggleTimeLimit)
            }
            fullScreenObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: desktop, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let observer = self.fullScreenObserver { NotificationCenter.default.removeObserver(observer) }
                    self.fullScreenObserver = nil
                    let next = self.afterFullScreen
                    self.afterFullScreen = nil
                    next?()
                }
            }
            desktop.toggleFullScreen(nil)
            return
        }
        self.desktop = desktop
        let screen = desktop?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // An iPhone's screen in points, or the size it was last resized to, shrunk to fit a short display.
        let frameExtra = 2 * PhoneView.bezel + 2 * PhoneView.margin
        let saved = UserDefaults.standard.double(forKey: Self.heightKey)
        let screenHeight = min(saved > 0 ? saved : 844, visible.height - 40 - frameExtra)
        let screenSize = CGSize(width: (screenHeight * PhoneView.aspect).rounded(), height: screenHeight.rounded())
        let size = CGSize(width: screenSize.width + frameExtra, height: screenSize.height + frameExtra)

        let root = PhoneView(toggleTimeLimit: toggleTimeLimit)
            .environment(model)
            .environment(playback)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = PhoneWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                 backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .managed]
        window.title = "Curated"
        window.contentView = hosting

        // Where the window was, kept on screen.
        let center = desktop.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSPoint(x: visible.midX, y: visible.midY)
        let origin = NSPoint(x: min(max(center.x - size.width / 2, visible.minX), visible.maxX - size.width),
                             y: min(max(center.y - size.height / 2, visible.minY), visible.maxY - size.height))
        window.setFrameOrigin(origin)

        self.window = window
        desktop?.orderOut(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Back to the window.
    func exit() {
        guard let window else { return }
        self.window = nil
        let desktop = desktop ?? NSApp.windows.first { $0.isRestorable && !($0 is PhoneWindow) && $0.contentView != nil }
        desktop?.makeKeyAndOrderFront(nil)
        window.orderOut(nil)
        window.contentView = nil
        window.close()
    }
}

/// Borderless, but it takes the keyboard (so ⌘-shortcuts and the share menu work).
final class PhoneWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - The phone

/// A phone drawn around the screen: a dark bezel with a metal edge, side buttons and the Dynamic Island. Drag the
/// bezel or the status bar to move it.
struct PhoneView: View {
    let toggleTimeLimit: EnvironmentAction?

    static let bezel: CGFloat = 13
    /// Room around the phone for its side buttons and shadow.
    static let margin: CGFloat = 6
    /// An iPhone screen's width to its height.
    static let aspect: CGFloat = 390 / 844

    var body: some View {
        // The screen takes whatever the window's been resized to, inside the bezel.
        GeometryReader { geo in
            let extra = 2 * (Self.bezel + Self.margin)
            phone(CGSize(width: max(0, geo.size.width - extra), height: max(0, geo.size.height - extra)))
        }
    }

    private func phone(_ screenSize: CGSize) -> some View {
        let screenRadius = screenSize.width * 0.135
        return PhoneScreen(screenSize: screenSize, toggleTimeLimit: toggleTimeLimit)
            .frame(width: screenSize.width, height: screenSize.height)
            .clipShape(RoundedRectangle(cornerRadius: screenRadius, style: .continuous))
            .padding(Self.bezel)
            .background {
                let shape = RoundedRectangle(cornerRadius: screenRadius + Self.bezel, style: .continuous)
                ZStack {
                    shape.fill(Color(white: 0.04))
                    // The metal band around the edge.
                    shape.strokeBorder(
                        LinearGradient(colors: [Color(white: 0.55), Color(white: 0.22), Color(white: 0.42), Color(white: 0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 3.5)
                    shape.inset(by: 3.5).strokeBorder(Color.black, lineWidth: 1.5)
                    WindowDragArea()
                }
            }
            .overlay(alignment: .topLeading) {
                // Action button and volume buttons on the left, side button on the right.
                VStack(spacing: 18) {
                    sideButton(height: 30)
                    sideButton(height: 54)
                    sideButton(height: 54)
                }
                .offset(x: -Self.margin + 1.5, y: screenSize.height * 0.2)
            }
            .overlay(alignment: .topTrailing) {
                sideButton(height: 86)
                    .offset(x: Self.margin - 1.5, y: screenSize.height * 0.27)
            }
            .padding(Self.margin)
            // Drag a bottom corner to resize; the phone keeps its shape. The grab area reaches over the screen's
            // rounded corner, but not onto the screen itself.
            .overlay(alignment: .bottomLeading) { resizeCorner(trailing: false, screenRadius: screenRadius) }
            .overlay(alignment: .bottomTrailing) { resizeCorner(trailing: true, screenRadius: screenRadius) }
            .environment(\.colorScheme, .dark)
    }

    /// Size of the square a resize corner takes.
    static let cornerGrab: CGFloat = 60

    private func resizeCorner(trailing: Bool, screenRadius: CGFloat) -> some View {
        // The window lets clicks through where it's clear, so the corners get a fill too faint to see.
        WindowResizeCorner(trailing: trailing, screenRadius: screenRadius)
            .background(Color.black.opacity(0.02))
            .frame(width: Self.cornerGrab, height: Self.cornerGrab)
    }

    private func sideButton(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.25)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 4, height: height)
    }
}

/// Moves the window when dragged.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

/// Resizes the phone's window from a bottom corner, keeping its shape, with the opposite top corner staying put.
/// Remembers the size for next time.
private struct WindowResizeCorner: NSViewRepresentable {
    let trailing: Bool
    let screenRadius: CGFloat

    func makeNSView(context: Context) -> CornerView { CornerView() }
    func updateNSView(_ view: CornerView, context: Context) {
        view.trailing = trailing
        view.screenRadius = screenRadius
        view.window?.invalidateCursorRects(for: view)
    }

    final class CornerView: NSView {
        var trailing = true
        var screenRadius: CGFloat = 0
        private var startFrame = NSRect.zero
        private var startMouse = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// Whether `point` (in this view) is on the phone's screen rather than its frame.
        private func isOnScreen(_ point: NSPoint) -> Bool {
            // Distances in from the phone's outer corner, which is this view's bottom corner.
            let x = trailing ? bounds.maxX - point.x : point.x - bounds.minX
            let y = isFlipped ? bounds.maxY - point.y : point.y - bounds.minY
            let edge = PhoneView.margin + PhoneView.bezel
            guard x > edge, y > edge else { return false }
            // Inside the screen's rounded corner?
            let center = edge + screenRadius
            let dx = max(0, center - x), dy = max(0, center - y)
            return dx * dx + dy * dy < screenRadius * screenRadius
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview, !isOnScreen(convert(point, from: superview)) else { return nil }
            return super.hitTest(point)
        }

        override func resetCursorRects() {
            let cursor: NSCursor
            if #available(macOS 15, *) {
                cursor = .frameResize(position: trailing ? .bottomRight : .bottomLeft, directions: .all)
            } else {
                cursor = .crosshair
            }
            // Only over the frame, row by row, so the cursor doesn't change over the screen.
            let step: CGFloat = 2
            var y = bounds.minY
            while y < bounds.maxY {
                let mid = y + step / 2
                // The frame's part of this row runs from the outer edge to where the screen starts.
                var run: CGFloat = 0
                while run < bounds.width,
                      !isOnScreen(NSPoint(x: trailing ? bounds.maxX - run - 0.5 : bounds.minX + run + 0.5, y: mid)) {
                    run += 1
                }
                addCursorRect(NSRect(x: trailing ? bounds.maxX - run : bounds.minX, y: y, width: run, height: step),
                              cursor: cursor)
                y += step
            }
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startFrame = window.frame
            startMouse = NSEvent.mouseLocation
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let mouse = NSEvent.mouseLocation
            let extra = 2 * (PhoneView.bezel + PhoneView.margin)
            // Follow whichever way the pointer went further, in screen heights.
            let dx = (trailing ? 1 : -1) * (mouse.x - startMouse.x)
            let dy = startMouse.y - mouse.y
            let grow = max(dy, dx / PhoneView.aspect)
            let maxHeight = (window.screen?.visibleFrame.height ?? 2000) - extra
            let screenHeight = min(max(startFrame.height - extra + grow, 300), maxHeight)
            let size = NSSize(width: (screenHeight * PhoneView.aspect).rounded() + extra, height: screenHeight.rounded() + extra)
            let x = trailing ? startFrame.minX : startFrame.maxX - size.width
            window.setFrame(NSRect(x: x, y: startFrame.maxY - size.height, width: size.width, height: size.height),
                            display: true)
        }

        override func mouseUp(with event: NSEvent) {
            guard let window else { return }
            let extra = 2 * (PhoneView.bezel + PhoneView.margin)
            UserDefaults.standard.set(window.frame.height - extra, forKey: PhoneMode.heightKey)
        }
    }
}

/// The phone's screen, laid out as in the iPhone app's player: the status bar, a top bar (the laptop button in place
/// of Back and the title), the Mac player's column of buttons down the right, and at the bottom the creator, caption
/// and scrubber, over a fade.
struct PhoneScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let screenSize: CGSize
    let toggleTimeLimit: EnvironmentAction?
    @State private var showQueue = false
    @State private var captionExpanded = false
    /// Height of the creator, caption and scrubber at the bottom, which the side buttons end above.
    @State private var panelHeight: CGFloat = 0

    /// Height of the status bar, with the Dynamic Island in it.
    private static let statusHeight: CGFloat = 50

    /// Below this screen height the controls shrink with the phone, keeping the layout they have at full size.
    private static let fullSizeHeight: CGFloat = 700

    /// How much the controls are shrunk.
    private var scale: CGFloat { min(1, max(screenSize.height, 1) / Self.fullSizeHeight) }

    var body: some View {
        ZStack {
            Color.black
            if let video = playback.current {
                if video.form == .long {
                    PlayerView(player: playback.player)
                } else {
                    VideoTape(fill: true, swipes: !showQueue)
                }
                // Tap to play or pause, as on the phones.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { playback.togglePlayPause() }
            }

            // Laid out on a full-size screen, then shrunk to fit this one.
            controls
                .frame(width: screenSize.width / scale, height: screenSize.height / scale)
                .scaleEffect(scale)
                .frame(width: screenSize.width, height: screenSize.height)

            // Drag anywhere along the status bar to move the phone.
            WindowDragArea()
                .frame(height: Self.statusHeight * scale)
                .frame(maxHeight: .infinity, alignment: .top)

            if showQueue {
                PhoneQueueSheet(screenHeight: screenSize.height) {
                    withAnimation(.snappy(duration: 0.3)) { showQueue = false }
                }
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onChange(of: playback.current?.id) { captionExpanded = false }
    }

    /// Everything drawn over the video, at full size.
    private var controls: some View {
        ZStack {
            if playback.current != nil {
                if !playback.isPlaying && !playback.finished && !playback.awaitingNext {
                    Image(systemName: "play.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 8)
                        .allowsHitTesting(false)
                }
            } else {
                VStack(spacing: 14) {
                    LogoView(height: 34, forceDark: true).opacity(0.55)
                    Text("Pick a video to start watching").foregroundStyle(.secondary)
                }
            }

            if playback.finished { finishedCard }
            if playback.awaitingNext, let next = playback.upNext {
                UpNextCard(next: next).scaleEffect(0.75)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let video = playback.current, !playback.finished {
                    bottomPanel(video)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                }
            }
            .padding(.top, Self.statusHeight)

            if let video = playback.current {
                // The Mac player's buttons, in a column down the right, ending above the caption.
                VideoSideButtons(video: video)
                    .environment(\.toggleTimeLimit, toggleTimeLimit)
                    .environment(\.toggleUpNext, EnvironmentAction(id: showQueue) {
                        withAnimation(.snappy(duration: 0.3)) { showQueue.toggle() }
                    })
                    .padding(.trailing, 14)
                    .padding(.top, Self.statusHeight + 6)
                    .padding(.bottom, playback.finished ? 22 : panelHeight)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }

            statusBar
        }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            // The Dynamic Island.
            Capsule().fill(.black).frame(width: 118, height: 34)
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 11)
        .frame(height: Self.statusHeight, alignment: .top)
        .shadow(color: .black.opacity(0.4), radius: 3)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    // MARK: Top

    private var topBar: some View {
        HStack(alignment: .top, spacing: 10) {
            PhoneIconButton(symbol: "laptopcomputer", help: "Back to the desktop") { PhoneMode.shared.exit() }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).lineLimit(1)
                if playback.mode?.isOpenMix == true { PhoneQueueSummary() }
            }
            .shadow(radius: playback.timeLimitMinutes != nil ? 0 : 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                // Blue glass while a time-limited mix counts down.
                if playback.timeLimitMinutes != nil {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.clear)
                        .glassCapsule(tint: .accentColor)
                }
            }
            Spacer(minLength: 0)
        }
        // Clear of the side buttons.
        .padding(.trailing, VideoSideButtons.circleSize + 10)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
            .padding(.top, -Self.statusHeight))
    }

    private var title: String {
        func named(_ id: UUID?, _ name: String) -> String {
            [model.category(id)?.name, name].compactMap { $0 }.joined(separator: " ")
        }
        switch playback.mode {
        case .automix(let c, _)?: return named(c, "Automix")
        case .latest(let c)?: return named(c, "Latest")
        case .top(let c, _)?: return named(c, "Top \(PlaybackMode.topCount(c, form: playback.form))")
        case .watchLater?: return "Watch Later"
        case .bookmarks?: return "Bookmarks"
        case .ipod?: return "On iPod"
        case .vineAutomix?: return "Vine Automix"
        case .creator(let username)?:
            return model.library(for: username, form: playback.form)?.displayName ?? "@\(username)"
        case nil: return "Curated"
        }
    }

    // MARK: Bottom

    private func bottomPanel(_ video: Video) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let lib = model.library(for: video.creator, form: video.form) {
                    AvatarView(library: lib, size: 36)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.library(for: video.creator, form: video.form)?.displayName ?? "@\(video.creator)")
                        .font(.headline)
                    Text(positionLabel(video)).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                if let views = video.viewCount {
                    VStack(spacing: 2) {
                        Image(systemName: "eye")
                        Text(views.formatted(.number.notation(.compactName)))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .help("\(views.formatted()) views")
                }
            }
            if video.form == .long && !video.title.isEmpty {
                Text(video.title).font(.headline).lineLimit(2)
            }
            let text = video.form == .long ? video.details : video.caption
            if !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(captionExpanded ? 12 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { captionExpanded.toggle() } }
            }
            PhoneScrubBar(length: duration(of: video))
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, 22)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
    }

    private func duration(of video: Video) -> TimeInterval {
        let item = playback.player.currentItem?.duration.seconds
        return model.duration(of: video) ?? (item?.isFinite == true ? item! : 0)
    }

    private func positionLabel(_ video: Video) -> String {
        var parts = [video.date.formatted(.relative(presentation: .named))]
        let position = playback.index.map { "\($0 + 1) of \(playback.queue.count)" }
        if let minutes = playback.timeLimitMinutes, let position {
            parts.append("\(minutes)-min mix · \(position)")
        } else {
            switch playback.mode {
            case .automix?: parts.append("Automix")
            case .vineAutomix?: parts.append("Vine Automix")
            case .latest?: if let position { parts.append("Latest · \(position)") }
            case .top?, .watchLater?, .bookmarks?, .ipod?: if let position { parts.append(position) }
            default: break
            }
        }
        return parts.joined(separator: " · ")
    }

    private var finishedCard: some View {
        VStack(spacing: 10) {
            if let minutes = playback.timeLimitMinutes {
                Image(systemName: "sun.max.fill").font(.system(size: 44)).foregroundStyle(.yellow)
                Text("Your \(minutes) minutes are up, now enjoy some sunshine!").font(.title3.weight(.semibold))
            } else if let limit = playback.mode?.topLimit(playback.form) {
                Image(systemName: "sun.max.fill").font(.system(size: 44)).foregroundStyle(.yellow)
                Text("You've reached the end, now enjoy some sunshine!").font(.title3.weight(.semibold))
                Text("That's your \(limit) for now.").foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle").font(.system(size: 44))
                Text("You're all caught up").font(.title3.weight(.semibold))
                Text("No unwatched videos left here.").foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(28)
    }
}

/// A round glass button, as on the iPhone app's player.
struct PhoneIconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    static let size: CGFloat = 40

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
                .frame(width: Self.size, height: Self.size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassCircle(tint: tint)
        .help(help)
    }
}

/// "12 unwatched · 23:41 left", as on the phones. Its own view so the ticking clock only redraws this.
private struct PhoneQueueSummary: View {
    @Environment(Playback.self) private var playback

    var body: some View {
        let timeLimited = playback.timeLimitMinutes != nil
        Text("\(playback.unwatched.count) unwatched · \(formatClock(timeLimited ? playback.secondsUntilEnd : playback.unwatchedSecondsLeft)) left")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(timeLimited ? 0.95 : 0.75))
    }
}

/// A thin seek bar that thickens while dragged, with the time over it, as on the phones.
private struct PhoneScrubBar: View {
    @Environment(Playback.self) private var playback
    let length: TimeInterval
    @State private var scrubbing: TimeInterval?
    @State private var wasPlaying = false

    var body: some View {
        let shown = scrubbing ?? playback.currentTime
        let fraction = length > 0 ? min(1, max(0, shown / length)) : 0
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: geometry.size.width * fraction)
            }
            .frame(height: scrubbing == nil ? 3 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard length > 0 else { return }
                        if scrubbing == nil {
                            wasPlaying = playback.isPlaying
                            playback.player.pause()
                        }
                        let time = min(1, max(0, drag.location.x / geometry.size.width)) * length
                        scrubbing = time
                        playback.seek(to: time)
                    }
                    .onEnded { _ in
                        scrubbing = nil
                        if wasPlaying { playback.player.play() }
                    }
            )
        }
        .frame(height: 20)
        .overlay(alignment: .top) {
            if scrubbing != nil {
                Text("\(formatClock(shown)) / \(formatClock(length))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .shadow(radius: 4)
                    .offset(y: -36)
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.15), value: scrubbing == nil)
    }
}

/// Up Next, sliding up from the bottom of the phone like the iPhone app's sheet. Half height at first; drag the grabber
/// up for the full height, or down (or click above it) to put it away.
private struct PhoneQueueSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let screenHeight: CGFloat
    let close: () -> Void
    @State private var large = false
    @State private var drag: CGFloat = 0

    var body: some View {
        let height = large ? screenHeight - 60 : screenHeight * 0.55
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.3)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 6)
                    ZStack {
                        Text("Up Next").font(.headline)
                        HStack {
                            Spacer()
                            Button("Done", action: close)
                                .buttonStyle(.plain)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation.height }
                        .onEnded { value in
                            withAnimation(.snappy(duration: 0.3)) {
                                if value.translation.height < -60 { large = true }
                                drag = 0
                            }
                            if value.translation.height > 60 {
                                if large { withAnimation(.snappy(duration: 0.3)) { large = false } } else { close() }
                            }
                        }
                )
                ScrollViewReader { proxy in
                    List {
                        if playback.form == .long {
                            Toggle("Autoplay", isOn: Binding(get: { playback.autoplayLong }, set: { playback.autoplayLong = $0 }))
                        }
                        ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, video in
                            VideoRow(video: video, isCurrent: playback.current?.id == video.id,
                                     isPlayed: model.isPlayed(video), isSaved: model.isSavedForLater(video),
                                     isBookmarked: model.isBookmarked(video),
                                     creator: playback.mode.map { if case .creator = $0 { false } else { true } } == true
                                        ? model.library(for: video.creator, form: video.form) : nil)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    playback.play(at: index)
                                    close()
                                }
                                .contextMenu { VideoContextMenu(video: video) }
                                .id(video.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        if let id = playback.current?.id { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
            .frame(height: max(120, height - drag))
            .frame(maxWidth: .infinity)
            .background {
                let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                shape.fill(.regularMaterial).overlay(shape.fill(Color(white: 0.1).opacity(0.75)))
            }
            .shadow(color: .black.opacity(0.4), radius: 12)
        }
    }
}
