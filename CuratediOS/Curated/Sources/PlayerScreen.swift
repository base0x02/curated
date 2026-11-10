import SwiftUI

struct PlayerScreen: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    /// Beside the screens on an iPhone held sideways (SidewaysLayout): the details, picture in picture, the queue and,
    /// for short videos, the main controls are in the tray on the left, and the rest stand down the right edge.
    @Environment(\.sideways) private var sideways
    @Environment(\.enterLongFullscreen) private var enterLongFullscreen
    @Environment(\.sideColumnInset) private var sideColumnInset
    let mode: PlaybackMode

    @State private var captionExpanded = false
    /// iPhone Duo's outer display: the system sets the toolbar down the side, so the buttons go there.
    @State private var verticalBars = false
    /// How far the video has been dragged up (negative) or down; the controls follow it.
    @State private var dragOffset: CGFloat = 0
    /// iPhone Duo partly folded (its hinge partly open).
    @State private var halfFolded = false
    /// In clear mode, whether a tap has brought the controls up, and touches since (each keeps them up 3 more seconds).
    @State private var revealed = false
    @State private var touches = 0

    private var build: (() -> [Video])? {
        if mode.creatorUsername != nil { return nil }
        return { [app, mode] in Queues.build(mode, app) }
    }

    private var isLoaded: Bool { playback.mode == mode }
    private var isTimeLimited: Bool { isLoaded && playback.timeLimitMinutes != nil }
    private var nothingUnplayed: Bool { app.libraries(in: nil, form: mode.form).allSatisfy { app.unplayedCount($0) == 0 } }
    /// Automix can be cut to a time budget: long-press its title or the queue button, or use the queue sheet's button.
    private var canTimeLimit: Bool { mode.isAutomix && build != nil && (!nothingUnplayed || isTimeLimited) }
    /// Clear mode hides the controls over a short video (not sideways, where they're beside it).
    private var clear: Bool { playback.clearMode && !sideways && !verticalBars }
    private var controlsShown: Bool { !clear || revealed }

    /// Starts a time-limited Automix, or ends one and goes back to the full mix.
    private func toggleTimeLimit() {
        guard let build, canTimeLimit else { return }
        if isTimeLimited {
            playback.continueWith(build(), mode: mode)
        } else {
            let minutes = app.timeLimitMinutes
            playback.start(Queues.limit(build(), toSeconds: Double(minutes * 60)), mode: mode, timeLimitMinutes: minutes)
        }
    }

    /// A long video is loaded here: it plays in the stock player, not the swipeable one.
    private var longVideo: Video? { isLoaded ? playback.current.flatMap { $0.isLong ? $0 : nil } : nil }

    var body: some View {
        @Bindable var router = router
        return Group {
            if let video = longVideo { if sideways { sidewaysLongBody(video) } else { longBody(video) } } else { shortBody }
        }
        .toolbar(verticalBars ? .visible : .hidden, for: .navigationBar)
        .modifier(SideToolbar(enabled: verticalBars, showQueue: { router.queueShown = true }) { sideMixItems })
        .modifier(VerticalBarsReader(vertical: $verticalBars))
        .background { HingeReader(halfOpen: $halfFolded) }
        // Dark glass for the toolbar down the side, which UIKit draws from the window's light/dark setting.
        .background { if verticalBars { DarkWindow() } }
        .persistentSystemOverlays(.hidden)
        .environment(\.colorScheme, .dark)
        .task(id: mode) {
            // Rebuild if another queue is loaded, or this one was empty (e.g. new videos since).
            if let build, playback.mode != mode || playback.queue.isEmpty { playback.start(build(), mode: mode) }
        }
        .onDisappear {
            // Going back pauses; the video stays in the mini player. Rotating an iPad into the wide layout also
            // removes this screen, but leaves it in the path, and the video keeps playing there. Sideways, the pane only
            // swaps one queue for another, or the phone turned upright and the player moved into the path.
            // Turning the phone sideways also removes the upright player, before the layout has moved it into the side
            // pane (and the path still says nothing), so this looks again once the turn has been handled.
            guard !sideways else { return }
            let playback = playback, router = router, mode = mode
            DispatchQueue.main.async {
                if !router.sideways && !playback.isPipActive && !router.path.contains(.player(mode)) {
                    Diagnostics.log("Paused: the player was closed")
                    playback.pause()
                }
            }
        }
        .sheet(isPresented: $router.queueShown) {
            QueueSheet(mode: mode, timeLimited: isTimeLimited, toggleTimeLimit: canTimeLimit ? toggleTimeLimit : nil)
        }
    }

    /// A long video: the top bar, the video in Apple's player (its controls skip 10 seconds, scrub and go full
    /// screen), then the title, description and the video's own buttons. iPhone Duo partly folded and upright: the
    /// top bar and video above the fold, the rest below it.
    private func longBody(_ video: Video) -> some View {
        let sunshine = playback.finished && playback.endsInSunshine
        return ZStack {
            Color.black.ignoresSafeArea()
            // The sunshine panel fills the screen, under the top bar; the caught-up card sits on the video.
            if sunshine { FinishedCard() }
            GeometryReader { geo in
                let insets = geo.safeAreaInsets
                // UIHinge doesn't say where the hinge is: it's taken to cross the middle of the window.
                let fold = (insets.top + geo.size.height + insets.bottom) / 2 - insets.top
                if halfFolded && geo.size.height > geo.size.width {
                    VStack(spacing: 0) {
                        // The whole top half, up under the status bar, as big as full screen makes it.
                        longPlayer(showsControls: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .frame(height: max(0, insets.top + fold - Self.creaseMargin))
                            .padding(.top, -insets.top)
                        // Below the fold: the top bar, then at the bottom the playback controls and the description.
                        VStack(spacing: 0) {
                            topBar
                            Spacer(minLength: 0)
                            if !sunshine {
                                transport(video)
                                bottomPanel(video, tabletop: true)
                            }
                        }
                        .padding(.top, Self.creaseMargin)
                    }
                } else {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 0)
                        // An iPhone upright: our own player, whose full screen is held sideways (LongFullscreen);
                        // elsewhere (iPad, iPhone Duo's inner display) the stock one.
                        if let enterLongFullscreen {
                            LongVideoPlayer(fullscreen: false, toggleFullscreen: enterLongFullscreen.callAsFunction)
                                .aspectRatio(playback.videoAspect ?? 16 / 9, contentMode: .fit)
                                .opacity(sunshine ? 0 : 1)
                        } else {
                            longPlayer()
                        }
                        Spacer(minLength: 0)
                        if !sunshine { bottomPanel(video) }
                    }
                }
            }
        }
        .animation(.snappy, value: halfFolded)
    }

    /// Room kept clear either side of the fold, where the screen bends.
    private static let creaseMargin: CGFloat = 12

    private func longPlayer(showsControls: Bool = true) -> some View {
        StockPlayerView(playback: playback, showsControls: showsControls)
            .aspectRatio(playback.videoAspect ?? 16 / 9, contentMode: .fit)
            .overlay {
                if playback.finished && !playback.endsInSunshine { FinishedCard() }
                if playback.awaitingNext, let next = playback.upNext { UpNextCard(next: next) }
            }
            .opacity(playback.finished && playback.endsInSunshine ? 0 : 1)
    }

    private var shortBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if playback.current != nil {
                VideoBackdrop(playback: playback)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            // Beside a toolbar down the side (iPhone Duo's, or the sideways pane's buttons), the video keeps to the
            // left and leaves the room on the right to them.
            SwipeableVideo(dragOffset: $dragOffset, enabled: isLoaded, leading: verticalBars || sideways,
                           onTap: controlsShown ? nil : { revealed = true })
                .ignoresSafeArea()

            if !isLoaded || playback.queue.isEmpty {
                Text(emptyText)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(32)
            } else if !playback.isPlaying && !playback.finished && !playback.awaitingNext && playback.current != nil {
                Image(systemName: "play.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(radius: 8)
                    .offset(y: dragOffset)
                    .allowsHitTesting(false)
            }

            if playback.isHoldingFast {
                Label("2×", systemImage: "forward.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .glassBackground(in: Capsule())
                    .allowsHitTesting(false)
            }

            if playback.finished && isLoaded { FinishedCard() }
            if playback.awaitingNext && isLoaded, let next = playback.upNext { UpNextCard(next: next) }

            if controlsShown {
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if !sideways, let video = playback.current, isLoaded, !(playback.finished && playback.endsInSunshine) {
                        bottomPanel(video).offset(y: dragOffset)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsShown)
        // Any touch while the controls are up in clear mode keeps them up for another 3 seconds.
        .simultaneousGesture(TapGesture().onEnded { if clear && revealed { touches += 1 } })
        .task(id: [clear, revealed, touches] as [AnyHashable]) {
            guard clear, revealed else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { revealed = false }
        }
        .onChange(of: playback.clearMode) { revealed = false }
        .statusBarHidden(clear && !revealed)
        .overlay(alignment: .trailing) {
            if controlsShown, let video = playback.current, isLoaded, !(playback.finished && playback.endsInSunshine) {
                if sideways {
                    sideColumn(video)
                } else if !verticalBars {
                    // Midway down the right edge, as on the Mac and the Duo, below the queue and autoplay at the top.
                    videoButtons(video)
                        .padding(.trailing, 16)
                        .offset(y: dragOffset)
                }
            }
        }
    }

    // MARK: Sideways

    /// A long video beside the tray: the video, then back 10 seconds, play or pause, ahead 10 and full screen above
    /// a thin progress bar along the bottom, and the video's buttons down the right edge.
    private func sidewaysLongBody(_ video: Video) -> some View {
        let sunshine = playback.finished && playback.endsInSunshine
        return ZStack {
            Color.black.ignoresSafeArea()
            if sunshine { FinishedCard() }
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                // Its own layer rather than the stock player, so picture in picture starts from the tray's button.
                VideoSurface(playback: playback)
                    .aspectRatio(playback.videoAspect ?? 16 / 9, contentMode: .fit)
                    .contentShape(Rectangle())
                    .onTapGesture { playback.togglePlayPause() }
                    .overlay {
                        if playback.finished && !sunshine { FinishedCard() }
                        if playback.awaitingNext, let next = playback.upNext { UpNextCard(next: next) }
                    }
                    .opacity(sunshine ? 0 : 1)
                    .accessibilityLabel("Video")
                Spacer(minLength: 0)
                if !sunshine {
                    VStack(spacing: 2) {
                        HStack {
                            // Balances the full screen button, so the three in the middle are centered.
                            Color.clear.frame(width: 44, height: 44)
                            Spacer()
                            Button { playback.seek(to: max(0, playback.position - 10)) } label: {
                                Image(systemName: "gobackward.10").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Back 10 seconds")
                            Button { playback.togglePlayPause() } label: {
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 34))
                                    .frame(width: 60, height: 48)
                            }
                            .disabled(playback.finished)
                            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                            Button {
                                let length = video.duration ?? 0
                                playback.seek(to: length > 0 ? min(length, playback.position + 10) : playback.position + 10)
                            } label: {
                                Image(systemName: "goforward.10").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Ahead 10 seconds")
                            Spacer()
                            Button { enterLongFullscreen?() } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Full Screen")
                        }
                        .font(.system(size: 22, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        if let length = video.duration, length > 0 { ScrubBar(length: length) }
                    }
                    // Clear of the buttons down the right edge.
                    .padding(.leading, 12)
                    .padding(.trailing, 64)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea())
                }
            }
        }
        .overlay(alignment: .trailing) { if !sunshine { sideColumn(video) } }
    }

    /// The buttons down the right edge: the mix's own (autoplay for long videos, Time Limit for Automix), then the
    /// video's: autoplay (short videos; played for long ones, whose played toggle isn't in the tray), speed, Watch
    /// Later, bookmark and share.
    private func sideColumn(_ video: Video) -> some View {
        VStack(spacing: 12) {
            mixButtons
            if video.isLong {
                let played = app.isPlayed(video)
                GlassIconButton(symbol: played ? "checkmark.circle.fill" : "circle",
                                label: played ? "Watched. Mark as unwatched" : "Mark as watched") {
                    app.setPlayed(video, !played)
                }
            } else {
                ShortAutoplayButton()
            }
            Button { playback.cycleSpeed() } label: {
                Text(formatSpeed(playback.shownSpeed))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed \(formatSpeed(playback.shownSpeed))")
            .speedLock(playback.speedLocked)
            GlassIconButton(symbol: "tray.and.arrow.down", label: "Watch Later") { playback.saveForLater() }
                .disabled(playback.finished)
            let bookmarked = app.isBookmarked(video)
            GlassIconButton(symbol: bookmarked ? "bookmark.fill" : "bookmark", label: bookmarked ? "Bookmarked. Remove bookmark" : "Bookmark") {
                playback.toggleBookmark()
            }
            ShareLink(item: app.store.videoFile(video)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")
        }
        // Out into the margin the system keeps down the right, as far as the Dynamic Island allows.
        .padding(.trailing, sideColumnInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .ignoresSafeArea(edges: .trailing)
    }

    // MARK: Top

    private var topBar: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                // With the toolbar down the side, the system's Back button and the toolbar's items replace these.
                // Sideways, the screens beside the player have Back.
                if !verticalBars && !sideways {
                    GlassIconButton(symbol: "chevron.left", label: "Back") { dismiss() }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline).lineLimit(1)
                    if mode.isOpenMix && isLoaded { QueueSummary() }
                }
                .foregroundStyle(.white)
                .shadow(radius: isTimeLimited ? 0 : 4)
                // Turns to blue glass while a time-limited mix counts down. The padding stays so the text doesn't jump.
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .modifier(TimeLimitGlass(active: isTimeLimited))
                .contentShape(Rectangle())
                .onLongPressGesture { toggleTimeLimit() }
                .sensoryFeedback(.impact, trigger: playback.timeLimitMinutes)
                .accessibilityElement(children: .combine)
                .modifier(TimeLimitAction(enabled: canTimeLimit, timeLimited: isTimeLimited, minutes: app.timeLimitMinutes, action: toggleTimeLimit))
                Spacer()
                // One column of same-size buttons down the right: Queue (long-press for Time Limit in Automix),
                // autoplay, clear mode (short videos), picture in picture.
                if !verticalBars {
                    VStack(spacing: 10) {
                        // Sideways, the queue and picture in picture are in the tray, and autoplay is down the side.
                        if !sideways {
                            GlassIconButton(symbol: "list.bullet", label: "Queue",
                                            longPress: canTimeLimit ? toggleTimeLimit : nil) { router.queueShown = true }
                                .disabled(!isLoaded || playback.queue.isEmpty)
                                .modifier(TimeLimitAction(enabled: canTimeLimit, timeLimited: isTimeLimited, minutes: app.timeLimitMinutes, action: toggleTimeLimit))
                        }
                        if mode.form == .short && !sideways { ShortAutoplayButton() }
                        // Long videos: play the next one when a video ends, or not. Filled while it's on.
                        // Sideways, these head the column of buttons down the right edge instead.
                        if !sideways { mixButtons }
                        // Clear mode: hide everything over the video until it's tapped.
                        if mode.form == .short && !sideways {
                            GlassIconButton(symbol: playback.clearMode ? "eye.slash.fill" : "eye.slash",
                                            label: playback.clearMode ? "Clear mode is on. Keep the controls up" : "Clear mode: hide the controls until you tap the video",
                                            tint: playback.clearMode ? .accentColor : nil) {
                                playback.clearMode.toggle()
                            }
                        }
                        if playback.canStartPip && !sideways {
                            GlassIconButton(symbol: "pip.enter", label: "Picture in Picture") { playback.startPip() }
                        }
                    }
                }
            }
            // Top lists and Watch Later keep a way to rebuild. The open mixes have none: they build a fresh queue at
            // launch and whenever they open after another queue.
            if let build, !mode.isOpenMix, !verticalBars {
                Button {
                    playback.start(build(), mode: mode)
                } label: {
                    Label(mode.topLimit == nil ? "Refresh" : "New List", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassChipStyle(selected: false))
                .disabled(nothingUnplayed && !mode.isBookmarks)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    /// Long videos' autoplay, filled while it's on. (Automix's Time Limit is a long press on the title or the queue button.)
    @ViewBuilder private var mixButtons: some View {
        if mode.form == .long {
            GlassIconButton(symbol: "play.square.stack", label: "", tint: app.autoplayLong ? .accentColor : nil) {
                app.autoplayLong.toggle()
            }
            .accessibilityLabel(app.autoplayLong ? "Autoplay is on" : "Autoplay is off")
            .accessibilityAddTraits(app.autoplayLong ? .isSelected : [])
        }
    }

    /// New List or Refresh for the lists, as toolbar items down the side. (Automix's Time Limit is a long press on the
    /// title, or the queue sheet's button.)
    @ViewBuilder private var sideMixItems: some View {
        if let build {
            if !mode.isOpenMix {
                Button { playback.start(build(), mode: mode) } label: {
                    Label(mode.topLimit == nil ? "Refresh" : "New List", systemImage: "arrow.clockwise")
                }
                .disabled(nothingUnplayed && !mode.isBookmarks)
            }
        }
        if mode.form == .short { ShortAutoplayItem() }
        if mode.form == .long {
            Button { app.autoplayLong.toggle() } label: {
                Label(app.autoplayLong ? "Autoplay is on" : "Autoplay is off",
                      systemImage: app.autoplayLong ? "play.square.stack.fill" : "play.square.stack")
            }
        }
    }

    private var title: String {
        switch mode {
        case .automix(let c, _): [app.category(c)?.name, "Automix"].compactMap { $0 }.joined(separator: " ")
        case .top(let c, _): [app.category(c)?.name, "Top \(PlaybackMode.topCount(c))"].compactMap { $0 }.joined(separator: " ")
        case .watchLater, .longWatchLater: "Watch Later"
        case .bookmarks, .longBookmarks: "Bookmarks"
        case .creator(let u): app.library(u)?.creator.displayName ?? "@\(creatorHandle(u))"
        case .longCreator(let u): app.library(u, form: .long)?.creator.displayName ?? "@\(creatorHandle(u))"
        case .latest(let c): [app.category(c)?.name, "Latest"].compactMap { $0 }.joined(separator: " ")
        case .longAutomix(let c, _): [app.category(c)?.name, "Automix"].compactMap { $0 }.joined(separator: " ")
        case .vineAutomix: "Vine Automix"
        }
    }

    private var emptyText: String {
        if case .latest = mode { return "No unwatched long videos. Check back after the next sync." }
        if case .top = mode { return "No unwatched videos right now. Check back after the next sync." }
        if mode == .watchLater || mode == .longWatchLater { return "Nothing saved. Use the Watch Later button in the player to set a video aside for later." }
        if mode.isBookmarks { return "No bookmarks. Use the bookmark button in the player to keep a video; bookmarked videos stay out of Automix and aren't deleted automatically." }
        return "No unwatched videos. Automix alternates between creators' unwatched videos. Check back after the next sync."
    }

    // MARK: Bottom

    /// iPhone Duo partly folded, where the video has no controls of its own: a seek bar with the time either side,
    /// then back 10 seconds, play or pause, and ahead 10 seconds.
    private func transport(_ video: Video) -> some View {
        let length = video.duration ?? 0
        return VStack(spacing: 8) {
            if length > 0 {
                ScrubBar(length: length)
                HStack {
                    Text(formatClock(playback.position))
                    Spacer()
                    Text("-" + formatClock(max(0, length - playback.position)))
                }
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
            }
            HStack(spacing: 48) {
                Button { playback.seek(to: max(0, playback.position - 10)) } label: {
                    Image(systemName: "gobackward.10")
                }
                .accessibilityLabel("Back 10 seconds")
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                        .frame(width: 56, height: 56)
                }
                .disabled(playback.finished)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                Button { playback.seek(to: length > 0 ? min(length, playback.position + 10) : playback.position + 10) } label: {
                    Image(systemName: "goforward.10")
                }
                .accessibilityLabel("Ahead 10 seconds")
            }
            .font(.system(size: 28, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// The creator, title, description and buttons. `tabletop`: below the fold of a partly folded iPhone Duo, with room
    /// for more of the description and no fade over the video.
    private func bottomPanel(_ video: Video, tabletop: Bool = false) -> some View {
        // Short videos: the video's buttons stand midway down the right edge instead (see shortBody).
        let column = !video.isLong && !verticalBars
        return VStack(alignment: .leading, spacing: 10) {
            details(video, tabletop: tabletop)
            // Long videos scrub in the stock player's own controls.
            if let length = video.duration, length > 0, !video.isLong {
                ScrubBar(length: length)
            }
            if !verticalBars && !column { controls(video) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, tabletop ? 0 : 40)
        .padding(.bottom, 8)
        .background {
            if !tabletop {
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
        }
        .onChange(of: video.id) { captionExpanded = false }
    }

    private func details(_ video: Video, tabletop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(username: video.creator, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.library(video.creator, form: video.isLong ? .long : .short)?.creator.displayName
                         ?? "@\(creatorHandle(video.creator))").font(.headline)
                    Text(playback.positionLabel(video, mode: mode)).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                if let views = video.viewCount {
                    VStack(spacing: 2) {
                        Image(systemName: "eye")
                        Text(views.formatted(.number.notation(.compactName)))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(views.formatted(.number.notation(.compactName))) views")
                }
            }
            // Long videos: the title, then the description (tap for more).
            if video.isLong, let title = video.title, !title.isEmpty {
                Text(title).font(.headline).lineLimit(2)
            }
            let text = video.isLong ? (video.details ?? "") : video.caption
            if !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(captionExpanded ? 12 : tabletop ? 6 : 2)
                    .onTapGesture { withAnimation(.snappy) { captionExpanded.toggle() } }
            }
        }
    }

    /// Short videos' buttons, in the Mac's order: share, speed, then Watch Later, bookmark and played together in a pill.
    /// (Queue, autoplay and Time Limit head the column at the top.)
    private func videoButtons(_ video: Video) -> some View {
        let saved = app.isSavedForLater(video)
        let bookmarked = app.isBookmarked(video)
        let played = app.isPlayed(video)
        return VStack(spacing: 12) {
            ShareLink(item: app.store.videoFile(video)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Share")
            Button { playback.cycleSpeed() } label: {
                Text(formatSpeed(playback.shownSpeed))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 40, height: 40)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Playback speed \(formatSpeed(playback.shownSpeed))")
            .speedLock(playback.speedLocked)
            VStack(spacing: 0) {
                Button {
                    if saved { app.setWatchLater([video], false) } else { playback.saveForLater() }
                } label: { pillIcon(saved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down") }
                    .disabled(playback.finished && !saved)
                    .accessibilityLabel(saved ? "In Watch Later. Remove from Watch Later" : "Watch Later")
                Button { playback.toggleBookmark() } label: { pillIcon(bookmarked ? "bookmark.fill" : "bookmark") }
                    .accessibilityLabel(bookmarked ? "Bookmarked. Remove bookmark" : "Bookmark")
                Button { app.setPlayed(video, !played) } label: { pillIcon(played ? "checkmark.circle.fill" : "circle") }
                    .accessibilityLabel(played ? "Watched. Mark as unwatched" : "Mark as watched")
            }
            .padding(.vertical, 4)
            .glassBackground(in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func pillIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .frame(width: 40, height: 38)
            .contentShape(Rectangle())
    }

    private func controls(_ video: Video) -> some View {
        let played = app.isPlayed(video)
        return HStack(spacing: 22) {
            Button {
                app.setPlayed(video, !played)
            } label: {
                Image(systemName: played ? "checkmark.circle.fill" : "circle")
            }
            .accessibilityLabel(played ? "Watched. Mark as unwatched" : "Mark as watched")
            Spacer()
            Button { playback.cycleSpeed() } label: {
                Text(formatSpeed(playback.shownSpeed)).font(.subheadline.weight(.semibold)).monospacedDigit().frame(minWidth: 34)
            }
            .accessibilityLabel("Playback speed \(formatSpeed(playback.shownSpeed))")
            .speedLock(playback.speedLocked)
            Button { playback.saveForLater() } label: { Image(systemName: "tray.and.arrow.down") }
                .disabled(playback.finished)
                .accessibilityLabel("Watch Later")
            BookmarkButton(video: video)
            ShareLink(item: app.store.videoFile(video)) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
        }
        .font(.title2)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

}

extension Playback {
    /// When the video is from and where it is in the queue: "2 days ago · Automix", "Latest · 3 of 12".
    func positionLabel(_ video: Video, mode: PlaybackMode) -> String {
        let i = index ?? 0
        var parts = [video.date.formatted(.relative(presentation: .named))]
        if let minutes = timeLimitMinutes {
            parts.append("\(minutes)-min mix · \(i + 1) of \(queue.count)")
        } else if mode == .vineAutomix {
            parts.append("Vine Automix")
        } else if mode.isAnyAutomix {
            parts.append("Automix")
        } else if case .latest = mode {
            parts.append("Latest · \(i + 1) of \(queue.count)")
        } else if mode.topLimit != nil || mode.creatorUsername == nil {
            parts.append("\(i + 1) of \(queue.count)")
        }
        return parts.joined(separator: " · ")
    }
}

/// "12 unwatched · 23:41 left". Its own view so the ticking clock only redraws this.
struct QueueSummary: View {
    @Environment(Playback.self) private var playback

    var body: some View {
        Group {
            if playback.timeLimitMinutes != nil {
                // A time-limited mix counts down to its end.
                if playback.finished {
                    Text("Time's up")
                } else {
                    Text("\(playback.unwatched.count) unwatched · \(formatClock(playback.secondsUntilEnd)) left")
                        .contentTransition(.numericText(countsDown: true))
                }
            } else {
                Text("\(playback.unwatched.count) unwatched · \(formatClock(playback.unwatchedSecondsLeft)) left")
            }
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.white.opacity(playback.timeLimitMinutes != nil ? 0.95 : 0.75))
    }
}

/// The blue glass behind the title while a time-limited mix runs.
struct TimeLimitGlass: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous), tint: .accentColor.opacity(0.6))
        } else {
            content
        }
    }
}

/// The end of the queue: the sunshine panel after a time-limited or Top mix or a creator's videos, filling the space
/// it's given; otherwise a "You're all caught up" card.
struct FinishedCard: View {
    @Environment(Playback.self) private var playback

    var body: some View {
        if let minutes = playback.timeLimitMinutes {
            SunshinePanel(headline: "Your \(minutes) minutes are up")
        } else if playback.endsInSunshine {
            SunshinePanel(headline: "You've reached the end")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle").font(.system(size: 48))
                Text("You're all caught up").font(.title2.weight(.semibold))
                Text("No unwatched videos left here.").foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(28)
            .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(32)
        }
    }
}

private struct QueueSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(\.dismiss) private var dismiss
    let mode: PlaybackMode
    var timeLimited = false
    /// Automix: start or end a time-limited mix.
    var toggleTimeLimit: (() -> Void)?

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    // Long videos: the autoplay switch at the top of Up Next.
                    if mode.form == .long {
                        Toggle("Autoplay", isOn: $app.autoplayLong)
                    }
                    ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, video in
                        Button {
                            playback.play(at: index)
                            dismiss()
                        } label: {
                            let showCreator = mode.creatorUsername == nil
                            if video.isLong {
                                LongVideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: showCreator)
                            } else {
                                VideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: showCreator)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(video.id)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let id = playback.current?.id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let toggleTimeLimit {
                    ToolbarItem(placement: .cancellationAction) {
                        TimeLimitToolbarButton(timeLimited: timeLimited) {
                            toggleTimeLimit()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The queue sheet's Time Limit: the timer alone, on the left of the Done row; filled while a time-limited mix runs.
struct TimeLimitToolbarButton: View {
    let timeLimited: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: timeLimited ? "timer.circle.fill" : "timer")
        }
        .accessibilityLabel(timeLimited ? "End the time-limited mix" : "Time Limit")
        .accessibilityAddTraits(timeLimited ? .isSelected : [])
    }
}

struct GlassIconButton: View {
    let symbol: String
    let label: String
    var tint: Color?
    /// An image from the asset catalog in place of `symbol` (a template, drawn like a symbol).
    var asset: String?
    /// A second action on a long press (then a tap and a long press are told apart, which a Button can't do).
    var longPress: (() -> Void)?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if let longPress {
            glyph
                .contentShape(Circle())
                .onTapGesture(perform: action)
                .onLongPressGesture(perform: longPress)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(label)
        } else {
            Button(action: action) { glyph }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        }
    }

    private var glyph: some View {
        Group {
            if let asset {
                Image(asset).resizable().scaledToFit().frame(width: 20, height: 20)
            } else {
                Image(systemName: symbol)
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
        .frame(width: 40, height: 40)
        .glassBackground(in: Circle(), interactive: true, tint: tint)
    }
}

/// Time Limit as a VoiceOver action, for the long presses that start and end it.
struct TimeLimitAction: ViewModifier {
    let enabled: Bool
    let timeLimited: Bool
    let minutes: Int
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: timeLimited ? "End the time-limited mix" : "Time Limit: a \(minutes)-minute mix", action)
        } else {
            content
        }
    }
}

/// Short videos: on to the next one when a video ends, or play it on a loop. The glyph shows which: an arrow with a
/// dashed stem while autoplay is on, slashed while it's off.
struct ShortAutoplayButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GlassIconButton(symbol: "", label: "", asset: app.autoplayShort ? "AutoplayOn" : "AutoplayOff") {
            app.autoplayShort.toggle()
        }
        .accessibilityLabel(app.autoplayShort ? "Autoplay is on" : "Autoplay is off, videos loop")
        .accessibilityHint(app.autoplayShort ? "Plays each video on a loop" : "Goes on to the next video when one ends")
    }
}

/// The same, as a toolbar item (iPhone Duo's side toolbars), with a title for the overflow menu.
struct ShortAutoplayItem: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button { app.autoplayShort.toggle() } label: {
            Label { Text(app.autoplayShort ? "Autoplay is on" : "Autoplay is off") } icon: {
                Image(app.autoplayShort ? "AutoplayOn" : "AutoplayOff")
            }
        }
    }
}

struct GlassChipStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassBackground(in: Capsule(), interactive: true, tint: selected ? .accentColor : nil)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// The playing video and, during a swipe, the one sliding in above or below it, under a layer that takes the
/// gestures: tap to pause, hold for 2×, swipe up for the next video and down for the previous one. Shared by the
/// full-screen player and the wide layout's player.
struct SwipeableVideo: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    /// How far the video has been dragged up (negative) or down; the neighbor slides in alongside it.
    @Binding var dragOffset: CGFloat
    /// Off while the queue on screen isn't the one playing.
    var enabled = true
    /// Against the leading edge instead of centered, beside iPhone Duo's toolbar down the side (or the sideways
    /// player's column of buttons).
    var leading = false
    /// Replaces tap to pause, e.g. to bring back the controls in clear mode.
    var onTap: (() -> Void)?

    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    /// Set once a touch moves far enough vertically to be a swipe rather than a tap or hold.
    @State private var isSwiping = false
    @State private var screenHeight: CGFloat = 800
    /// The video whose first frame covers the player after a swipe, until the player draws it.
    @State private var coverID: String?

    var body: some View {
        ZStack {
            videoStack
            gestureLayer
        }
        .task(id: playback.upNext?.id) {
            // Have the next video's first frame ready before a swipe starts.
            if let next = playback.upNext { await VideoStill.load(app.store.videoFile(next)) }
        }
        .onChange(of: playback.startedID) { _, id in
            // The player layer only reports the first video's first frame; later ones count once they're playing.
            if id == coverID { coverID = nil }
        }
    }

    /// The playing video and, during a swipe, the one sliding in above or below it. Both follow the finger.
    private var videoStack: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = leading ? min(geo.size.width, height * (playback.videoAspect ?? 9 / 16)) : geo.size.width
            ZStack {
                if dragOffset < 0, let next = playback.upNext {
                    VideoStill(url: app.store.videoFile(next)).offset(y: height + dragOffset)
                } else if dragOffset > 0, let previous = playback.previousVideo {
                    VideoStill(url: app.store.videoFile(previous)).offset(y: -height + dragOffset)
                }
                ZStack {
                    VideoSurface(playback: playback, onReadyForDisplay: { coverID = nil })
                    if let current = playback.current, coverID == current.id {
                        VideoStill(url: app.store.videoFile(current))
                    }
                }
                .offset(y: dragOffset)
            }
            .frame(width: width, height: height)  // At the leading edge (the reader's origin) when narrowed.
            .onAppear { screenHeight = height }
            .onChange(of: height) { _, newHeight in screenHeight = newHeight }
        }
    }

    /// Tap to pause, hold for 2×, swipe up for the next video and down for the previous one.
    private var gestureLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressStart == nil {
                            pressStart = Date()
                            holdTask = Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                if !Task.isCancelled { playback.holdFast(true) }
                            }
                        }
                        if abs(value.translation.height) > 20 || abs(value.translation.width) > 20 { holdTask?.cancel() }
                        let dy = value.translation.height
                        if !isSwiping, !playback.isHoldingFast, enabled, playback.current != nil,
                           abs(dy) > 10, abs(dy) > abs(value.translation.width) {
                            isSwiping = true
                        }
                        if isSwiping { dragOffset = followFinger(dy) }
                    }
                    .onEnded { value in
                        holdTask?.cancel()
                        pressStart = nil
                        if playback.isHoldingFast {
                            playback.holdFast(false)
                        } else if isSwiping {
                            endSwipe(value)
                        } else if abs(value.translation.height) < 12 && abs(value.translation.width) < 12 {
                            if let onTap { onTap() } else { playback.togglePlayPause() }
                        }
                        isSwiping = false
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("Video")
            .accessibilityHint("Double-tap to play or pause")
            .accessibilityAction(named: "Next video") { playback.next() }
            .accessibilityAction(named: "Previous video") { playback.previous() }
            .accessibilityIdentifier("videoSurface")
    }

    /// The video tracks the finger, with rubber-band resistance where there's nothing to slide in.
    private func followFinger(_ dy: CGFloat) -> CGFloat {
        let hasNeighbor = dy < 0 ? playback.upNext != nil : playback.previousVideo != nil
        return hasNeighbor ? max(-screenHeight, min(screenHeight, dy)) : dy / 4
    }

    /// Past an eighth of the screen, or flicked, the neighbor finishes sliding in and plays; otherwise it springs back.
    private func endSwipe(_ value: DragGesture.Value) {
        let dy = value.translation.height
        let predicted = value.predictedEndTranslation.height
        let speed = value.velocity.height
        let goingUp = dy < 0
        let flicked = (abs(speed) > 250 && (speed < 0) == goingUp)
            || (abs(predicted) > screenHeight * 0.3 && (predicted < 0) == goingUp)
        let committed = abs(dy) > screenHeight * 0.12 || flicked
        let incoming = goingUp ? playback.upNext : playback.previousVideo
        guard committed, incoming != nil else {
            // Swiping up past the last video still finishes the mix, as before.
            if committed && goingUp { playback.next() }
            withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
            return
        }
        withAnimation(.spring(duration: 0.22, bounce: 0)) {
            dragOffset = goingUp ? -screenHeight : screenHeight
        } completion: {
            if goingUp { playback.next() } else { playback.previous() }
            // The incoming frame stays in place until the player draws the same frame underneath it.
            coverID = playback.current?.id
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { dragOffset = 0 }
        }
    }
}

/// Whether the system sets bars down the side of the screen here (iPhone Duo's outer display, and its inner display
/// in landscape). Always false before iOS 27.1.
struct VerticalBarsReader: ViewModifier {
    @Binding var vertical: Bool

    func body(content: Content) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.modifier(EdgeReader(vertical: $vertical))
        } else {
            content
        }
        #else
        // Built with the iOS 27.0 SDK (Xcode 27.0), which doesn't have toolbarVerticalEdge.
        content
        #endif
    }

    // toolbarVerticalEdge is in the iOS 27.1 SDK (SwiftUI 8.0.85) and later.
    #if canImport(SwiftUI, _version: 8.0.85)
    @available(iOS 27.1, *)
    private struct EdgeReader: ViewModifier {
        @Environment(\.toolbarVerticalEdge) private var edge
        @Binding var vertical: Bool

        func body(content: Content) -> some View {
            content.onChange(of: edge, initial: true) { _, edge in vertical = edge != nil }
        }
    }
    #endif
}

/// Whether the device's hinge is partly open (iPhone Duo folded part way), from a UIHingeInteraction on an empty view.
/// Always false before iOS 27.1 and on devices without a hinge.
struct HingeReader: UIViewRepresentable {
    @Binding var halfOpen: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            let binding = $halfOpen
            view.addInteraction(UIHingeInteraction { _, update in
                let open = update.hinge?.status == .partiallyOpen
                if binding.wrappedValue != open { binding.wrappedValue = open }
            })
        }
        #endif
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

/// Keeps a video: out of Automix, and never deleted automatically.
struct BookmarkButton: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    let video: Video

    var body: some View {
        let bookmarked = app.isBookmarked(video)
        Button { playback.toggleBookmark() } label: { Image(systemName: bookmarked ? "bookmark.fill" : "bookmark") }
            .accessibilityLabel(bookmarked ? "Bookmarked. Remove bookmark" : "Bookmark")
    }
}
