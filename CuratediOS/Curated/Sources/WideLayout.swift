 import SwiftUI

extension EnvironmentValues {
    /// The width of the sidebar and queue columns: 340 on an iPad, narrower on iPhone Duo's smaller inner display.
    @Entry var wideColumnWidth: CGFloat = 340
    /// iPhone Duo unfolded in portrait: the sidebar slides out over the player instead of standing beside it.
    @Entry var wideSidebarFloats = false
    /// The floating sidebar's width: over the black bars beside the video, so the category names fit.
    @Entry var floatingSidebarWidth: CGFloat = 420
    /// iPhone Duo unfolded in landscape: the sidebar stays, and the queue slides up from the bottom as on the phone.
    @Entry var wideQueueAsSheet = false
    /// iPhone Duo unfolded in landscape: the player's buttons go in the system toolbar, which iOS sets down the side
    /// of the screen with the status bar (the HIG's vertical controls), instead of over the video.
    @Entry var wideSideToolbar = false
    /// The system's light/dark setting while the window is held in dark mode for the side toolbar (DarkWindow). Nil
    /// otherwise.
    @Entry var systemColorScheme: ColorScheme? = nil
    /// Slides the queue sheet up. Nil while the queue is a column beside the player.
    @Entry var showQueueSheet: ViewAction? = nil
    /// Automix: start or end a time-limited mix, from a long press on the title or the queue button.
    @Entry var toggleTimeLimit: ViewAction? = nil
    /// Slides the floating sidebar out or away. Nil while the sidebar stands beside the player.
    @Entry var toggleSidebar: ViewAction? = nil
}

/// A closure to keep in the environment. Closures can't be compared, so a bare one counts as changed every time its
/// parent updates and redraws every view reading it; two of these are the same if their keys are. Key on any value the
/// closure captures: it may go on running an earlier copy until the key changes. (@State and classes read live.)
struct ViewAction: Equatable {
    private let key: AnyHashable
    private let action: () -> Void

    init(key: AnyHashable = AnyHashable(0), _ action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }

    func callAsFunction() { action() }

    static func == (a: ViewAction, b: ViewAction) -> Bool { a.key == b.key }
}

/// iPad in landscape and unfolded iPhone Duo: the Mac app's window. A sidebar with the mixes and creator cards, and
/// beside it the queue and the player. Portrait iPad (and narrow multitasking windows) use the iPhone layout instead;
/// see RootView.
struct WideLayout: View {
    @Environment(AppState.self) private var app
    @Environment(\.wideColumnWidth) private var columnWidth
    @Environment(\.wideSidebarFloats) private var sidebarFloats
    @Environment(\.floatingSidebarWidth) private var floatingWidth
    @Environment(\.wideSideToolbar) private var sideToolbar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    @Binding var selection: PlaybackMode?
    @State private var sidebarOpen = false
    /// The system's light/dark setting, reported by DarkWindow while the side toolbar holds the window in dark mode.
    @State private var systemScheme: ColorScheme = .light
    @AppStorage("queueHidden") private var queueHidden = false

    var body: some View {
        Group {
            if sidebarFloats {
                floating
            } else if sideToolbar {
                splitView
            } else {
                // Side by side like the Mac window. (The system split view floats its sidebar over the queue on iPad.)
                HStack(spacing: 0) {
                    sidebar
                        .background { AuroraBackground(intensity: 0.65, frameInterval: 1.0 / 20) }
                        // Out to the screen's edge, past the margin iPhone Duo keeps for its rounded corners in
                        // landscape, so the cards sit as far from the left edge as from the right.
                        .ignoresSafeArea(edges: .leading)
                        .frame(width: columnWidth)
                    Divider().ignoresSafeArea()
                    detail
                        .id(selection)  // A fresh view (and onAppear) for each queue, e.g. switching between categories.
                }
            }
        }
        .onChange(of: selection) { setSidebarOpen(false) }
        .onChange(of: router.settingsShown) { _, showing in if showing { setSidebarOpen(false) } }
        .onChange(of: sidebarFloats) { setSidebarOpen(false) }
        .onChange(of: app.categories) { _, categories in
            // Leave a deleted category's queue.
            switch selection {
            case .automix(let id?, _), .top(let id?, _):
                if !categories.contains(where: { $0.id == id }) { selection = .automix(nil) }
            case .latest(let id?), .longAutomix(let id?, _):
                if !categories.contains(where: { $0.id == id }) { selection = .latest(nil) }
            default: break
            }
        }
        // Switching between short and long videos opens the other one's first mix, unless what's selected is already
        // of that form (e.g. coming back to what's playing).
        .onChange(of: app.form) { _, form in
            if selection?.form != form {
                // Long videos: what's loaded, such as the one last playing on another device, or else Latest.
                let loaded = playback.current != nil && playback.mode?.form == .long ? playback.mode : nil
                selection = form == .short ? .automix(nil) : loaded ?? .latest(nil)
            }
        }
        .onChange(of: playback.syncedVideoLoads) {
            if app.form == .long, let mode = playback.mode { selection = mode }
        }
    }

    /// iPhone Duo unfolded in landscape: the system split view, whose detail column gets its toolbar down the side of
    /// the screen (only a split view's detail, or a full-width view, gets vertical bars).
    private var splitView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
                .navigationSplitViewColumnWidth(columnWidth)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(removing: .sidebarToggle)
                // The window is dark (DarkWindow); the sidebar keeps the system's look, background included, since
                // the split view would paint its column from the window.
                .background { AuroraBackground(intensity: 0.65, frameInterval: 1.0 / 20).ignoresSafeArea() }
                .environment(\.colorScheme, systemScheme)
        } detail: {
            detail
                .id(selection)
                .toolbarTitleDisplayMode(.inline)
                .environment(\.systemColorScheme, systemScheme)
        }
        .navigationSplitViewStyle(.balanced)
        .background { DarkWindow(systemScheme: $systemScheme) }
    }

    /// The player full width, with the sidebar sliding out over it as a glass panel. Tapping anywhere else, or the
    /// sidebar button again, slides it away.
    private var floating: some View {
        ZStack(alignment: .topLeading) {
            detail
                .id(selection)
                .environment(\.toggleSidebar, ViewAction { setSidebarOpen(!sidebarOpen) })
            if selection == nil {
                // No queue open, so no top bar with the sidebar button: float one over the player.
                GlassIconButton(symbol: "line.3.horizontal", label: "Show Sidebar") { setSidebarOpen(true) }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if sidebarOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { setSidebarOpen(false) }
                    .accessibilityLabel("Hide Sidebar")
                    .accessibilityAddTraits(.isButton)
                sidebar
                    .frame(width: floatingWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .glassBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 20, x: 4)
                    .padding(.leading, 8)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private func setSidebarOpen(_ open: Bool) {
        guard sidebarOpen != open else { return }
        withAnimation(.snappy(duration: 0.3)) { sidebarOpen = open }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if app.isSyncing {
                    SyncProgressRow().padding(.horizontal, 6)
                }
                SidebarSectionTitle("Watch")
                watchSection

                SidebarSectionTitle("Creators").padding(.top, 8)
                if app.form == .long && app.longLibraries.allSatisfy(\.videos.isEmpty) { NoLongVideos() }
                // The long sidebar only shows categories that have a long-video creator.
                let shown = app.categories.filter { app.form == .short || !app.longLibraries(in: $0.id).isEmpty }
                ForEach(shown) { category in
                    CreatorCard(title: category.name, libraries: app.libraries(in: category.id, form: app.form),
                                cardKey: category.id, category: category.id, open: open, selection: selection,
                                avatarSize: 44, form: app.form)
                }
                let others = app.form == .short ? app.uncategorizedLibraries : app.uncategorizedLongLibraries
                if !others.isEmpty {
                    CreatorCard(title: shown.isEmpty ? "All Creators" : "Other Creators", libraries: others,
                                cardKey: "other", category: nil, open: open, selection: selection,
                                avatarSize: 44, form: app.form)
                }
                if app.form == .short && !app.vineLibraries.isEmpty {
                    CreatorCard(title: "Vine", libraries: app.vineLibraries, cardKey: "vine", category: nil, open: open,
                                selection: selection, avatarSize: 44, vine: true)
                }
                // Always the last card.
                if app.form == .long && !app.playlistLibraries.isEmpty {
                    PlaylistsCard(playlists: app.playlistLibraries, open: open, selection: selection)
                }

                LibraryFooter()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .refreshable {
            if app.pairing != nil { await app.sync() }
        }
        .modifier(SidebarHeader {
            HStack {
                Image(app.logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 28)
                    .accessibilityLabel(app.form == .long ? "Curated, long videos" : "Curated")
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if app.pairing != nil {
                    Button { router.addingCreator = true } label: {
                        Image(systemName: "plus").font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Add Creator")
                    .accessibilityIdentifier("homeAddCreator")
                }
                FormSwitchButton()
                Button { router.settingsShown = true } label: {
                    Image(systemName: "gearshape").font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityLabel("Settings")
            }
            .padding(.leading, Self.margin)
            .padding(.trailing, Self.margin - 8)
            .padding(.top, sideToolbar ? 43.5 : 8)  // iPhone Duo landscape: centered on the clock and Wi-Fi in the side strip.
            .padding(.bottom, 10)
        })
    }

    /// The same Automix and Top 15 tiles as Home (Latest and Automix for long videos), then Watch Later and Bookmarks.
    private var watchSection: some View {
        let long = app.form == .long
        let later: PlaybackMode = long ? .longWatchLater : .watchLater
        let bookmarks: PlaybackMode = long ? .longBookmarks : .bookmarks
        let laterCount = app.watchLaterVideos(app.form).count
        let bookmarkCount = app.bookmarkedVideos(app.form).count
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                if long {
                    let unwatched = app.latestCount(in: nil)
                    WatchTile(symbol: "clock", tint: .logoRed, title: "Latest",
                              subtitle: unwatched > 0 ? "\(unwatched) unwatched" : "All caught up",
                              selected: selection == .latest(nil)) { startMix(.latest(nil)) }
                    WatchTile(symbol: "shuffle", tint: .topTint, title: "Automix", subtitle: "Mixed creators",
                              selected: selection == .longAutomix(nil), hold: { router.pick(.longAutomix) }) { startMix(.longAutomix(nil)) }
                } else {
                    let unplayed = app.automixCount(in: nil)
                    WatchTile(symbol: "shuffle", tint: .logoRed, title: "Automix",
                              subtitle: unplayed > 0 ? "\(unplayed) unwatched" : "All caught up",
                              selected: selection == .automix(nil), hold: { router.pick(.automix) }) { startMix(.automix(nil)) }
                    WatchTile(symbol: "star.fill", tint: .topTint, title: "Top \(PlaybackMode.topCountAll)", subtitle: "Most viewed",
                              selected: selection == .top(nil), hold: { router.pick(.top) }) { startMix(.top(nil)) }
                }
            }
            // Square icon buttons on the right, as on the phone's Home, each while something is saved. A video picked
            // from one's list plays that list beside the sidebar.
            if laterCount > 0 || bookmarkCount > 0 {
                HStack(spacing: 10) {
                    Spacer()
                    if laterCount > 0 {
                        SavedButton(symbol: "tray.and.arrow.down", title: "Watch Later", mode: later, onPick: playSaved)
                    }
                    if bookmarkCount > 0 {
                        SavedButton(symbol: "bookmark.fill", title: "Bookmarks", mode: bookmarks, onPick: playSaved)
                    }
                }
            }
        }
    }

    /// A video picked from Watch Later or Bookmarks: plays that list from there.
    private func playSaved(_ mode: PlaybackMode, _ videos: [Video], _ index: Int) {
        playback.start(videos, at: index, mode: mode)
        selection = mode
    }

    /// Selects a mix with a new queue, even when it's the one already playing.
    private func startMix(_ mode: PlaybackMode) {
        playback.start(Queues.build(mode, app), mode: mode)
        selection = mode
    }

    /// Selects a mix or creator. A creator's videos are picked from the queue, so it comes back if it was hidden.
    private func open(_ mode: PlaybackMode) {
        selection = mode
        if case .creator = mode, queueHidden {
            withAnimation(.snappy(duration: 0.3)) { queueHidden = false }
        }
    }

    /// The sidebar's one left edge: the 12pt outside the cards plus the 14pt inside them.
    static let margin: CGFloat = 26

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .creator(let username)?:
            CreatorDetail(username: username)
        case .longCreator(let username)?:
            LongCreatorDetail(username: username)
        case let mode?:
            QueueDetail(mode: mode)
        case nil:
            PlayerPane()
        }
    }
}

/// The logo and sync button pinned over the top of the sidebar. Cards scrolling under it blur and fade toward the
/// top of the screen (the system's scroll edge effect); at rest it's the sidebar's own color. Before iOS 26, a
/// frosted band fades in once the list scrolls.
private struct SidebarHeader<Header: View>: ViewModifier {
    @ViewBuilder let header: () -> Header
    @State private var scrolled = false

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .safeAreaBar(edge: .top, spacing: 0, content: header)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else if #available(iOS 18, *) {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    header().background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea(edges: [.top, .horizontal])
                            .opacity(scrolled ? 1 : 0)
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, isScrolled in
                    withAnimation(.easeOut(duration: 0.15)) { scrolled = isScrolled }
                }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0, content: header)
        }
    }
}

private struct SidebarSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, WideLayout.margin - 12)
            .padding(.top, 4)
    }
}

// MARK: Queue

/// A mix (Automix, Top, Watch Later) with its list beside the player, like the Mac's QueueView.
private struct QueueDetail: View {
    @Environment(AppState.self) private var app
    @Environment(\.wideColumnWidth) private var columnWidth
    @Environment(Playback.self) private var playback
    @Environment(\.wideQueueAsSheet) private var queueAsSheet
    let mode: PlaybackMode
    @AppStorage("queueHidden") private var queueHidden = false
    @State private var showQueue = false

    private var isLoaded: Bool { playback.mode == mode }
    private var isTimeLimited: Bool { isLoaded && playback.timeLimitMinutes != nil }
    private var nothingUnplayed: Bool { app.libraries(in: nil, form: mode.form).allSatisfy { app.unplayedCount($0) == 0 } }

    var body: some View {
        HStack(spacing: 0) {
            if !queueHidden && !queueAsSheet {
                queueList
                    .frame(width: columnWidth)
                    .transition(.move(edge: .leading))
                Divider()
            }
            PlayerPane()
                .overlay(alignment: .top) {
                    PlayerTopBar(title: title, showSummary: mode.isOpenMix && isLoaded, timeLimited: isTimeLimited) {
                        mixControls
                    }
                    .environment(\.showQueueSheet, queueAsSheet ? ViewAction { showQueue = true } : nil)
                }
        }
        .modifier(SideToolbar(showQueue: { showQueue = true }) { sideMixControls })
        .environment(\.toggleTimeLimit, canTimeLimit ? ViewAction(key: mode, toggleTimeLimit) : nil)
        .sheet(isPresented: $showQueue) {
            QueueListSheet(timeLimited: isTimeLimited, toggleTimeLimit: canTimeLimit ? toggleTimeLimit : nil) { queueList }
        }
        .onAppear {
            // Rebuild if another queue is loaded, or this one was empty (e.g. new videos since).
            if !isLoaded || playback.queue.isEmpty { start() }
        }
    }

    private var queueList: some View {
        QueueList(videos: isLoaded ? playback.queue : [], showCreator: true, emptyText: emptyText) { index in
            playback.play(at: index)
            showQueue = false
        }
    }

    /// As on the phone: New List or Refresh for a list. (Automix's Time Limit is a long press on the title or the queue
    /// button, or the queue sheet's button.)
    @ViewBuilder private var mixControls: some View {
        if mode.form == .short { ShortAutoplayButton() }
        if mode.form == .long { AutoplayButton() }
        if !mode.isOpenMix {
            Button { start() } label: {
                Label(mode.topLimit == nil ? "Refresh" : "New List", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GlassChipStyle(selected: false))
            .disabled(nothingUnplayed && !mode.isBookmarks)
        }
    }

    /// The same controls as toolbar items, with titles for the system's overflow menu.
    @ViewBuilder private var sideMixControls: some View {
        if mode.form == .short { ShortAutoplayItem() }
        if mode.form == .long {
            Button { app.autoplayLong.toggle() } label: {
                Label(app.autoplayLong ? "Autoplay is on" : "Autoplay is off",
                      systemImage: app.autoplayLong ? "play.square.stack.fill" : "play.square.stack")
            }
        }
        if !mode.isOpenMix {
            Button { start() } label: {
                Label(mode.topLimit == nil ? "Refresh" : "New List", systemImage: "arrow.clockwise")
            }
            .disabled(nothingUnplayed && !mode.isBookmarks)
        }
    }

    private var canTimeLimit: Bool { mode.isAutomix && (!nothingUnplayed || isTimeLimited) }

    private func toggleTimeLimit() {
        if isTimeLimited {
            playback.continueWith(Queues.build(mode, app), mode: mode)
        } else {
            let minutes = app.timeLimitMinutes
            playback.start(Queues.limit(Queues.build(mode, app), toSeconds: Double(minutes * 60)),
                           mode: mode, timeLimitMinutes: minutes)
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
        switch mode {
        case .top: "No unwatched videos right now. Check back after the next sync."
        case .latest: "No unwatched long videos. Check back after the next sync."
        case .watchLater, .longWatchLater: "Nothing saved. Use the Watch Later button in the player to set a video aside for later."
        case .bookmarks, .longBookmarks: "No bookmarks. Use the bookmark button in the player to keep a video; bookmarked videos stay out of Automix and aren't deleted automatically."
        default: "No unwatched videos. Automix alternates between creators' unwatched videos. Check back after the next sync."
        }
    }

    private func start() {
        playback.start(Queues.build(mode, app), mode: mode)
    }
}

/// A creator's videos beside the player, like the Mac's CreatorWatchView.
private struct CreatorDetail: View {
    @Environment(AppState.self) private var app
    @Environment(\.wideColumnWidth) private var columnWidth
    @Environment(Playback.self) private var playback
    @Environment(\.wideQueueAsSheet) private var queueAsSheet
    let username: String
    @AppStorage("queueHidden") private var queueHidden = false
    @State private var showQueue = false

    private var library: CreatorLibrary? { app.library(username) }
    private var name: String { library?.creator.displayName ?? "@\(creatorHandle(username))" }

    var body: some View {
        HStack(spacing: 0) {
            if !queueHidden && !queueAsSheet {
                queueList
                    .frame(width: columnWidth)
                    .transition(.move(edge: .leading))
                Divider()
            }
            PlayerPane()
                .overlay(alignment: .top) {
                    PlayerTopBar(title: name, subtitle: library.map { "\(app.unplayedCount($0)) unwatched · \($0.videos.count) total" }) {
                        if let library, !library.videos.isEmpty {
                            Menu {
                                MarkAllButtons(library: library)
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .glassBackground(in: Circle(), interactive: true)
                            }
                            .accessibilityLabel("Mark All")
                        }
                    }
                    .environment(\.showQueueSheet, queueAsSheet ? ViewAction { showQueue = true } : nil)
                }
        }
        .modifier(SideToolbar(showQueue: { showQueue = true }) {
            if let library, !library.videos.isEmpty {
                Menu {
                    MarkAllButtons(library: library)
                } label: {
                    Label("Mark All", systemImage: "checkmark.circle")
                }
            }
        })
        .sheet(isPresented: $showQueue) {
            QueueListSheet { queueList }
        }
        .onAppear {
            // A creator's videos are picked from the list, so it slides up unless one of theirs is already playing.
            if queueAsSheet && playback.mode != .creator(username) { showQueue = true }
        }
    }

    private var queueList: some View {
        QueueList(videos: library?.videos ?? [], showCreator: false,
                  emptyText: "Videos for \(name) appear here after the next sync.") { index in
            if let library { playback.start(library.videos, at: index, mode: .creator(username)) }
            showQueue = false
        }
    }
}

/// iPhone Duo unfolded in landscape: the player's buttons as system toolbar items, which iOS places down the side of
/// the screen (the HIG's vertical controls). The top bar's group (queue, the mix's own buttons, picture in picture)
/// comes first, then the bottom bar's playback controls, each kept as its own group.
struct SideToolbar<MixItems: View>: ViewModifier {
    @Environment(\.wideSideToolbar) private var wideSideToolbar
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    /// Nil to follow the wide layout's setting (wideSideToolbar); the phone player passes its own.
    var enabled: Bool? = nil
    let showQueue: () -> Void
    @ViewBuilder let mixItems: () -> MixItems

    func body(content: Content) -> some View {
        // Only iPhone Duo (iOS 27) puts bars down the side.
        if enabled ?? wideSideToolbar, #available(iOS 26, *) {
            sideToolbar(content)
        } else {
            content
        }
    }

    @available(iOS 26, *)
    private func sideToolbar(_ content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button(action: showQueue) { Label("Queue", systemImage: "list.bullet") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    mixItems()
                    if playback.canStartPip {
                        Button { playback.startPip() } label: { Label("Picture in Picture", systemImage: "pip.enter") }
                    }
                }
                // Share on its own, then the speed, then Watch Later and played together at the bottom.
                if let video = playback.current {
                    ToolbarItemGroup(placement: .bottomBar) {
                        ShareLink(item: app.store.videoFile(video)) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { playback.cycleSpeed() } label: {
                            Label { Text("Speed \(formatSpeed(playback.shownSpeed))") } icon: { SpeedGlyph(speed: playback.shownSpeed) }
                        }
                        .speedLock(playback.speedLocked)
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItemGroup(placement: .bottomBar) { savedItems(video) }
                }
            }
            .tint(.white)  // White symbols on the dark glass, like the phone player's buttons.
    }

    @ViewBuilder private func savedItems(_ video: Video) -> some View {
        let played = app.isPlayed(video)
        Button { playback.saveForLater() } label: { Label("Watch Later", systemImage: "tray.and.arrow.down") }
            .disabled(playback.finished)
        let bookmarked = app.isBookmarked(video)
        Button { playback.toggleBookmark() } label: {
            Label(bookmarked ? "Remove Bookmark" : "Bookmark", systemImage: bookmarked ? "bookmark.fill" : "bookmark")
        }
        Button { app.setPlayed(video, !played) } label: {
            Label(played ? "Mark as Unwatched" : "Mark as Watched", systemImage: played ? "checkmark.circle.fill" : "circle")
        }
    }
}

/// The speed ("1×", "1.5×", "2×") drawn as a template image, so the toolbar keeps it down the side: a toolbar item
/// whose label is only text, or a custom view, goes back to a horizontal bar.
private struct SpeedGlyph: View {
    let speed: Float
    private static var cache: [String: UIImage] = [:]

    var body: some View {
        Image(uiImage: Self.image(formatSpeed(speed)))
    }

    private static func image(_ text: String) -> UIImage {
        if let cached = cache[text] { return cached }
        let font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        let image = UIGraphicsImageRenderer(size: CGSize(width: ceil(size.width), height: ceil(size.height))).image { _ in
            (text as NSString).draw(at: .zero, withAttributes: attributes)
        }
        .withRenderingMode(.alwaysTemplate)
        cache[text] = image
        return image
    }
}

/// The queue sliding up from the bottom, as on the phone.
private struct QueueListSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.systemColorScheme) private var systemColorScheme
    var timeLimited = false
    /// Automix: start or end a time-limited mix.
    var toggleTimeLimit: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
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
        .environment(\.colorScheme, systemColorScheme ?? colorScheme)
    }
}

/// Applies the Appearance setting to every window, except ones a DarkWindow is holding dark.
@MainActor
enum WindowAppearance {
    static private(set) var style = UIUserInterfaceStyle.unspecified
    static var heldDark = Set<ObjectIdentifier>()
    static let changed = Notification.Name("CuratedAppearanceChanged")

    static func apply(_ newStyle: UIUserInterfaceStyle) {
        style = newStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where !heldDark.contains(ObjectIdentifier(window)) {
                window.overrideUserInterfaceStyle = newStyle
            }
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

/// Holds the window in dark mode while it's on screen. UIKit draws iPhone Duo's toolbar down the side from the
/// window's light/dark setting, which SwiftUI's colorScheme doesn't reach, so in light mode its glass is a gray slab
/// beside the black player. Reports the system's own setting (the scene's, which the window override doesn't change)
/// so the sidebar and sheets can keep it.
struct DarkWindow: UIViewRepresentable {
    /// Optional: the phone player is dark throughout, so it doesn't need the system's setting back.
    var systemScheme: Binding<ColorScheme>?

    func makeUIView(context: Context) -> WindowView {
        let view = WindowView()
        view.onSchemeChange = { systemScheme?.wrappedValue = $0 }
        return view
    }

    func updateUIView(_ view: WindowView, context: Context) {
        view.onSchemeChange = { systemScheme?.wrappedValue = $0 }
    }

    static func dismantleUIView(_ view: WindowView, coordinator: ()) {
        view.restore()
    }

    final class WindowView: UIView {
        var onSchemeChange: ((ColorScheme) -> Void)?
        private weak var darkenedWindow: UIWindow?
        private weak var observedScene: UIWindowScene?
        private var registration: (any UITraitChangeRegistration)?
        private var appearanceObserver: (any NSObjectProtocol)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            restore()
            guard let window, let scene = window.windowScene else { return }
            window.overrideUserInterfaceStyle = .dark
            WindowAppearance.heldDark.insert(ObjectIdentifier(window))
            darkenedWindow = window
            observedScene = scene
            report(scene)
            registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (scene: UIWindowScene, _) in
                self?.report(scene)
            }
            appearanceObserver = NotificationCenter.default.addObserver(forName: WindowAppearance.changed, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    if let scene = self?.observedScene { self?.report(scene) }
                }
            }
        }

        /// The Appearance setting, or the system's when that's set to System.
        private func report(_ scene: UIWindowScene) {
            let style = WindowAppearance.style == .unspecified ? scene.traitCollection.userInterfaceStyle : WindowAppearance.style
            let scheme: ColorScheme = style == .dark ? .dark : .light
            DispatchQueue.main.async { [weak self] in self?.onSchemeChange?(scheme) }
        }

        func restore() {
            if let darkenedWindow {
                WindowAppearance.heldDark.remove(ObjectIdentifier(darkenedWindow))
                darkenedWindow.overrideUserInterfaceStyle = WindowAppearance.style
            }
            darkenedWindow = nil
            if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
            appearanceObserver = nil
            if let registration { observedScene?.unregisterForTraitChanges(registration) }
            registration = nil
        }
    }
}

/// The phone player's top bar, over the video: the queue toggle, the title (blue glass while a time-limited mix
/// counts down) and the mix's own buttons on the right.
private struct PlayerTopBar<Trailing: View>: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(\.toggleTimeLimit) private var toggleTimeLimit
    @Environment(\.toggleSidebar) private var toggleSidebar
    @Environment(\.wideSideToolbar) private var sideToolbar
    let title: String
    var subtitle: String?
    var showSummary = false
    var timeLimited = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let toggleSidebar {
                GlassIconButton(symbol: "line.3.horizontal", label: "Show Sidebar", action: toggleSidebar.callAsFunction)
            }
            if !sideToolbar { QueueToggleButton() }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).lineLimit(1)
                if showSummary {
                    QueueSummary()
                } else if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
            .foregroundStyle(.white)
            .shadow(radius: timeLimited ? 0 : 4)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .modifier(TimeLimitGlass(active: timeLimited))
            .contentShape(Rectangle())
            .onLongPressGesture { toggleTimeLimit?() }
            .sensoryFeedback(.impact, trigger: playback.timeLimitMinutes)
            .accessibilityElement(children: .combine)
            .modifier(TimeLimitAction(enabled: toggleTimeLimit != nil, timeLimited: timeLimited, minutes: app.timeLimitMinutes,
                                      action: { toggleTimeLimit?() }))
            Spacer()
            if !sideToolbar {  // Otherwise they're in the toolbar down the side.
                if playback.canStartPip {
                    GlassIconButton(symbol: "pip.enter", label: "Picture in Picture") { playback.startPip() }
                }
                trailing()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, sideToolbar ? 14.5 : 8)  // iPhone Duo landscape: centered on the clock and Wi-Fi.
        .padding(.bottom, 24)
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }
}

/// The queue's videos; tap one to play it, long-press for played and Watch Later.
private struct QueueList: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    let videos: [Video]
    let showCreator: Bool
    let emptyText: String
    let onSelect: (Int) -> Void

    var body: some View {
        if videos.isEmpty {
            ContentUnavailableView {
                Label("No videos", systemImage: "film.stack")
            } description: {
                Text(emptyText)
            }
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        Button { onSelect(index) } label: {
                            if video.isLong {
                                LongVideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: showCreator)
                            } else {
                                VideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: showCreator)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(playback.current?.id == video.id ? Color.accentColor.opacity(0.12) : Color.clear)
                        .contextMenu {
                            if app.isPlayed(video) {
                                Button("Mark as Unwatched", systemImage: "circle") { app.setPlayed(video, false) }
                            } else {
                                Button("Mark as Watched", systemImage: "checkmark.circle") { app.setPlayed(video, true) }
                                if app.isSavedForLater(video) {
                                    Button("Remove from Watch Later", systemImage: "tray.and.arrow.up") { app.setWatchLater([video], false) }
                                } else {
                                    Button("Save to Watch Later", systemImage: "tray.and.arrow.down") { app.setWatchLater([video], true) }
                                }
                            }
                            if app.isBookmarked(video) {
                                Button("Remove Bookmark", systemImage: "bookmark.slash") { app.setBookmarked(video, false) }
                            } else {
                                Button("Bookmark", systemImage: "bookmark") { app.setBookmarked(video, true) }
                            }
                        }
                        .id(video.id)
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let id = playback.current?.id { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: playback.current?.id) { _, id in
                    if let id, videos.contains(where: { $0.id == id }) {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }
}

/// Shows or hides the list beside the player. Remembered across launches.
private struct QueueToggleButton: View {
    @Environment(\.showQueueSheet) private var showQueueSheet
    @Environment(\.toggleTimeLimit) private var toggleTimeLimit
    @AppStorage("queueHidden") private var queueHidden = false

    var body: some View {
        // A long press starts or ends Automix's Time Limit.
        if let showQueueSheet {
            GlassIconButton(symbol: "list.bullet", label: "Queue", longPress: toggleTimeLimit?.callAsFunction, action: showQueueSheet.callAsFunction)
        } else {
            GlassIconButton(symbol: "sidebar.left", label: queueHidden ? "Show Queue" : "Hide Queue", longPress: toggleTimeLimit?.callAsFunction) {
                withAnimation(.snappy(duration: 0.3)) { queueHidden.toggle() }
            }
        }
    }
}

// MARK: Player

/// The video with the Mac's bar underneath: who and what, the view count, and the controls.
struct PlayerPane: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(\.wideSideToolbar) private var sideToolbar
    /// How far the video has been dragged up or down; the controls follow it.
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if let video = playback.current, video.isLong { longBody(video) } else { shortBody }
    }

    /// A long video: Apple's player (its controls skip 10 seconds, scrub, and go full screen or picture in picture),
    /// with who, what and the video's buttons underneath rather than over it, so they don't cover its controls.
    private func longBody(_ video: Video) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.ignoresSafeArea()
                StockPlayerView(playback: playback)
                    .aspectRatio(playback.videoAspect ?? 16 / 9, contentMode: .fit)
                if playback.finished { FinishedCard() }
                if playback.awaitingNext, let next = playback.upNext { UpNextCard(next: next) }
            }
            // Room for the top bar laid over the pane (title, queue and the mix's buttons).
            .padding(.top, 64)
            bar(video)
                .ignoresSafeArea(edges: sideToolbar ? .bottom : [])
        }
        .background { Color.black.ignoresSafeArea() }
        .background { keyboardShortcuts }
        .environment(\.colorScheme, .dark)
    }

    private var shortBody: some View {
        VStack(spacing: 0) {
            ZStack {
                // Out to every edge of the screen (behind the home indicator, the status bar and iPhone Duo's toolbar
                // down the side), so no strip of the app's background shows around the video.
                Color.black.ignoresSafeArea()
                if playback.current != nil {
                    VideoBackdrop(playback: playback)
                        .ignoresSafeArea()
                        .accessibilityHidden(true)
                    SwipeableVideo(dragOffset: $dragOffset)
                        .clipped()  // The video sliding in stays inside the pane.
                        // Full height, under the status bar and home indicator, like the phone player: only the
                        // controls and caption need the safe area.
                        .ignoresSafeArea(edges: .vertical)
                    if !playback.isPlaying && !playback.finished && !playback.awaitingNext {
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
                } else {
                    VStack(spacing: 14) {
                        Image(app.logoName)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 44)
                            .opacity(0.55)
                        Text("Pick a video to start watching")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .environment(\.colorScheme, .dark)
                }
                if playback.finished { FinishedCard() }
                if playback.awaitingNext, let next = playback.upNext { UpNextCard(next: next) }
            }
            .background { keyboardShortcuts }
            // Laid over the video like the full-screen player's controls, not in a panel below it.
            .overlay(alignment: .bottom) {
                if let video = playback.current {
                    bar(video)
                        .offset(y: dragOffset)
                        // iPhone Duo landscape: down past the safe area, level with the bottom of the side toolbar.
                        .ignoresSafeArea(edges: sideToolbar ? .bottom : [])
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// Who and when, the caption, progress and the controls, over a fade at the bottom of the video.
    private func bar(_ video: Video) -> some View {
        let played = app.isPlayed(video)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(username: video.creator, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.library(video.creator, form: video.isLong ? .long : .short)?.creator.displayName
                         ?? "@\(creatorHandle(video.creator))")
                        .font(.headline)
                    HStack(spacing: 6) {
                        Text(video.date, format: .relative(presentation: .named))
                        if let label = modeLabel {
                            Text("·")
                            Label(label.text, systemImage: label.symbol)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let views = video.viewCount {
                    VStack(spacing: 2) {
                        Image(systemName: "eye")
                        Text(views.formatted(.number.notation(.compactName)))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .fixedSize()
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(views.formatted(.number.notation(.compactName))) views")
                }
            }
            // Long videos: the title, then the description.
            if video.isLong, let title = video.title, !title.isEmpty {
                Text(title).font(.headline).lineLimit(2)
            }
            let text = video.isLong ? (video.details ?? "") : video.caption
            if !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            // Long videos scrub in the stock player's own controls.
            if let length = video.duration, length > 0, !video.isLong {
                ScrubBar(length: length)
            }
            if !sideToolbar { controls(video, played: played) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, sideToolbar ? 31 : 12)  // 31 from the screen's edge, as the side toolbar is.
        .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    /// Space, ⌘← and ⌘→ for a hardware keyboard, now that the transport buttons are the video's tap and swipe.
    private var keyboardShortcuts: some View {
        ZStack {
            Button("Play or Pause") { playback.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(playback.current == nil || playback.finished)
            Button("Previous") { playback.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!playback.hasPrevious)
            Button("Skip") { playback.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(playback.current == nil || playback.finished)
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Played, speed, Watch Later and share. (Play, pause, previous and next are the video's tap and swipe.) In the
    /// side toolbar instead on an unfolded iPhone Duo in landscape (SideToolbar).
    private func controls(_ video: Video, played: Bool) -> some View {
        HStack {
            Button { app.setPlayed(video, !played) } label: {
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
                .keyboardShortcut("l", modifiers: .command)
                .accessibilityLabel("Watch Later")
            BookmarkButton(video: video)
                .keyboardShortcut("b", modifiers: .command)
            ShareLink(item: app.store.videoFile(video)) { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Share")
        }
        .font(.title2)
        .buttonStyle(.plain)
    }

    private var modeLabel: (text: String, symbol: String)? {
        let i = playback.index ?? 0
        if let minutes = playback.timeLimitMinutes { return ("\(minutes)-min mix · \(i + 1) of \(playback.queue.count)", "timer") }
        switch playback.mode {
        case .automix?, .longAutomix?: return ("Automix", "shuffle")
        case .vineAutomix?: return ("Vine Automix", "shuffle")
        case .latest?: return ("Latest · \(i + 1) of \(playback.queue.count)", "clock")
        case .watchLater?, .longWatchLater?: return ("\(i + 1) of \(playback.queue.count)", "tray.and.arrow.down")
        case .bookmarks?, .longBookmarks?: return ("\(i + 1) of \(playback.queue.count)", "bookmark")
        case .top?: return ("\(i + 1) of \(playback.queue.count)", "star")
        default: return nil
        }
    }
}

extension View {
    /// A Liquid Glass button on iOS 26 (tinted when `prominent`), the bordered look before that.
    @ViewBuilder func glassButtonStyle(prominent: Bool = false) -> some View {
        Group {
            if #available(iOS 26, *) {
                if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
            } else if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
    }
}

/// Long videos: play the next one when a video ends, or not. Filled while it's on.
private struct AutoplayButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GlassIconButton(symbol: "play.square.stack", label: "", tint: app.autoplayLong ? .accentColor : nil) {
            app.autoplayLong.toggle()
        }
        .accessibilityLabel(app.autoplayLong ? "Autoplay is on" : "Autoplay is off")
        .accessibilityAddTraits(app.autoplayLong ? .isSelected : [])
    }
}

/// A long-video creator or playlist from the sidebar: its gallery, as on the Mac. Picking a video plays it, with the
/// creator's videos beside the player; All Videos (or the video ending, with autoplay off) brings the gallery back.
private struct LongCreatorDetail: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(\.wideColumnWidth) private var columnWidth
    @Environment(\.wideQueueAsSheet) private var queueAsSheet
    @Environment(\.toggleSidebar) private var toggleSidebar
    let username: String
    @AppStorage("queueHidden") private var queueHidden = false
    @State private var showGallery = true
    @State private var showQueue = false

    private var library: CreatorLibrary? { app.library(username, form: .long) }
    private var mode: PlaybackMode { .longCreator(username) }
    private var isLoaded: Bool { playback.mode == mode && playback.current != nil }
    private var ended: Bool { playback.awaitingNext || playback.finished }

    var body: some View {
        Group {
            if showGallery || !isLoaded {
                gallery
            } else {
                player
            }
        }
        .onAppear { showGallery = !(isLoaded && !ended) }
        .onChange(of: ended) { _, ended in
            if ended && isLoaded { withAnimation(.snappy) { showGallery = true } }
        }
    }

    @ViewBuilder private var gallery: some View {
        if let library {
            LongGallery(library: library) { index in
                playback.start(app.longVideos(library), at: index, mode: mode)
                withAnimation(.snappy) { showGallery = false }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // iPhone Duo in portrait: the sidebar button, as the player's top bar would have it.
                if let toggleSidebar {
                    GlassIconButton(symbol: "line.3.horizontal", label: "Show Sidebar", action: toggleSidebar.callAsFunction)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
        } else {
            ContentUnavailableView("No Videos Yet", systemImage: "rectangle.stack")
        }
    }

    private var player: some View {
        HStack(spacing: 0) {
            if !queueHidden && !queueAsSheet {
                queueList.frame(width: columnWidth).transition(.move(edge: .leading))
                Divider()
            }
            PlayerPane()
                .overlay(alignment: .top) {
                    PlayerTopBar(title: library?.creator.displayName ?? "@\(creatorHandle(username))",
                                 subtitle: library.map { "\(app.unplayedCount($0)) unwatched · \($0.videos.count) videos" }) {
                        AutoplayButton()
                        GlassIconButton(symbol: "square.grid.2x2", label: "All Videos") {
                            playback.pause()
                            withAnimation(.snappy) { showGallery = true }
                        }
                    }
                    .environment(\.showQueueSheet, queueAsSheet ? ViewAction { showQueue = true } : nil)
                }
        }
        .modifier(SideToolbar(showQueue: { showQueue = true }) {
            Button {
                playback.pause()
                withAnimation(.snappy) { showGallery = true }
            } label: {
                Label("All Videos", systemImage: "square.grid.2x2")
            }
        })
        .sheet(isPresented: $showQueue) { QueueListSheet { queueList } }
    }

    private var queueList: some View {
        QueueList(videos: library.map(app.longVideos) ?? [], showCreator: library?.creator.isPlaylist == true,
                  emptyText: "Videos appear here after the next sync.") { index in
            if let library { playback.start(app.longVideos(library), at: index, mode: mode) }
            showQueue = false
        }
    }
}
