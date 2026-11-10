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
            router.open(.player(.latest(nil)))  // For tests: -curatedLong opens the long Home's Latest.
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
    /// The player's queue sheet is up. Here so the sideways tray's Queue button can open it too.
    var queueShown = false

    func open(_ route: Route) {
        if sideways, case .player(let mode) = route {
            sidePlayer = mode
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
    /// An iPhone (or iPhone Duo's outer display) turned sideways while a long video's player is open: just the video,
    /// full screen. The app is otherwise upright only, so this follows how the phone is held, not the window.
    @State private var turnedFullscreen = false
    /// Whether the wide layout is showing; turning the phone only goes full screen from the phone layout.
    @State private var isWide = false

    var body: some View {
        GeometryReader { geo in
            // An iPhone only gets a regular width on iPhone Duo's inner display, which ignores the portrait-only
            // orientation setting, so it's wide either way up.
            let landscape = geo.size.width > geo.size.height
            let phone = UIDevice.current.userInterfaceIdiom == .phone
            // Long videos on iPhone Duo's unfolded display in portrait use the phone's screens instead: Home, then a
            // creator's gallery, then the player, each with Back, and the queue sliding up from the bottom.
            // An iPhone on its side (a compact height): the screens on the left, the player beside them. Not while the
            // stock player is full screen from upright, which turns the phone itself.
            let sideways = phone && landscape && verticalSizeClass == .compact && !playback.isStockFullscreen
            let wide = !sideways && sizeClass == .regular && (phone ? landscape || app.form == .short : landscape)
            Group {
                if turnedFullscreen && playback.current?.isLong == true {
                    LongFullscreen { setTurnedFullscreen(false) }
                } else if sideways {
                    SidewaysLayout()
                        .environment(\.sideways, true)
                        .environment(\.enterLongFullscreen, ViewAction { setTurnedFullscreen(true) })
                } else if wide {
                    WideLayout(selection: $selection)
                        // The Duo's landscape sidebar is wider than an iPad's: it's the only column beside the player.
                        .environment(\.wideColumnWidth, phone && landscape ? min(380, geo.size.width * 0.45)
                                                                          : min(340, geo.size.width * 0.34))
                        // An unfolded iPhone Duo has about 670pt across in portrait: its sidebar slides out over the
                        // player. In landscape the sidebar stays and the queue slides up from the bottom instead.
                        .environment(\.wideSidebarFloats, phone && !landscape)
                        .environment(\.wideQueueAsSheet, phone && landscape)
                        // Landscape also moves the player's buttons into the toolbar down the side, per the HIG.
                        .environment(\.wideSideToolbar, phone && landscape)
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
        }
        .onAppear { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
        // Full screen (held sideways until its exit button, however the phone turns) ends if the long video does (stopped, or a short one started).
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
                    }
                }
        }
    }

    /// The players leave the path for the pane beside it: the open one, or else whatever's loaded.
    private func enterSideways() {
        let open: PlaybackMode? = router.path.last { if case .player = $0 { true } else { false } }.flatMap {
            if case .player(let mode) = $0 { mode } else { nil }
        }
        router.path.removeAll { if case .player = $0 { true } else { false } }
        router.sidePlayer = open ?? playback.mode
        router.sideways = true
    }

    /// Upright again: the player for what's playing goes back on top of the screens.
    private func leaveSideways() {
        router.sideways = false
        if playback.current != nil, let mode = router.sidePlayer ?? playback.mode, mode == playback.mode {
            router.path.append(.player(mode))
        }
        router.sidePlayer = nil
    }

    private func setTurnedFullscreen(_ on: Bool) {
        guard turnedFullscreen != on else { return }
        withAnimation(.snappy) { turnedFullscreen = on }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        OrientationLock.lockLandscape(on, in: scene)
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
            default: router.path = [.player(mode)]
            }
        } else if case .creator(let username)? = selection, app.form == .short {
            router.path = [.creator(username)]
        } else if case .longCreator(let username)? = selection, app.form == .long {
            router.path = [.gallery(username)]
        } else {
            router.path = []
        }
    }
}
