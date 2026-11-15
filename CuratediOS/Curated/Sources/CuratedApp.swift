import AVFoundation
import BackgroundTasks
import SwiftUI

@main
struct CuratedApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var app: AppState
    @State private var playback: Playback
    @State private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let app = AppState()
        _app = State(initialValue: app)
        let playback = Playback(app: app)
        _playback = State(initialValue: playback)
        // Video plays with sound even with the silent switch on, and keeps going in picture in picture.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            Diagnostics.log("Setting the audio category failed: \(error)")
        }
        Diagnostics.watchAudioSession()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppState.backgroundSyncID, using: nil) { task in
            let work = Task { @MainActor in
                await app.sync()
                app.scheduleBackgroundSync()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        #if DEBUG
        TestHooks.apply(app, playback)
        #endif
        // A fresh launch goes straight to Automix (Home stays underneath for Back) when there's something to watch.
        let router = Router()
        router.onboarding = app.pairing == nil && app.libraries.isEmpty
        #if DEBUG
        let openLatest = ProcessInfo.processInfo.arguments.contains("-curatedLong") && app.latestCount(in: nil) > 0
        let openSettings = ProcessInfo.processInfo.arguments.contains("-curatedSettings")  // For tests: open Settings.
        let stayHome = openSettings || ProcessInfo.processInfo.arguments.contains("-curatedHome")  // For tests: start on Home.
        #else
        let openLatest = false
        let openSettings = false
        let stayHome = false
        #endif
        #if DEBUG
        if let older = ProcessInfo.processInfo.environment["CURATED_TEST_OLDER"] {
            let key = older == "1" ? "youtube@jawed" : older
            Task {
                try? await Task.sleep(for: .seconds(2))
                router.olderVideos = OlderVideosTarget(id: key, name: "@\(creatorHandle(key))")
            }
        }
        #endif
        if openSettings {
            router.settingsShown = true
        } else if stayHome {
        } else if openLatest {
            app.form = .long
            router.open(.latest(nil))  // For tests: -curatedLong opens the long Home's Latest.
        } else if app.automixCount(in: nil) > 0 {
            router.open(.player(.automix(nil)))
        }
        #if DEBUG
        // For tests: -curatedPicker automix|top|longAutomix opens that mix's picker.
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-curatedPicker"), i + 1 < arguments.count {
            router.picking = MixPick(rawValue: arguments[i + 1])
        }
        #endif
        _router = State(initialValue: router)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(playback)
                .environment(router)
                .tint(.accentColor)
                // Light, dark or the system's, from Settings. The windows exist by the time this first runs.
                .onChange(of: app.appearance, initial: true) { _, appearance in
                    WindowAppearance.apply(appearance.interfaceStyle)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                playback.didBecomeActive()
                app.syncIfDue()
                app.resumeFollowingRequestedVideos()
            case .inactive:
                playback.willLeave()
            case .background:
                app.scheduleBackgroundSync()
                app.stopWatchingMacDownload()
                // So another device can pick up from here, even if this one is never opened again.
                playback.savePosition()
                app.sendPositionsSoon()
                // Picture in picture starts as the app leaves the screen.
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    playback.didEnterBackground()
                }
            @unknown default:
                break
            }
        }
    }
}

enum Route: Hashable {
    case player(PlaybackMode)
    case creator(String)
    /// A long-video creator's or playlist's gallery.
    case gallery(String)
    /// Long videos' Latest (or a category's) as a gallery.
    case latest(String?)
}

/// What the sideways layout's right pane shows in place of a player: Latest's gallery.
struct SideLatest: Hashable {
    let category: String?
}

@Observable
final class Router {
    var path: [Route] = []
    /// The first-launch pairing screen (OnboardingView) covers everything while this is set.
    var onboarding = false
    /// Settings covers the whole screen, in every layout.
    var settingsShown = false
    /// Whose older videos are being picked from (OlderVideosView).
    var olderVideos: OlderVideosTarget?
    /// The add-creator form, from Home's + (AddCreatorView).
    var addingCreator = false

    /// Long-pressing Automix or Top 15: the popup picking which cards it plays from (RootView shows it over everything).
    var picking: MixPick?
    /// An iPhone held sideways (SidewaysLayout): the screens on the left, and the player on the right instead of in the path.
    var sideways = false
    /// The queue the sideways player shows (nil for whatever's loaded).
    var sidePlayer: PlaybackMode?
    /// Latest's gallery in the sideways right pane, in place of the player. Opening a player clears it.
    var sideLatest: SideLatest?
    /// The player's queue sheet is up. Here so the sideways tray's Queue button can open it too.
    var queueShown = false

    func open(_ route: Route) {
        if sideways, case .player(let mode) = route {
            sidePlayer = mode
            sideLatest = nil
        } else if sideways, case .latest(let category) = route {
            sideLatest = SideLatest(category: category)
        } else {
            path.append(route)
        }
    }
    func pick(_ mix: MixPick?) { withAnimation(.snappy(duration: 0.25)) { picking = mix } }
}

/// The iPhone layout everywhere except a full-width iPad in landscape or an unfolded iPhone Duo, which get the Mac's
/// layout (WideLayout). Rotating, folding and unfolding carry over what's open and keep the video playing.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The sidebar selection in the wide layout.
    @State private var selection: PlaybackMode?
    /// A long video full screen from its full screen button, held sideways until its exit button (OrientationLock).
    @State private var turnedFullscreen = false
    /// Full screen was left while turned sideways without the side-by-side layout: the upright layout until the window
    /// is upright again.
    @State private var turnedLongDismissed = false
    /// Whether the wide layout is showing; turning the phone only goes full screen from the phone layout.
    @State private var isWide = false

    /// iPhone Duo's inner display: the only time an iPhone gets a regular width.
    private var unfolded: Bool { UIDevice.current.userInterfaceIdiom == .phone && sizeClass == .regular }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            let phone = UIDevice.current.userInterfaceIdiom == .phone
            // Settings: short videos may turn sideways; long videos get the side-by-side layouts when turned (or else
            // play full screen). iPad and iPhone Duo's inner display may turn regardless: then the upright layout.
            let landscapeAllowed = app.allowsLandscape(app.form, unfolded: unfolded)
            let longLoaded = playback.current?.isLong == true
            let turnedLong = landscape && !landscapeAllowed && app.form == .long && longLoaded
                && !playback.isStockFullscreen && !turnedLongDismissed
            let landscapeLayout = landscape && landscapeAllowed
            // Long videos on iPhone Duo's unfolded display in portrait use the phone's screens instead: Home, then a
            // creator's gallery, then the player, each with Back, and the queue sliding up from the bottom.
            // An iPhone on its side (a compact height): the screens on the left, the player beside them. Not while the
            // stock player is full screen from upright, which turns the phone itself.
            let sideways = phone && landscapeLayout && verticalSizeClass == .compact && !playback.isStockFullscreen
            let wide = !sideways && sizeClass == .regular && (phone ? landscapeLayout || app.form == .short : landscapeLayout)
            Group {
                if (turnedFullscreen || turnedLong) && longLoaded {
                    LongFullscreen { leaveFullscreen() }
                } else if sideways {
                    SidewaysLayout()
                        .environment(\.sideways, true)
                        .environment(\.enterLongFullscreen, ViewAction { setTurnedFullscreen(true) })
                } else if wide {
                    WideLayout(selection: $selection)
                        // The Duo's landscape sidebar is wider than an iPad's: it's the only column beside the player.
                        .environment(\.wideColumnWidth, phone && landscapeLayout ? min(380, geo.size.width * 0.45)
                                                                                : min(340, geo.size.width * 0.34))
                        // An unfolded iPhone Duo has about 670pt across in portrait: its sidebar slides out over the
                        // player. In landscape the sidebar stays and the queue slides up from the bottom instead.
                        .environment(\.wideSidebarFloats, phone && !landscapeLayout)
                        .environment(\.wideQueueAsSheet, phone && landscapeLayout)
                        // Landscape also moves the player's buttons into the toolbar down the side, per the HIG.
                        .environment(\.wideSideToolbar, phone && landscapeLayout)
                        .environment(\.floatingSidebarWidth, min(420, geo.size.width * 0.66))
                } else {
                    stack
                        .environment(\.enterLongFullscreen, phone && sizeClass != .regular ? ViewAction { setTurnedFullscreen(true) } : nil)
                }
            }
            .onChange(of: sideways, initial: true) { wasSideways, isSideways in
                if isSideways {
                    enterSideways()
                } else if wasSideways {
                    leaveSideways()
                }
            }
            .onChange(of: wide, initial: true) { wasWide, isWide in
                self.isWide = isWide
                if isWide {
                    enterWide()
                } else if wasWide {
                    enterNarrow()
                }
            }
            // Upright, or allowed to turn again: the next turn goes full screen again.
            .onChange(of: landscape && !landscapeAllowed) { _, stillTurned in if !stillTurned { turnedLongDismissed = false } }
            // The app turns sideways for what Settings allow, and for a long video to go full screen.
            .onChange(of: landscapeAllowed || (app.form == .long && longLoaded), initial: true) { _, allowed in
                OrientationLock.setLandscapeAllowed(allowed, in: windowScene)
            }
        }
        .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            if UIDevice.current.orientation == .portrait { OrientationLock.releasePortrait(in: windowScene) }
        }
        // iPhone Duo: a hinge, so the turning settings are per display and allowed by default.
        .background { FoldableReader { if !app.foldable { app.foldable = true } } }
        // Full screen (held sideways until its exit button, however the phone turns) ends if the long video does (stopped, or a short one started).
        // Upright, long videos open on Latest (Home is one Back away); short videos go back to Home. Sideways, Latest
        // takes the right pane instead. The wide layout picks its own (WideLayout).
        .onChange(of: app.form) { _, form in
            guard !isWide else { return }
            if router.sideways {
                if form == .long, router.sidePlayer?.form != .long { router.sideLatest = SideLatest(category: nil) }
                if form == .short { router.sideLatest = nil }
            } else if form == .long {
                router.path = [.latest(nil)]
            } else if router.path.contains(where: { if case .latest = $0 { true } else { false } }) {
                router.path = []
            }
        }
        .onChange(of: playback.current?.isLong == true) { _, isLong in if !isLong { setTurnedFullscreen(false) } }
        .overlay { mixPicker }
        .fullScreenCover(isPresented: Bindable(router).settingsShown) { SettingsView() }
        // On its own view: two presentations on one view get in each other's way.
        .background { Color.clear.sheet(item: Bindable(router).olderVideos) { OlderVideosView(target: $0) } }
        .background { Color.clear.sheet(isPresented: Bindable(router).addingCreator) { AddCreatorView() } }
        .overlay {
            if router.onboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.6)) { router.onboarding = false }
                    // Like a launch: straight into Automix when there's something to watch.
                    if app.automixCount(in: nil) > 0 { router.path = [.player(.automix(nil))] }
                }
                .transition(.opacity)
            }
        }
        // Unpairing clears the phone, so it starts over at the pairing screen.
        .onChange(of: app.pairing == nil && app.libraries.isEmpty) { _, unpaired in
            if unpaired {
                router.settingsShown = false
                router.olderVideos = nil
                router.path = []
                withAnimation(.easeInOut(duration: 0.4)) { router.onboarding = true }
            }
        }
    }

    /// The Automix or Top 15 popup over a dimmed screen; tapping the dimmed part closes it.
    private var mixPicker: some View {
        ZStack {
            if let pick = router.picking {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { router.pick(nil) }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                MixPicker(pick: pick, dismiss: { router.pick(nil) }) { mode in
                    // A new queue, even if the same pick is already playing.
                    playback.start(Queues.build(mode, app), mode: mode)
                    if isWide { selection = mode } else { router.open(.player(mode)) }
                }
                .id(pick)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        // Across the whole screen, including iPhone Duo's strip down the side of its outer display.
        .ignoresSafeArea(edges: .horizontal)
    }

    private var stack: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .player(let mode): PlayerScreen(mode: mode)
                    case .creator(let username): CreatorView(username: username)
                    case .gallery(let username): LongCreatorView(username: username)
                    case .latest(let category): LatestView(category: category)
                    }
                }
        }
    }

    /// The players leave the path for the pane beside it: the open one, or else whatever's loaded.
    private func enterSideways() {
        let open: PlaybackMode? = router.path.last { if case .player = $0 { true } else { false } }.flatMap {
            if case .player(let mode) = $0 { mode } else { nil }
        }
        // Upright Latest moves to the right pane, unless a player was open over it.
        let latest: SideLatest? = router.path.last.flatMap { if case .latest(let c) = $0 { SideLatest(category: c) } else { nil } }
        router.path.removeAll {
            switch $0 { case .player, .latest: true; default: false }
        }
        router.sidePlayer = open ?? playback.mode
        // Long videos with no player open: the main curated pane on the left, Latest beside it.
        router.sideLatest = latest ?? (open == nil && app.form == .long ? SideLatest(category: nil) : nil)
        router.sideways = true
    }

    /// Upright again: the player for what's playing goes back on top of the screens.
    private func leaveSideways() {
        router.sideways = false
        if let latest = router.sideLatest {
            router.path.append(.latest(latest.category))
            router.sideLatest = nil
            router.sidePlayer = nil
            return
        }
        if playback.current != nil, let mode = router.sidePlayer ?? playback.mode, mode == playback.mode {
            router.path.append(.player(mode))
        }
        router.sidePlayer = nil
    }

    private var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    private func setTurnedFullscreen(_ on: Bool) {
        guard turnedFullscreen != on else { return }
        withAnimation(.snappy) { turnedFullscreen = on }
        OrientationLock.lockLandscape(on, in: windowScene)
    }

    /// Full screen's exit button. Without the side-by-side layout, turned sideways would only go full screen again, so
    /// it goes upright and stays there until the phone is held upright (or, where it can't be held, shows the upright
    /// layout sideways).
    private func leaveFullscreen() {
        guard !app.allowsLandscape(app.form, unfolded: unfolded) else { return setTurnedFullscreen(false) }
        withAnimation(.snappy) {
            turnedFullscreen = false
            turnedLongDismissed = true
        }
        OrientationLock.holdPortrait(in: windowScene)
    }

    /// Selects what's playing, or what the iPhone layout had open, or Automix.
    /// Only what belongs to the form showing (short or long): switching forms on iPhone Duo also switches layouts.
    private func enterWide() {
        if playback.current != nil, let mode = playback.mode, mode.form == app.form {
            selection = mode
            return
        }
        switch router.path.last {
        case .player(let mode)? where mode.form == app.form: selection = mode
        case .creator(let username)? where app.form == .short: selection = .creator(username)
        case .gallery(let username)? where app.form == .long: selection = .longCreator(username)
        case .latest(let category)? where app.form == .long: selection = .latest(category)
        default:
            if let selection, selection.form == app.form { return }
            selection = app.form == .long ? .latest(nil) : app.libraries.isEmpty ? nil : .automix(nil)
        }
    }

    /// Portrait shows the full-screen player for what's playing, or the creator that was selected.
    private func enterNarrow() {
        if playback.current != nil, let mode = playback.mode, mode.form == app.form {
            switch mode {
            case .creator(let username): router.path = [.creator(username), .player(mode)]
            case .longCreator(let username): router.path = [.gallery(username), .player(mode)]
            case .latest(let category): router.path = [.latest(category), .player(mode)]
            default: router.path = [.player(mode)]
            }
        } else if case .creator(let username)? = selection, app.form == .short {
            router.path = [.creator(username)]
        } else if case .longCreator(let username)? = selection, app.form == .long {
            router.path = [.gallery(username)]
        } else if app.form == .long {
            if case .latest(let category)? = selection { router.path = [.latest(category)] } else { router.path = [.latest(nil)] }
        } else {
            router.path = []
        }
    }
}
