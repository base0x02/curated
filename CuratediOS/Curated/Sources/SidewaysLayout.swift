import SwiftUI

extension EnvironmentValues {
    /// An iPhone held sideways (SidewaysLayout): Home's bar takes the mix buttons, the mini player gives way to the
    /// tray, and the player sits in the pane beside the screens.
    @Entry var sideways = false
    /// The sideways long-video player's full screen button.
    @Entry var enterLongFullscreen: ViewAction? = nil
    /// How far the sideways player's buttons stand from the right edge of the screen.
    @Entry var sideColumnInset: CGFloat = 14
}

/// An iPhone on its side, as on a Galaxy Fold's cover screen in the Android app: the phone's screens on the left with
/// the tray (SideTray) under them, and the player on the right. Short videos are narrow, so they give the left pane
/// more of the width.
struct SidewaysLayout: View {
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    /// The Dynamic Island (or notch) is down the right edge: the phone's top is turned to the right.
    @State private var islandOnRight = false

    var body: some View {
        @Bindable var router = router
        GeometryReader { geo in
            let fullWidth = geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
            let mode = router.sidePlayer ?? playback.mode
            let paneWidth = min(440, max(320, fullWidth * 0.42))
            // A short video keeps to the left of its pane, full height, with its buttons in the room to its right; the
            // left pane gives up some of its extra width when that room would be too narrow.
            let fullHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            // Sized for an upright short video, so the pane doesn't jump about from one video to the next.
            let shortVideoWidth = fullHeight * 9 / 16
            // The buttons go out into the right-hand margin, clear of the Dynamic Island when it's on that side.
            let trailingInset = geo.safeAreaInsets.trailing
            let columnInset = islandOnRight && trailingInset > 0 ? trailingInset - 4 : 14
            let columnRoom = Self.buttonWidth + columnInset + 6
            let leftWidth = mode?.form == .short
                ? min(paneWidth * 1.35, geo.size.width + trailingInset - shortVideoWidth - columnRoom)
                : min(geo.size.width * 0.7, paneWidth)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    NavigationStack(path: $router.path) {
                        HomeView()
                            .navigationDestination(for: Route.self) { route in
                                switch route {
                                // Players open in the pane on the right (Router.open), not here.
                                case .player: EmptyView()
                                case .creator(let username): CreatorView(username: username)
                                case .gallery(let username): LongCreatorView(username: username)
                                }
                            }
                    }
                    if playback.showsSideTray { SideTray() }
                }
                .frame(width: leftWidth)
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let mode {
                        PlayerScreen(mode: mode).id(mode)
                    } else {
                        Text("Pick a mix or a creator to start watching.")
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(32)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .environment(\.sideColumnInset, columnInset)
            .animation(.snappy, value: mode?.form)
        }
        .onAppear(perform: findIsland)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Turning from one side to the other keeps the window's size, so ask once the turn has settled.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                findIsland()
            }
        }
    }

    private func findIsland() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        // Landscape left: the home indicator's end of the phone on the left, its top on the right.
        islandOnRight = scene?.effectiveGeometry.interfaceOrientation == .landscapeLeft
    }

    /// The player's buttons (PlayerScreen.sideColumn).
    private static let buttonWidth: CGFloat = 40
}

extension Playback {
    /// Whether SideTray has anything to show: a video, and no sunshine panel in its place.
    var showsSideTray: Bool { current != nil && mode != nil && !(finished && endsInSunshine) }
}

/// The bottom of the sideways left pane, in place of the details over the video: picture in picture and the queue; for
/// short videos the progress bar, played, play or pause and next; then the creator, date and caption (a long video's
/// title and description). Dragging it down (or tapping its handle) shrinks it to one row, the creator with play or
/// pause and next, so the creator cards above have room; dragging up opens it again.
struct SideTray: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    @State private var collapsed = false
    @State private var captionExpanded = false

    var body: some View {
        if let video = playback.current, let mode = playback.mode {
            VStack(alignment: .leading, spacing: 4) {
                Button { withAnimation(.snappy) { collapsed.toggle() } } label: {
                    Capsule().fill(.secondary.opacity(0.5)).frame(width: 36, height: 5)
                        .frame(maxWidth: .infinity, minHeight: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? "Show the controls" : "Shrink the controls")
                if collapsed { collapsedRow(video) } else { expanded(video, mode: mode) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, collapsed ? 4 : 8)
            .background { Rectangle().fill(.bar).ignoresSafeArea(edges: [.leading, .bottom]) }
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onEnded { drag in
                    let dy = drag.translation.height
                    guard abs(dy) > abs(drag.translation.width) else { return }
                    if dy > 24 && !collapsed { withAnimation(.snappy) { collapsed = true } }
                    if dy < -24 && collapsed { withAnimation(.snappy) { collapsed = false } }
                }
            )
            .onChange(of: video.id) { captionExpanded = false }
        }
    }

    private func collapsedRow(_ video: Video) -> some View {
        HStack(spacing: 10) {
            AvatarView(username: video.creator, size: 28)
            Text(video.isLong ? video.displayTitle : creatorName(video))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            playPause(size: 22)
            if !video.isLong { nextButton }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder private func expanded(_ video: Video, mode: PlaybackMode) -> some View {
        HStack(spacing: 4) {
            Spacer()
            if playback.canStartPip {
                Button { playback.startPip() } label: { Image(systemName: "pip.enter").frame(width: 40, height: 36) }
                    .accessibilityLabel("Picture in Picture")
            }
            Button { router.queueShown = true } label: { Image(systemName: "list.bullet").frame(width: 40, height: 36) }
                .disabled(playback.queue.isEmpty)
                .accessibilityLabel("Queue")
        }
        .font(.title3)
        .buttonStyle(.plain)
        if !video.isLong {
            if let length = video.duration, length > 0 {
                ScrubBar(length: length, color: .primary)
            }
            HStack(spacing: 32) {
                let played = app.isPlayed(video)
                Button { app.setPlayed(video, !played) } label: {
                    Image(systemName: played ? "checkmark.circle.fill" : "circle").font(.title2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(played ? "Watched. Mark as unwatched" : "Mark as watched")
                playPause(size: 30)
                nextButton
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        HStack(spacing: 10) {
            AvatarView(username: video.creator, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(creatorName(video)).font(.headline).lineLimit(1)
                Text(playback.positionLabel(video, mode: mode)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let views = video.viewCount {
                VStack(spacing: 2) {
                    Image(systemName: "eye")
                    Text(views.formatted(.number.notation(.compactName))).font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(views.formatted(.number.notation(.compactName))) views")
            }
        }
        .padding(.top, 4)
        if video.isLong, let title = video.title, !title.isEmpty {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        let text = video.isLong ? (video.details ?? "") : video.caption
        if !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .lineLimit(captionExpanded ? 8 : 2)
                .onTapGesture { withAnimation(.snappy) { captionExpanded.toggle() } }
        }
    }

    private func playPause(size: CGFloat) -> some View {
        Button { playback.togglePlayPause() } label: {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size))
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(playback.finished)
        .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
    }

    private var nextButton: some View {
        Button { playback.next() } label: {
            Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(playback.finished)
        .accessibilityLabel("Next video")
    }

    private func creatorName(_ video: Video) -> String {
        app.library(video.creator, form: video.isLong ? .long : .short)?.creator.displayName ?? "@\(creatorHandle(video.creator))"
    }
}
