import AVKit
import SwiftUI

enum SidebarItem: Hashable {
    /// A nil category means all creators; `picked` limits Automix or Top to some of the sidebar's cards
    /// (`PlaybackMode.automix`).
    case automix(UUID?, picked: Set<String>? = nil), latest(UUID?), top(UUID?, picked: Set<String>? = nil)
    case creator(String), watchLater, bookmarks, ipod, manage
    /// The Vine card's Automix.
    case vineAutomix
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    @Environment(\.openSettings) private var openSettings
    @State private var selection: SidebarItem?
    /// Where the other form's sidebar was, to go back to when switching between short and long videos.
    @State private var otherSelection: SidebarItem?
    @AppStorage("otherCreatorsExpanded") private var otherCreatorsExpanded = true
    @AppStorage("vineExpanded") private var vineExpanded = true
    @AppStorage("queueHidden") private var queueHidden = false
    @State private var showSync = false
    /// Where the sidebar was before Creators & Downloads, for its button to go back to when nothing is playing.
    @State private var beforeManage: SidebarItem?
    /// Holding Automix or Top (or Option-clicking it): the popover picking which cards it plays from.
    @State private var picking: MixPick?
    /// Curated opens on Automix with its queue listed but nothing playing; picking anything in the sidebar ends that,
    /// and mixes play as soon as they're opened again.
    @State private var holdingLaunchMix = true
    /// Always `.all`: the sidebar can't be hidden (the queue beside the player can instead).
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var form: VideoForm { model.form }

    /// Where the currently loaded video lives in the sidebar (of `playback.form`).
    private var nowPlayingItem: SidebarItem? {
        guard playback.current != nil else { return nil }
        switch playback.mode {
        case .creator(let username): return .creator(username)
        case .automix(let category, let picked): return .automix(category, picked: picked)
        case .latest(let category): return .latest(category)
        case .top(let category, let picked): return .top(category, picked: picked)
        case .watchLater: return .watchLater
        case .bookmarks: return .bookmarks
        case .ipod: return .ipod
        case .vineAutomix: return .vineAutomix
        case nil: return nil
        }
    }

    /// Categories with a card in this form's sidebar: all of them for short videos (an empty one stays as a
    /// collapsed card), only those with a long-video creator for long ones.
    private var shownCategories: [Category] {
        form == .short ? model.categories : model.categories.filter { !model.watchLibraries(.long, in: $0.id).isEmpty }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section("Watch") {
                    mixTiles
                    savedButtons
                }
                Section("Creators") {
                    ForEach(shownCategories) { category in
                        CreatorCard(title: category.name, symbol: category.symbol,
                                    libraries: model.watchLibraries(form, in: category.id),
                                    isExpanded: Binding(get: { !category.collapsed },
                                                        set: { model.setCollapsed(!$0, for: category.id) }),
                                    category: category.id, selection: $selection)
                    }
                    let uncategorized = model.uncategorizedWatchLibraries(form)
                    if !uncategorized.isEmpty {
                        CreatorCard(title: shownCategories.isEmpty ? "All Creators" : "Other Creators", symbol: nil,
                                    libraries: uncategorized,
                                    isExpanded: $otherCreatorsExpanded, selection: $selection)
                    }
                    // The authors of every Vine downloaded, each like a creator.
                    if form == .short, !model.vineLibraries.isEmpty {
                        CreatorCard(title: "Vine", symbol: nil, vineLogo: true, libraries: model.vineLibraries,
                                    isExpanded: $vineExpanded, selection: $selection)
                    }
                    // Always the last card.
                    if form == .long, !model.playlistLibraries.isEmpty {
                        PlaylistsCard(playlists: model.playlistLibraries, selection: $selection)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // The long-video sidebar has its own wordmark (landscape cards).
                LogoView(height: 30, long: form == .long)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { sidebarFooter }
            .scrollContentBackground(.hidden)
            .background(PaneBackground().ignoresSafeArea())
            // A fixed width, so resizing the window only resizes the detail beside it.
            .navigationSplitViewColumnWidth(290)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(minWidth: detailMinWidth)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailHeight = $0 }
                .id(selection)  // fresh view (and onAppear) for each queue, e.g. switching between categories
                .id(form)
        }
        .onChange(of: columnVisibility) { _, visibility in
            if visibility != .all { columnVisibility = .all }
        }
        .onAppear {
            if selection == nil { selection = defaultSelection(form) }
            #if DEBUG
            // Lets a test open a screen without clicking: CURATED_TEST_SELECT=latest, automix, manage or creator:<id>.
            switch ProcessInfo.processInfo.environment["CURATED_TEST_SELECT"] {
            case "latest"?: selection = .latest(nil)
            case "automix"?: selection = .automix(nil)
            case "manage"?: selection = .manage
            case let item? where item.hasPrefix("creator:"): selection = .creator(String(item.dropFirst(8)))
            default: break
            }
            // CURATED_TEST_THEN_MANAGE=1 opens Creators & Downloads a few seconds in (after the selected screen starts
            // playing), to see the sidebar's Now Playing bar.
            if ProcessInfo.processInfo.environment["CURATED_TEST_THEN_MANAGE"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { toggleManage() }
            }
            // CURATED_TEST_PICK_OLDER=<creator id> opens that creator's older-videos picker.
            if let id = ProcessInfo.processInfo.environment["CURATED_TEST_PICK_OLDER"],
               let creator = model.config.creators.first(where: { $0.id == id }) {
                model.pickOlderLong(creator)
            }
            // CURATED_TEST_PICK=automix or top opens that mix's category picker.
            switch ProcessInfo.processInfo.environment["CURATED_TEST_PICK"] {
            case "automix"?: picking = .automix
            case "top"?: picking = .top
            default: break
            }
            // CURATED_TEST_PHONE=1 switches to Phone view after a moment.
            if ProcessInfo.processInfo.environment["CURATED_TEST_PHONE"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if playback.current == nil, let library = model.libraries.first(where: { !$0.videos.isEmpty }) {
                        playback.start(library.videos, mode: .creator(library.id), form: library.form)
                    }
                    PhoneMode.shared.enter(from: NSApp.windows.first { $0.isVisible && $0.contentView != nil },
                                           model: model, playback: playback, toggleTimeLimit: nil)
                }
            }
            // CURATED_TEST_RESET=library or everything runs Delete Library or Reset Everything after a moment. Only for a
            // test run with its own data folder and library, so it can never reach the real ones.
            if let what = ProcessInfo.processInfo.environment["CURATED_TEST_RESET"], Paths.dataDirOverride != nil,
               model.settings.libraryURL.standardizedFileURL != Paths.defaultLibrary.standardizedFileURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if what == "everything" { model.resetEverything(stopping: playback) } else { model.deleteLibrary() }
                }
            }
            // CURATED_TEST_SETTINGS=<pane> opens Settings on that section.
            if ProcessInfo.processInfo.environment["CURATED_TEST_SETTINGS"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { openSettings() }
            }
            // CURATED_TEST_SWITCH_FORM: switches sidebars by itself after 2 seconds, as the Short | Long pill does.
            if ProcessInfo.processInfo.environment["CURATED_TEST_SWITCH_FORM"] != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { switchForm() }
            }
            // CURATED_TEST_SNAPSHOT=<folder>: after a few seconds, saves each window as a PNG there (works without
            // screen recording, e.g. with the display asleep).
            if let folder = ProcessInfo.processInfo.environment["CURATED_TEST_SNAPSHOT"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { saveWindowSnapshots(to: folder) }
            }
            #endif
        }
        // Here rather than in Creators & Downloads, since a creator's gallery opens it too.
        .sheet(isPresented: Binding(get: { model.longPick?.shown ?? false }, set: { if !$0 { model.closeLongPick() } })) {
            LongPickerView()
        }
        .onChange(of: playback.closedVideos) { holdingLaunchMix = true }
        .onChange(of: playback.syncedVideoLoads) {
            if form == .long, let nowPlayingItem { selection = nowPlayingItem }
        }
        .onChange(of: selection) { old, new in
            // The first selection is the one made at launch.
            if old != nil { holdingLaunchMix = false }
            // Picking a creator from a mix shows their videos, even if the mix had its queue hidden.
            if case .creator? = new {
                if case .creator? = old {} else { queueHidden = false }
            }
        }
        .onChange(of: model.categories) { _, categories in
            // Leave a deleted category's queue.
            switch selection {
            case .automix(let id?, _), .latest(let id?), .top(let id?, _):
                if !categories.contains(where: { $0.id == id }) { selection = defaultSelection(form) }
            default: break
            }
        }
    }

    /// The mixes as tiles, as on iOS: Automix and Top 15, or for long videos Latest and Automix. The open one is filled
    /// with its color. Holding Automix or Top (or Option-clicking it) picks which cards it plays from. One untagged
    /// list row, so its buttons handle selection instead of the List.
    private var mixTiles: some View {
        HStack(spacing: 8) {
            switch form {
            case .short:
                let unplayed = model.unplayedCount(in: nil, form: .short)
                mixTile(.automix(nil), symbol: "shuffle", tint: .logoRed, title: "Automix",
                        subtitle: unplayed > 0 ? "\(unplayed) unwatched" : "All caught up", pick: .automix)
                mixTile(.top(nil), symbol: "star.fill", tint: .topTint,
                        title: "Top \(PlaybackMode.topCount(nil, form: .short))", subtitle: "Most viewed", pick: .top)
            case .long:
                let unwatched = model.unplayedCount(in: nil, form: .long)
                mixTile(.latest(nil), symbol: "clock", tint: .logoRed, title: "Latest",
                        subtitle: unwatched > 0 ? "\(unwatched) unwatched" : "All caught up", pick: nil)
                mixTile(.automix(nil), symbol: "shuffle", tint: .topTint, title: "Automix", subtitle: "Mixed creators",
                        pick: .automix)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
    }

    private func mixTile(_ item: SidebarItem, symbol: String, tint: Color, title: String, subtitle: String,
                         pick: MixPick?) -> some View {
        // The launch mix isn't filled in until it's clicked (or anything else is picked).
        MixTile(symbol: symbol, tint: tint, title: title, subtitle: subtitle,
                selected: selection == item && !holdingLaunchMix,
                hold: pick.map { pick in { picking = pick } }) { startMix(item) }
            .popover(isPresented: Binding(get: { pick != nil && picking == pick }, set: { if !$0 { picking = nil } }),
                     arrowEdge: .trailing) {
                if let pick {
                    MixPicker(pick: pick, form: form) { picked in
                        picking = nil
                        startMix(pick == .top ? .top(nil, picked: picked) : .automix(nil, picked: picked))
                    }
                }
            }
    }

    /// Watch Later, Bookmarks and the iPod list as square icon buttons on the right, as on iOS, each while something
    /// is saved (or its list is open, so the selection doesn't vanish mid-list). Clicking one lists its videos in a
    /// popover; picking one plays that list from there.
    @ViewBuilder private var savedButtons: some View {
        let laterCount = model.watchLaterVideos(form).count
        let bookmarkCount = model.bookmarkedVideos(form).count
        let ipodVideos = model.ipodVideos(form)
        let showLater = laterCount > 0 || selection == .watchLater
        let showBookmarks = bookmarkCount > 0 || selection == .bookmarks
        let showIPod = !ipodVideos.isEmpty || selection == .ipod
        if showLater || showBookmarks || showIPod {
            HStack(spacing: 8) {
                Spacer()
                if showLater {
                    SavedButton(symbol: "tray.and.arrow.down", title: "Watch Later", videos: model.watchLaterVideos(form),
                                selected: selection == .watchLater) { playSaved(.watchLater, $0, at: $1) }
                }
                if showBookmarks {
                    SavedButton(symbol: "bookmark.fill", title: "Bookmarks", videos: model.bookmarkedVideos(form),
                                selected: selection == .bookmarks) { playSaved(.bookmarks, $0, at: $1) }
                }
                if showIPod {
                    SavedButton(symbol: "ipod", title: "On iPod", videos: ipodVideos,
                                selected: selection == .ipod,
                                actions: [SavedListAction(title: "Mark All as Watched", symbol: "eye") {
                                              model.setPlayed(ipodVideos, true)
                                          },
                                          SavedListAction(title: "Clear List", symbol: "xmark.circle", destructive: true) {
                                              model.clearIPodList(form)
                                          }]) { playSaved(.ipod, $0, at: $1) }
                }
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
        }
    }

    /// A video picked from Watch Later or Bookmarks: plays that list from there, with the list beside the player.
    private func playSaved(_ item: SidebarItem, _ videos: [Video], at index: Int) {
        holdingLaunchMix = false
        playback.start(videos, at: index, mode: item == .bookmarks ? .bookmarks : item == .ipod ? .ipod : .watchLater, form: form)
        selection = item
    }

    /// The queue behind a mix in the sidebar.
    private func queue(for item: SidebarItem) -> [Video] {
        let videos = mixVideos(item)
        return form == .long ? model.handPickedFirst(videos) : videos
    }

    private func mixVideos(_ item: SidebarItem) -> [Video] {
        switch item {
        case .automix(let categoryID, let picked):
            // Bookmarked videos are kept for their own list, not mixed in.
            Library.automixQueue(picked.map { model.automixLibraries(form, picked: $0) } ?? model.automixLibraries(form, in: categoryID),
                                 excluding: model.played.union(model.bookmarkedIDs))
        case .vineAutomix:
            Library.automixQueue(model.vineLibraries, excluding: model.played.union(model.bookmarkedIDs))
        case .latest(let categoryID):
            Library.latestQueue(model.mixLibraries(.long, in: categoryID), excluding: model.played)
        case .top(let categoryID, let picked):
            Library.topQueue(picked.map { model.mixLibraries(form, picked: $0) } ?? model.mixLibraries(form, in: categoryID),
                             excluding: model.played, count: PlaybackMode.topCount(categoryID, form: form))
        case .watchLater: model.watchLaterVideos(form)
        case .bookmarks: model.bookmarkedVideos(form)
        case .ipod: model.ipodVideos(form)
        case .creator, .manage: []
        }
    }

    /// Opens a mix with a new queue, even when it's the one already playing (Now Playing carries on instead).
    private func startMix(_ item: SidebarItem) {
        let mode: PlaybackMode
        switch item {
        case .automix(let c, let p): mode = .automix(c, picked: p)
        case .top(let c, let p): mode = .top(c, picked: p)
        case .latest(let c): mode = .latest(c)
        default: selection = item; return
        }
        holdingLaunchMix = false
        playback.start(queue(for: item), mode: mode, form: form)
        selection = item
    }

    private func defaultSelection(_ form: VideoForm) -> SidebarItem {
        switch form {
        case .short: (model.libraries + model.vineLibraries).contains { !$0.videos.isEmpty } ? .automix(nil) : .manage
        case .long: .latest(nil)
        }
    }

    /// Selects `item` in `form`'s sidebar, switching sidebars first if needed.
    private func show(_ item: SidebarItem, in newForm: VideoForm) {
        if newForm != form {
            otherSelection = selection
            model.form = newForm
        }
        selection = item
    }

    /// Swaps between the short and long sidebars, back to wherever the other one was.
    private func switchForm() {
        let newForm: VideoForm = form == .short ? .long : .short
        // The long video last playing on any device is ready to go, rather than Latest starting by itself.
        if newForm == .long, playback.loadSyncedVideo(switching: true), let nowPlayingItem {
            holdingLaunchMix = false
            show(nowPlayingItem, in: newForm)
            return
        }
        show(otherSelection ?? defaultSelection(newForm), in: newForm)
    }

    private func showNowPlaying() {
        if let nowPlayingItem { show(nowPlayingItem, in: playback.form) }
    }

    /// Fixed icon row at the bottom of the sidebar: Creators & Downloads (a toggle back to the video), Phone Sync, the
    /// Short | Long pill and Settings. Above it, the Now Playing bar while a video is loaded and another
    /// screen is open, and while a download runs, its progress, Stop and what it's doing.
    private var sidebarFooter: some View {
        let nowPlayingHere = nowPlayingItem != nil && selection == nowPlayingItem && form == playback.form
        return VStack(spacing: 0) {
            if nowPlayingItem != nil && !nowPlayingHere {
                Divider()
                SidebarNowPlaying(show: showNowPlaying)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.isDownloading {
                Divider()
                SidebarDownloadBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if IPodExporter.shared.isRunning {
                Divider()
                SidebarIPodBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            HStack {
                // A toggle: into Creators & Downloads, and from there back to the video (or wherever the sidebar was).
                Button(action: toggleManage) {
                    Image(systemName: "person.crop.square.on.square.angled.fill")
                        .foregroundStyle(selection == .manage ? Color.accentColor : Color.primary)
                }
                .help(selection == .manage ? (nowPlayingItem == nil ? "Back" : "Back to the video") : "Creators & Downloads")
                Spacer()
                Button {
                    showSync.toggle()
                } label: {
                    // Slashed (and plain) while phones can't find this Mac: sync off, or hidden.
                    let findable = model.settings.syncEnabled && model.settings.syncDiscoverable
                    Image(systemName: findable ? "ipad.landscape.and.iphone" : "ipad.landscape.and.iphone.slash")
                        .foregroundStyle(model.usbSyncActive ? Color.red : findable ? Color.accentColor : Color.primary)
                }
                .help(!model.settings.syncEnabled ? "Phone sync is off"
                      : (model.settings.syncDiscoverable ? "Phone sync · discoverable" : "Phone sync · hidden")
                        + (model.usbSyncActive ? " · USB active" : ""))
                .popover(isPresented: $showSync, arrowEdge: .top) { SyncPopover() }
                Spacer()
                FormPill(form: form) { if $0 != form { switchForm() } }
                Spacer()
                SettingsLink {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 21.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
        .animation(.easeOut(duration: 0.25), value: model.isDownloading)
        .animation(.easeOut(duration: 0.25), value: nowPlayingHere)
    }

    /// Creators & Downloads' button: opens it, or from it goes back to what's playing, or else where the sidebar was.
    private func toggleManage() {
        guard selection == .manage else {
            beforeManage = selection
            selection = .manage
            return
        }
        if nowPlayingItem != nil {
            showNowPlaying()
        } else {
            selection = beforeManage.flatMap { $0 == .manage ? nil : $0 } ?? defaultSelection(form)
        }
    }

    @State private var detailHeight: CGFloat = 0

    /// Creators & Downloads needs room for a long-video creator's row (1210 wide with the sidebar), and the window
    /// widens to it. The short player needs room for the queue beside it, or with its queue hidden, can narrow to the
    /// video it's playing (never asking for more than with the queue, so a landscape video never widens the window).
    private var detailMinWidth: CGFloat {
        if selection == .manage || selection == nil { return 920 }
        guard form == .short, queueHidden, detailHeight > 0 else { return 640 }
        let aspect = playback.videoAspect ?? 9 / 16
        return min(640, max(240, (detailHeight * aspect).rounded(.up)))
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .automix(let categoryID, let picked):
            let name = model.category(categoryID).map { "\($0.name) " } ?? ""
            QueueView(mode: .automix(categoryID, picked: picked), form: form, title: "\(name)Automix", autoplay: !holdingLaunchMix,
                      emptyText: "No unwatched videos. Automix alternates between creators' unwatched videos — check back after the next download.") {
                queue(for: .automix(categoryID, picked: picked))
            }
        case .vineAutomix:
            QueueView(mode: .vineAutomix, form: .short, title: "Vine Automix",
                      emptyText: "No unwatched Vines. Download more from the Vine row in Creators & Downloads.") {
                queue(for: .vineAutomix)
            }
        case .latest(let categoryID):
            let name = model.category(categoryID).map { "\($0.name) " } ?? ""
            QueueView(mode: .latest(categoryID), form: .long, title: "\(name)Latest",
                      emptyText: model.longLibraries.isEmpty
                        ? "No long videos yet. In Creators & Downloads, light up the wide video icon on a YouTube creator to download their long videos."
                        : "No unwatched long videos — check back after the next download.") {
                queue(for: .latest(categoryID))
            }
        case .top(let categoryID, let picked):
            let name = model.category(categoryID).map { "\($0.name) " } ?? ""
            QueueView(mode: .top(categoryID, picked: picked), form: form,
                      title: "\(name)Top \(PlaybackMode.topCount(categoryID, form: form))",
                      emptyText: "No unwatched videos right now — check back after the next download.") {
                queue(for: .top(categoryID, picked: picked))
            }
        case .watchLater:
            QueueView(mode: .watchLater, form: form, title: "Watch Later",
                      emptyText: "Nothing saved. Use the Watch Later button in the player to set a video aside for later.") {
                queue(for: .watchLater)
            }
        case .bookmarks:
            QueueView(mode: .bookmarks, form: form, title: "Bookmarks",
                      emptyText: "No bookmarks. Use the bookmark button in the player to keep a video; bookmarked videos stay out of Automix and aren't deleted automatically.") {
                queue(for: .bookmarks)
            }
        case .ipod:
            QueueView(mode: .ipod, form: form, title: "On iPod",
                      emptyText: "Nothing exported. Videos you export in Settings > iPod are listed here.") {
                queue(for: .ipod)
            }
        case .creator(let username):
            if let lib = model.library(for: username, form: form) {
                if form == .long { LongCreatorView(library: lib) } else { CreatorWatchView(library: lib) }
            } else {
                ContentUnavailableView("Nothing here", systemImage: "person.crop.circle.badge.questionmark")
            }
        case .manage, nil:
            ManageView()
        }
    }
}

#if DEBUG
/// For tests: each visible window's content as `window-<n>.png` in `folder`.
@MainActor func saveWindowSnapshots(to folder: String) {
    for (i, window) in NSApp.windows.enumerated() where window.isVisible {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent("window-\(i).png"))
    }
}
#endif

/// Blurs whatever is behind the window (other windows, the desktop), like Finder's sidebar. Unlike Finder's, it stays
/// blurred when the window isn't in front.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Short | Long as a pill of both marks in the sidebar's icon row, the current one on a raised segment.
struct FormPill: View {
    let form: VideoForm
    let select: (VideoForm) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment(.short)
            segment(.long)
        }
        .padding(2)
        .background(.quaternary.opacity(0.7), in: Capsule())
    }

    private func segment(_ option: VideoForm) -> some View {
        let on = form == option
        return Button { select(option) } label: {
            FormMark(form: option, height: 21)
                .saturation(on ? 1 : 0.2)
                .opacity(on ? 1 : 0.6)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    if on { Capsule().fill(.background).shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(option == .short ? "Short videos" : "Long videos")
        .accessibilityLabel(option == .short ? "Short videos" : "Long videos")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// While a video is loaded and another screen is open: the video itself, live, with its creator and caption, and
/// previous, play/pause and next. Clicking the video or its text goes back to it.
struct SidebarNowPlaying: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let show: () -> Void

    var body: some View {
        if let video = playback.current {
            let long = video.form == .long
            HStack(alignment: .top, spacing: 10) {
                Button(action: show) {
                    LivePlayerView(player: playback.player)
                        .frame(width: long ? 148 : 56, height: long ? 84 : 100)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Go to Now Playing")
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: show) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.library(for: video.creator, form: video.form)?.displayName ?? "@\(video.creator)")
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Text(video.caption.isEmpty ? "No caption" : video.caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(long ? 2 : 3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Go to Now Playing")
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Button { playback.previous() } label: { control("backward.end.fill", size: 13) }
                            .disabled(!playback.hasPrevious)
                            .help("Previous video")
                        Button { playback.togglePlayPause() } label: {
                            control(playback.isPlaying ? "pause.fill" : "play.fill", size: 17)
                        }
                        .disabled(playback.finished)
                        .help(playback.isPlaying ? "Pause" : "Play")
                        Button { playback.next() } label: { control("forward.end.fill", size: 13) }
                            .disabled(playback.finished)
                            .help("Next video")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(height: long ? 84 : 100)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func control(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .frame(width: 28, height: 26)
            .contentShape(Rectangle())
    }
}

/// A second, live picture of the playing video (an AVPlayerLayer on Playback's player), filling its frame. It never
/// takes clicks, so the button around it does.
struct LivePlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> LiveView {
        let view = LiveView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: LiveView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class LiveView: NSView {
        let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
        }

        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// The running download, above the sidebar's icon row: a progress bar with Stop beside it, and what it's doing under.
struct SidebarDownloadBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ProgressView(value: model.downloadProgress ?? 0)
                    .progressViewStyle(.linear)
                    .animation(.easeOut(duration: 0.4), value: model.downloadProgress)
                    .accessibilityLabel("Download progress")
                Button { model.cancelDownloads() } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .help("Stop downloading")
                .accessibilityLabel("Stop")
            }
            Text(model.lastActivity ?? "Starting…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// A category's creators as a collapsible card: a header row with its mixes, then the avatar grid.
/// One untagged list row, so its buttons handle selection instead of the List.
struct CreatorCard: View {
    @Environment(AppModel.self) private var model
    let title: String
    let symbol: String?
    /// The Vine card shows the Vine V in place of a symbol.
    var vineLogo = false
    let libraries: [CreatorLibrary]
    @Binding var isExpanded: Bool
    /// For a category: shows its Automix and Top buttons in the header.
    var category: UUID? = nil
    @Binding var selection: SidebarItem?
    /// Also shows creators with nothing new (dimmed). Not saved.
    @State private var showCaughtUp = false
    /// Opened by hand while it has nothing to play; not saved, unlike `isExpanded`.
    @State private var openedWhileEmpty = false

    var body: some View {
        let unplayed = libraries.reduce(0) { $0 + model.unplayedCount($1) }
        // Nothing to play: stays collapsed unless opened here, and goes back to its saved state once videos arrive.
        let expanded = unplayed > 0 ? isExpanded : openedWhileEmpty
        let caughtUp = libraries.filter { model.unplayedCount($0) == 0 }.count
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        if unplayed > 0 { isExpanded.toggle() } else { openedWhileEmpty.toggle() }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 10)
                        if vineLogo {
                            VineGlyph(height: 13).foregroundStyle(.secondary)
                        } else if let symbol {
                            Image(systemName: symbol).foregroundStyle(.secondary)
                        }
                        Text(title).fontWeight(.semibold).lineLimit(1).layoutPriority(1)
                        UnplayedCountCapsule(count: unplayed)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Collapse" : unplayed > 0 ? "Expand" : "Expand · nothing new to watch")
                HStack(spacing: 0) {
                    caughtUpToggle(count: caughtUp, expanded: expanded, unplayed: unplayed)
                    if vineLogo {
                        SidebarIconButton(symbol: "shuffle", help: "Vine Automix", item: .vineAutomix, selection: $selection)
                    }
                    if let category {
                        if model.form == .long {
                            SidebarIconButton(symbol: "clock", help: "\(title) Latest",
                                              item: .latest(category), selection: $selection)
                        }
                        SidebarIconButton(symbol: "shuffle", help: "\(title) Automix",
                                          item: .automix(category), selection: $selection)
                        if model.form == .short {
                            SidebarIconButton(symbol: "star", help: "\(title) Top \(PlaybackMode.topCount(category))",
                                              item: .top(category), selection: $selection)
                        }
                    }
                }
            }
            if expanded {
                // An empty card has only caught-up creators, so opening it shows them.
                CreatorGrid(libraries: libraries, selection: $selection, showCaughtUp: showCaughtUp || unplayed == 0)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .cardBackground()
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        .listRowSeparator(.hidden)
    }

    /// Styled like the mix buttons beside it; highlighted while on.
    private func caughtUpToggle(count: Int, expanded: Bool, unplayed: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                showCaughtUp.toggle()
                if showCaughtUp && !expanded {
                    if unplayed > 0 { isExpanded = true } else { openedWhileEmpty = true }
                }
            }
        } label: {
            Image(systemName: "memories")
                .frame(width: 24, height: 20)
                .foregroundStyle(showCaughtUp ? Color.white : Color.secondary)
                .background(showCaughtUp ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(count == 0)
        .help(count == 0 ? "Everyone here has something new"
              : showCaughtUp ? "Hide \(count) caught-up creators" : "Show \(count) caught-up creators")
    }
}

/// A section's total unplayed count, in a small capsule beside its title. Hidden at zero.
struct UnplayedCountCapsule: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .fixedSize()
                .help("\(count) unwatched")
        }
    }
}

extension View {
    /// Liquid Glass on macOS 26, a soft tinted panel before that.
    @ViewBuilder func cardBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.quaternary.opacity(0.6), in: shape)
        }
    }
}

extension View {
    /// A Liquid Glass button on macOS 26 (tinted when `prominent`), the default bordered look before that.
    @ViewBuilder func glassButtonStyle(prominent: Bool = false) -> some View {
        Group {
            if #available(macOS 26, *) {
                if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
            } else if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
    }

    /// A floating Liquid Glass panel on macOS 26, bar material before that.
    @ViewBuilder func glassPanel() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.bar, in: shape)
        }
    }

    /// A floating Liquid Glass circle on macOS 26, thin material before that. A `tint` colors the glass.
    @ViewBuilder func glassCircle(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: Circle())
        } else if let tint {
            background(tint, in: Circle())
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
    }

    /// A floating Liquid Glass capsule on macOS 26, thin material before that. A `tint` colors the glass.
    @ViewBuilder func glassCapsule(tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: Capsule())
        } else if let tint {
            background(tint, in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// Drops the detail column's title bar so the content runs to the top of the window.
    @ViewBuilder func hiddenWindowTitleBar() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .ignoresSafeArea(.container, edges: .top)
        } else {
            self
        }
    }
}

/// A small borderless icon that selects a sidebar item, highlighted while it's selected.
struct SidebarIconButton: View {
    let symbol: String
    let help: String
    let item: SidebarItem
    @Binding var selection: SidebarItem?
    /// nil keeps the symbol's own width, so a row of differently shaped symbols gets even gaps.
    var width: CGFloat? = 24

    var body: some View {
        let selected = selection == item
        Button {
            selection = item
        } label: {
            Image(systemName: symbol)
                .frame(width: width, height: 20)
                .padding(.horizontal, width == nil ? 3 : 0)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Creators with something new, most unplayed first. The caught-up ones follow (dimmed) when `showCaughtUp` is on.
struct CreatorGrid: View {
    @Environment(AppModel.self) private var model
    let libraries: [CreatorLibrary]
    @Binding var selection: SidebarItem?
    let showCaughtUp: Bool

    var body: some View {
        let counted = libraries.map { (lib: $0, unplayed: model.unplayedCount($0)) }
        let fresh = counted.filter { $0.unplayed > 0 }
            .sorted {
                if $0.unplayed != $1.unplayed { return $0.unplayed > $1.unplayed }
                return $0.lib.displayName.localizedStandardCompare($1.lib.displayName) == .orderedAscending
            }
            .map(\.lib)
        // The selected creator stays in view even when caught up, so the selection never vanishes.
        let caughtUp = counted.filter { $0.unplayed == 0 }.map(\.lib)
            .filter { showCaughtUp || selection == .creator($0.id) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 4)], spacing: 10) {
            ForEach(fresh + caughtUp) { lib in
                CreatorGridCell(library: lib, size: 44, selected: selection == .creator(lib.id)) {
                    selection = .creator(lib.id)
                }
            }
        }
    }
}

struct CreatorGridCell: View {
    @Environment(AppModel.self) private var model
    let library: CreatorLibrary
    let size: CGFloat
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let unplayed = model.unplayedCount(library)
        let quiet = unplayed == 0 && !selected && !hovering
        Button(action: action) {
            AvatarView(library: library, size: size)
                .saturation(quiet ? 0 : 1)
                .opacity(quiet ? 0.45 : 1)
                .padding(3)
                .overlay {
                    Circle().stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                }
                .overlay(alignment: .topTrailing) {
                    if model.statuses[library.id] == .downloading {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(2)
                            .background(.background, in: Circle())
                    } else {
                        UnplayedBadge(count: unplayed).offset(x: 3, y: -1)
                    }
                }
                .onHover { hovering = $0 }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(library.displayName) · \(unplayed) unwatched · \(library.videos.count) total")
        .accessibilityLabel("\(library.displayName), \(unplayed) unwatched")
        .contextMenu {
            OpenCreatorButton(creator: library.creator)
            MarkAllMenuItems(library: library)
        }
    }
}

/// An app-icon-style count on an avatar's corner. Hidden at zero.
struct UnplayedBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 17, minHeight: 17)
                .background(Color.accentColor, in: Capsule())
                .overlay { Capsule().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5) }
                .fixedSize()
        }
    }
}

/// Holding or right-clicking a creator or playlist: its page on YouTube or TikTok. Vine authors and the Suggestions
/// playlist have none.
struct OpenCreatorButton: View {
    let creator: Creator

    var body: some View {
        if creator.platform != .vine && !creator.isSuggestions {
            Button("Open in \(creator.platform.name)") { NSWorkspace.shared.open(creator.profileURL) }
            Divider()
        }
    }
}

struct MarkAllMenuItems: View {
    @Environment(AppModel.self) private var model
    let library: CreatorLibrary

    var body: some View {
        Button("Mark All as Watched") { model.setPlayed(library.videos, true) }
            .disabled(model.unplayedCount(library) == 0)
        Button("Mark All as Unwatched") { model.setPlayed(library.videos, false) }
            .disabled(model.unplayedCount(library) == library.videos.count)
    }
}

// MARK: - Watching

struct CreatorWatchView: View {
    @Environment(Playback.self) private var playback
    let library: CreatorLibrary
    @AppStorage("queueHidden") private var queueHidden = false

    var body: some View {
        HStack(spacing: 0) {
            PlayerPane()
            // On the right, as in a mix's queue.
            if !queueHidden {
                Divider()
                VideoList(videos: library.videos, showCreator: false, emptyText: "No videos downloaded for \(library.displayName) yet.") { index in
                    playback.start(library.videos, at: index, mode: .creator(library.id), form: library.form)
                }
                .frame(width: 320)
                .transition(.move(edge: .trailing))
            }
        }
        .navigationTitle(library.displayName)
        .toolbar {
            Menu {
                MarkAllMenuItems(library: library)
            } label: {
                Label("Mark All", systemImage: "checkmark.circle")
            }
            .help("Mark all of this creator's videos as watched or unwatched")
            .disabled(library.videos.isEmpty)
        }
    }
}

/// A generated queue (Automix or Top N) with its list and player.
struct QueueView: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let mode: PlaybackMode
    let form: VideoForm
    let title: String
    /// Off at launch: the queue is listed, and nothing plays until a video is picked.
    var autoplay = true
    let emptyText: String
    let build: () -> [Video]
    @AppStorage("queueHidden") private var queueHidden = false

    var body: some View {
        Group {
            if form == .long { longBody } else { shortBody }
        }
        .navigationTitle(title)
        .hiddenWindowTitleBar()
        .onAppear {
            // Also starts the mix that was only listed at launch, once it's opened again.
            if !playback.isLoaded(mode, form: form) || autoplay && playback.current == nil { start() }
        }
    }

    /// Long videos: the player full width, its queue in an Up Next panel that slides up from the bottom.
    @ViewBuilder private var longBody: some View {
        if playback.isLoaded(mode, form: form) && !playback.queue.isEmpty {
            LongPlayerPane()
                .overlay(alignment: .topLeading) {
                    if mode.isOpenMix { QueueSummary().padding(12) }
                }
        } else {
            ContentUnavailableView {
                Label("No videos", systemImage: "film.stack")
            } description: {
                Text(emptyText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Short videos: the queue in a column beside the player.
    private var shortBody: some View {
        HStack(spacing: 0) {
            PlayerPane()
                .overlay(alignment: .topLeading) {
                    if mode.isOpenMix && playback.isLoaded(mode, form: form) {
                        QueueSummary().padding(12)
                    }
                }
                // The player's side column gets a Time Limit button too, for Automix.
                .environment(\.toggleTimeLimit, mode.isAutomix ? EnvironmentAction(id: [AnyHashable(mode), AnyHashable(form)], run: toggleTimeLimit) : nil)
                .focusedSceneValue(\.toggleTimeLimitFromMenu, mode.isAutomix ? EnvironmentAction(id: [AnyHashable(mode), AnyHashable(form)], run: toggleTimeLimit) : nil)
            // The queue is the rightmost pane, sliding out from the window's edge, so the video stays in the middle.
            if !queueHidden {
                Divider()
                VideoList(videos: playback.isLoaded(mode, form: form) ? playback.queue : [], showCreator: true,
                          emptyText: emptyText) { index in
                    playback.play(at: index)
                }
                .frame(width: 320)
                .transition(.move(edge: .trailing))
            }
        }
    }

    private var isTimeLimited: Bool { playback.isLoaded(mode, form: form) && playback.timeLimitMinutes != nil }

    private func toggleTimeLimit() {
        if isTimeLimited { endTimeLimit() } else { startTimeLimited() }
    }

    private func start() {
        // Holding back only applies to short videos; the long player has no empty state beside its queue.
        playback.start(build(), mode: mode, form: form, autoplay: autoplay || form == .long)
    }

    /// Back to the full mix, without interrupting the video that's playing.
    private func endTimeLimit() {
        playback.continueWith(build(), mode: mode)
    }

    private func startTimeLimited() {
        let queue = build()
        let minutes = model.settings.timeLimitMinutes
        Task {
            let limited = await Library.limitToDuration(queue, seconds: TimeInterval(minutes * 60))
            playback.start(limited, mode: mode, form: form, timeLimitMinutes: minutes)
        }
    }
}

/// "12 unwatched · 23:41 left" for the loaded queue. Its own view so the ticking clock only redraws this.
struct QueueSummary: View {
    @Environment(Playback.self) private var playback

    var body: some View {
        let count = playback.unwatched.count
        let timeLimited = playback.timeLimitMinutes != nil
        HStack(spacing: 6) {
            Text("\(count) unwatched")
            Text("·").foregroundStyle(timeLimited ? AnyShapeStyle(.white.opacity(0.6)) : AnyShapeStyle(.tertiary))
            // While a time limit runs: its countdown, on blue.
            Text(timeLimited ? formatClock(playback.secondsUntilEnd) : "\(formatClock(playback.unwatchedSecondsLeft)) left")
                .fontWeight(timeLimited ? .semibold : .regular)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(timeLimited ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassCapsule(tint: timeLimited ? .accentColor : nil)
        .help(timeLimited
              ? "Videos left in this time-limited mix, and how long until it ends"
              : "Videos in this mix you haven't started yet, and how long they'll take to watch (including the rest of the current video)")
    }
}

/// "4:05" or "1:02:09".
func formatClock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    let h = total / 3600, m = total / 60 % 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// "3h 12m", "45m" or "30s", for totals.
func formatLength(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = total / 60 % 60
    if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
    return m > 0 ? "\(m)m" : "\(total)s"
}

struct VideoList: View {
    @Environment(AppModel.self) private var model
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
                        VideoRow(video: video, isCurrent: playback.current?.id == video.id,
                                 isPlayed: model.isPlayed(video), isSaved: model.isSavedForLater(video),
                                 isBookmarked: model.isBookmarked(video),
                                 creator: showCreator ? model.library(for: video.creator, form: video.form) : nil)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(index) }
                            .contextMenu { VideoContextMenu(video: video) }
                            .id(video.id)
                    }
                }
                .listStyle(.plain)
                // See-through like the sidebar, but tinted a little more solid so the two panels read apart.
                .scrollContentBackground(.hidden)
                .background {
                    PaneBackground()
                        .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.45))
                        .ignoresSafeArea()
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

/// Played, Watch Later, Bookmark and Trash, for a video's right-click menu.
struct VideoContextMenu: View {
    @Environment(AppModel.self) private var model
    let video: Video

    var body: some View {
        if model.isPlayed(video) {
            Button("Mark as Unwatched") { model.setPlayed(video, false) }
        } else {
            Button("Mark as Watched") { model.setPlayed(video, true) }
            if model.isSavedForLater(video) {
                Button("Remove from Watch Later") { model.setWatchLater(video, false) }
            } else {
                Button("Save to Watch Later") { model.setWatchLater(video, true) }
            }
        }
        if model.isBookmarked(video) {
            Button("Remove Bookmark") { model.setBookmarked(video, false) }
        } else {
            Button("Bookmark") { model.setBookmarked(video, true) }
        }
        Divider()
        Button("Move to Trash", role: .destructive) { model.trash(video) }
    }
}

struct VideoRow: View {
    let video: Video
    let isCurrent: Bool
    let isPlayed: Bool
    let isSaved: Bool
    let isBookmarked: Bool
    /// Shown in bold above the caption in mixed queues.
    let creator: CreatorLibrary?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ThumbnailView(url: video.url)
                .frame(width: video.form == .long ? 128 : 54, height: video.form == .long ? 72 : 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isPlayed && !isCurrent ? 0.45 : 1)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                        Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                if let creator {
                    Text(creator.displayName).font(.subheadline.weight(.bold))
                }
                Text(video.caption.isEmpty ? "No caption" : video.caption)
                    .font(.callout)
                    .foregroundStyle(video.caption.isEmpty || isPlayed ? .secondary : .primary)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    if isPlayed {
                        Label("Watched", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                        Text("·")
                    } else if isSaved {
                        Label("Later", systemImage: "tray.and.arrow.down.fill")
                            .labelStyle(.titleAndIcon)
                        Text("·")
                    }
                    if isBookmarked {
                        Image(systemName: "bookmark.fill").help("Bookmarked")
                        Text("·")
                    }
                    Text(video.date, format: .relative(presentation: .named))
                    if let views = video.viewCount {
                        Text("·")
                        Text("\(views.formatted(.number.notation(.compactName))) views")
                    }
                    if let d = video.duration {
                        Text("·")
                        Text(formatClock(TimeInterval(d)))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        // Which platform it's from, in the corner.
        .overlay(alignment: .bottomTrailing) {
            PlatformIcon(platform: video.creator.hasPrefix("youtube@") ? .youtube
                         : video.creator.hasPrefix(Vine.folderPrefix) ? .vine : .tiktok, size: 13)
                .padding(.trailing, 4)
                .padding(.bottom, 6)
        }
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

struct PlayerPane: View {
    @Environment(Playback.self) private var playback
    /// Long videos: skip back and ahead in place of previous and next, and AVKit's own full screen.
    var long = false
    @State private var fullScreen = PlayerFullScreen()

    var body: some View {
        // The video fills the pane; who, what and the buttons sit over it, as on the phones and iPhone Duo.
        ZStack {
            Color.black
            if playback.current != nil {
                if long {
                    PlayerView(player: playback.player, fullScreen: fullScreen)
                } else {
                    // Short videos are on a tape: a two-finger swipe moves to the next or previous one.
                    VideoTape(pictureInPicture: fullScreen)
                }
                PlayerControls(long: long, enterFullScreen: long ? fullScreen.enter : nil, pictureInPicture: fullScreen)
            } else {
                VStack(spacing: 14) {
                    LogoView(height: 44, forceDark: true)
                        .opacity(0.55)
                    Text("Pick a video to start watching")
                        .foregroundStyle(.secondary)
                }
            }
            if playback.awaitingNext, let next = playback.upNext {
                UpNextCard(next: next)
            }
            if playback.finished {
                VStack(spacing: 10) {
                    if let minutes = playback.timeLimitMinutes {
                        Image(systemName: "sun.max.fill").font(.system(size: 44)).foregroundStyle(.yellow)
                        Text("Your \(minutes) minutes are up, now enjoy some sunshine!").font(.title2.weight(.semibold))
                        Text("That's the end of your time-limited mix.").foregroundStyle(.secondary)
                    } else if let limit = playback.mode?.topLimit(playback.form) {
                        Image(systemName: "sun.max.fill").font(.system(size: 44)).foregroundStyle(.yellow)
                        Text("You've reached the end, now enjoy some sunshine!").font(.title2.weight(.semibold))
                        Text("That's your \(limit) for now.").foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle").font(.system(size: 44))
                        Text("You're all caught up").font(.title2.weight(.semibold))
                        Text("No unwatched videos left here.").foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

/// Everything over the video. At the bottom, who posted it and what it says, over a fade, like the phones. Down the
/// right, the video's buttons in a column, in the iPhone Duo's order. Above the caption, floating glass controls:
/// previous, play/pause and next (in place of AVKit's rewind and fast-forward), a scrubber, mute, picture in picture and full screen,
/// shown while the pointer moves over the video and while it's paused. Clicking the video plays or pauses it.
/// For long videos, skip back and ahead 15 seconds in place of previous and next, like AVKit's full-screen controls,
/// and clear mode, as on Android: nothing over the video until it's clicked, then everything for 3 seconds after the
/// pointer last moves.
struct PlayerControls: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    @Environment(\.toggleTimeLimit) private var toggleTimeLimit
    var long = false
    /// Puts the video alone into full screen (AVKit's, with its own controls); otherwise the window goes full screen.
    var enterFullScreen: (() -> Void)?
    /// Floats the video in AVKit's picture in picture, so it keeps playing over other apps. Its button is beside
    /// full screen.
    var pictureInPicture: PlayerFullScreen?
    @State private var visible = true
    @State private var hideTask: Task<Void, Never>?
    /// Where the scrubber is being dragged to; the video seeks when it's let go.
    @State private var scrubbing: TimeInterval?
    @State private var muted = false
    @State private var overPanel = false
    /// The caption overlay's height, so the side column can sit above it and the hover controls.
    @State private var infoHeight: CGFloat = 0
    /// Where the controls were dragged to, as their center's fraction of the player's width and height, kept from
    /// video to video and between launches, like QuickTime's; -1 for the default spot, centered above the caption.
    @AppStorage("controlsX") private var savedX = -1.0
    @AppStorage("controlsY") private var savedY = -1.0
    @State private var panelSize = CGSize.zero
    /// The controls' center while they're being dragged, and where it was when the drag began.
    @State private var dragCenter: CGPoint?
    @State private var dragStart: CGPoint?
    /// Clear mode: everything is up after a click on the video, until `revealTask` hides it again.
    @State private var revealed = false
    @State private var revealTask: Task<Void, Never>?

    private var clear: Bool { long && playback.clearMode }
    private var controlsShown: Bool { !clear || revealed }

    /// Room kept for the hover controls (shown or not), so the column doesn't jump when they appear.
    private static let panelRoom: CGFloat = 196
    /// How far the long-video skip buttons jump, as in AVKit's controls.
    private static let skipSeconds: TimeInterval = 15

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    // In clear mode, a click while it's all hidden only brings it back.
                    if controlsShown { playback.togglePlayPause() }
                    if clear { reveal() }
                }
            if controlsShown, let video = playback.current {
                VideoInfoOverlay(video: video)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { infoHeight = $0 }
                    .transition(.opacity)
            }
            if controlsShown, let video = playback.current {
                // Up the right edge, ending above the hover controls so they can sit centered under it.
                VideoSideButtons(video: video)
                    .padding(.trailing, 14)
                    .padding(.top, 12)
                    .padding(.bottom, infoHeight + Self.panelRoom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }
            GeometryReader { geo in
                if clear ? revealed || scrubbing != nil || dragCenter != nil
                         : visible || !playback.isPlaying || scrubbing != nil || dragCenter != nil {
                    panel
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
                        .position(dragCenter ?? panelCenter(in: geo.size))
                        .gesture(move(in: geo.size))
                        .transition(.opacity)
                }
            }
        }
        .onContinuousHover { phase in
            // In clear mode, moving the pointer only keeps things up once a click has brought them back.
            if clear {
                if case .active = phase, revealed { reveal() }
                return
            }
            switch phase {
            case .active: show()
            case .ended: hideSoon(after: 0.4)
            }
        }
        .onAppear {
            muted = playback.player.isMuted
            hideSoon(after: 2.5)
        }
        .animation(.easeOut(duration: 0.2), value: visible)
        .animation(.easeOut(duration: 0.2), value: controlsShown)
    }

    private var duration: TimeInterval {
        let item = playback.player.currentItem?.duration.seconds
        return playback.current.flatMap { model.duration(of: $0) } ?? (item?.isFinite == true ? item! : 0)
    }

    private var panel: some View {
        let time = scrubbing ?? playback.currentTime
        return VStack(spacing: 8) {
            HStack(spacing: 22) {
                Button {
                    muted.toggle()
                    playback.player.isMuted = muted
                } label: {
                    Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 22)
                }
                .help(muted ? "Unmute" : "Mute")
                Spacer()
                if long {
                    Button { skip(-Self.skipSeconds) } label: { Image(systemName: "gobackward.15") }
                        .help("Back 15 seconds")
                } else {
                    Button { playback.previous() } label: { Image(systemName: "backward.end.fill") }
                        .disabled(!playback.hasPrevious)
                        .help("Previous (⌘←)")
                }
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26))
                        .frame(width: 30)
                }
                .disabled(playback.finished)
                .help(playback.isPlaying ? "Pause" : "Play")
                if long {
                    Button { skip(Self.skipSeconds) } label: { Image(systemName: "goforward.15") }
                        .disabled(playback.finished)
                        .help("Ahead 15 seconds")
                } else {
                    Button { playback.next() } label: { Image(systemName: "forward.end.fill") }
                        .disabled(playback.finished)
                        .help("Next (⌘→)")
                }
                Spacer()
                // Short videos keep Phone View up here; long videos have it in the row under the scrubber.
                if !long { phoneViewButton }
                if let pictureInPicture {
                    Button(action: pictureInPicture.togglePictureInPicture) {
                        Image(systemName: pictureInPicture.inPictureInPicture ? "pip.exit" : "pip.enter").frame(width: 22)
                    }
                    .help(pictureInPicture.inPictureInPicture ? "Exit Picture in Picture" : "Picture in Picture")
                }
                Button { if let enterFullScreen { enterFullScreen() } else { NSApp.keyWindow?.toggleFullScreen(nil) } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 22)
                }
                .help("Full Screen")
            }
            .font(.system(size: 17))
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Text(formatClock(time)).frame(minWidth: 40, alignment: .trailing)
                Slider(
                    value: Binding(get: { min(time, max(duration, 0.1)) }, set: { scrubbing = $0 }),
                    in: 0...max(duration, 0.1)
                ) { editing in
                    if !editing, let target = scrubbing {
                        playback.seek(to: target)
                        scrubbing = nil
                    }
                    if !editing, clear { reveal() }
                }
                .controlSize(.small)
                Text("-" + formatClock(max(0, duration - time))).frame(minWidth: 44, alignment: .leading)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            if long { longExtras }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: 420)
        .glassPanel()
        .environment(\.colorScheme, .dark)  // Over the video, like AVKit's own controls.
        .onHover { inside in
            // Stays up while the pointer is on it.
            overPanel = inside
            if clear {
                if !inside && revealed { reveal() }
            } else if inside { visible = true } else { hideSoon(after: 2.5) }
        }
        .padding(.horizontal, 16)
    }

    /// Phone view: the window steps aside for a floating phone playing the same queue.
    private var phoneViewButton: some View {
        Button {
            PhoneMode.shared.enter(from: NSApp.keyWindow, model: model, playback: playback,
                                   toggleTimeLimit: toggleTimeLimit)
        } label: {
            Image(systemName: "iphone").frame(width: 22)
        }
        .help("Phone View")
    }

    /// Long videos: a row under the scrubber with Phone View, QuickTime Player and clear mode.
    private var longExtras: some View {
        HStack(spacing: 30) {
            phoneViewButton
            if let video = playback.current {
                // Hands the file to QuickTime Player, pausing here (and saving the spot) so the two don't both play.
                Button {
                    playback.player.pause()
                    playback.savePosition()
                    if let quickTime = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.QuickTimePlayerX") {
                        NSWorkspace.shared.open([video.url], withApplicationAt: quickTime,
                                                configuration: NSWorkspace.OpenConfiguration())
                    } else {
                        NSWorkspace.shared.open(video.url)
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app").frame(width: 22)
                }
                .help("Open in QuickTime Player")
            }
            // Turning it on clears the screen straight away; off brings everything back.
            Button {
                playback.clearMode.toggle()
                revealed = false
                revealTask?.cancel()
                if !playback.clearMode { show() }
            } label: {
                // Shows what a click does, as on Android: a clear screen to clear it, the controls over it to keep them.
                ClearModeGlyph(overlaid: playback.clearMode).frame(width: 22)
            }
            .help(playback.clearMode ? "Clear mode is on: click the video to bring the controls back. Click to keep them up"
                                     : "Clear Mode: hide everything over the video until you click it")
        }
        .font(.system(size: 15))
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// Where the controls sit: where they were dragged to, kept inside the player, or centered above the caption.
    private func panelCenter(in size: CGSize) -> CGPoint {
        guard savedX >= 0, savedY >= 0 else {
            return CGPoint(x: size.width / 2, y: size.height - infoHeight - 10 - panelSize.height / 2)
        }
        return clamped(CGPoint(x: savedX * size.width, y: savedY * size.height), in: size)
    }

    private func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let halfWidth = panelSize.width / 2, halfHeight = panelSize.height / 2
        return CGPoint(x: min(max(point.x, halfWidth), max(halfWidth, size.width - halfWidth)),
                       y: min(max(point.y, halfHeight + 8), max(halfHeight + 8, size.height - halfHeight - 8)))
    }

    /// Dragging the controls by their background moves them anywhere over the video, like the system's floating
    /// controls. Double-clicking them puts them back above the caption.
    private func move(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = dragStart ?? panelCenter(in: size)
                dragStart = start
                dragCenter = clamped(CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height),
                                     in: size)
            }
            .onEnded { _ in
                if let dragCenter, size.width > 0, size.height > 0 {
                    savedX = dragCenter.x / size.width
                    savedY = dragCenter.y / size.height
                }
                dragCenter = nil
                dragStart = nil
                if clear { reveal() } else { hideSoon(after: 2.5) }
            }
            .simultaneously(with: TapGesture(count: 2).onEnded {
                withAnimation(.easeOut(duration: 0.2)) {
                    savedX = -1
                    savedY = -1
                }
            })
    }

    private func skip(_ seconds: TimeInterval) {
        playback.seek(to: min(max(0, playback.currentTime + seconds), max(0, duration - 1)))
        show()
    }

    private func show() {
        if clear {
            if revealed { reveal() }
            return
        }
        visible = true
        hideSoon(after: 2.5)
    }

    /// Clear mode: brings everything up, then hides it 3 seconds on (unless the pointer's on the controls by then).
    private func reveal() {
        revealed = true
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && !overPanel && scrubbing == nil { revealed = false }
        }
    }

    private func hideSoon(after seconds: Double) {
        #if DEBUG
        // CURATED_TEST_CONTROLS=1 keeps the controls up, for snapshots.
        if ProcessInfo.processInfo.environment["CURATED_TEST_CONTROLS"] != nil { return }
        #endif
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled && !overPanel { visible = false }
        }
    }
}

/// Clear mode's button: a laptop with a clear screen, or with a bar over its screen like the controls over a video.
struct ClearModeGlyph: View {
    let overlaid: Bool

    var body: some View {
        Image(systemName: "laptopcomputer")
            .overlay(alignment: .top) {
                if overlaid {
                    RoundedRectangle(cornerRadius: 1)
                        .frame(width: 13, height: 3)
                        .padding(.top, 8)
                }
            }
    }
}

/// Avatar, name, when (or where in the mix), views and the caption, over a fade at the bottom of the video.
struct VideoInfoOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let lib = model.library(for: video.creator, form: video.form) {
                    AvatarView(library: lib, size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.library(for: video.creator, form: video.form)?.displayName ?? "@\(video.creator)")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Text(video.date, format: .dateTime.month().day().hour().minute())
                        if let (text, symbol) = modeLabel { Label(text, systemImage: symbol) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let views = video.viewCount {
                    VStack(spacing: 2) {
                        Image(systemName: "eye")
                        Text(views.formatted(.number.notation(.compactName)))
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .help("\(views.formatted()) views")
                }
            }
            if video.form == .long && !video.title.isEmpty {
                Text(video.title).font(.title3.weight(.semibold)).lineLimit(2)
            }
            let text = video.form == .long ? video.details : video.caption
            if !text.isEmpty {
                ScrollView {
                    Text(text).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 60)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
    }

    private var modeLabel: (String, String)? {
        guard let i = playback.index else { return nil }
        let position = "\(i + 1) of \(playback.queue.count)"
        if let minutes = playback.timeLimitMinutes { return ("\(minutes)-min mix · \(position)", "timer") }
        switch playback.mode {
        case .automix?: return ("Automix", "shuffle")
        case .vineAutomix?: return ("Vine Automix", "shuffle")
        case .latest?: return ("Latest · \(position)", "clock")
        case .watchLater?: return (position, "tray.and.arrow.down")
        case .bookmarks?: return (position, "bookmark")
        case .ipod?: return (position, "ipod")
        case .top?: return (position, "star")
        default: return nil
        }
    }
}

extension EnvironmentValues {
    /// Turns the loaded Automix's time limit on or off; nil where there's no time limit (Top lists, creators).
    @Entry var toggleTimeLimit: EnvironmentAction? = nil
    /// Shows or hides the Up Next panel; set for long videos, whose queue slides up from the bottom.
    @Entry var toggleUpNext: EnvironmentAction? = nil
}

/// An action handed down through the environment. Closures can't be compared, so a bare closure would update every
/// view reading it on each change; this compares by `id` instead, which should be whatever the closure captures that
/// can change while the view stays put (`@State` doesn't count: the closure reads it when it runs).
struct EnvironmentAction: Equatable {
    var id: AnyHashable = 0
    let run: () -> Void

    func callAsFunction() { run() }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

/// The player's buttons in a column down the right of the video, in the iPhone Duo's order: at the top, show or hide
/// the queue and (in Automix) Time Limit; at the bottom, share, speed, then Watch Later, bookmark and played together.
struct VideoSideButtons: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    @Environment(\.toggleTimeLimit) private var toggleTimeLimit
    @Environment(\.toggleUpNext) private var toggleUpNext
    @AppStorage("queueHidden") private var queueHidden = false
    let video: Video

    var body: some View {
        VStack(spacing: 12) {
            if let toggleUpNext {
                Button { toggleUpNext() } label: { circleIcon("list.bullet") }
                    .glassCircle()
                    .help("Up Next")
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.3)) { queueHidden.toggle() }
                } label: { circleIcon("sidebar.right") }
                    .glassCircle()
                    .help(queueHidden ? "Show Queue" : "Hide Queue")
            }
            if video.form == .short {
                let on = playback.autoplayShort
                Button { playback.autoplayShort.toggle() } label: {
                    AutoplayGlyph(on: on, size: 20)
                        .frame(width: Self.circleSize, height: Self.circleSize)
                        .contentShape(Circle())
                }
                // The glyph alone shows which: an arrow with a dashed stem while on, slashed while off.
                .glassCircle()
                .help(on ? "Autoplay is on: the next video starts when this one ends. Click to play each video on a loop instead"
                         : "Autoplay is off: each video plays on a loop. Click to go on to the next video when one ends")
                .accessibilityLabel(on ? "Autoplay is on" : "Autoplay is off")
            }
            if video.form == .long {
                let on = playback.autoplayLong
                Button { playback.autoplayLong.toggle() } label: { circleIcon("play.square.stack") }
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .glassCircle(tint: on ? .accentColor : nil)
                    .help(on ? "Autoplay is on: the next video starts when this one ends. Click to turn it off"
                             : "Autoplay is off: playback stops at the end of each video. Click to turn it on")
            }
            if let toggleTimeLimit {
                let timeLimited = playback.timeLimitMinutes != nil
                Button { toggleTimeLimit() } label: { circleIcon("timer") }
                    .foregroundStyle(timeLimited ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .glassCircle(tint: timeLimited ? .accentColor : nil)
                    .disabled(!timeLimited && (model.libraries + model.vineLibraries).allSatisfy { model.unplayedCount($0) == 0 })
                    .help(timeLimited
                          ? "Turn off the time limit and go back to the full Automix"
                          : "Time Limit: a fresh mix of about \(model.settings.timeLimitMinutes) minutes, then it stops")
            }
            Spacer(minLength: 12)
            ShareLink(item: video.url) { circleIcon("square.and.arrow.up") }
                .glassCircle()
                .help("Share this video")
            Button { playback.cycleSpeed() } label: {
                Text(playback.shownSpeed == 1 ? "1×" : playback.shownSpeed == 2 ? "2×" : "1.5×")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: Self.circleSize, height: Self.circleSize)
                    .contentShape(Circle())
            }
            .disabled(playback.speedLocked)
            .opacity(playback.speedLocked ? 0.55 : 1)
            .glassCircle()
            .help(playback.speedLocked ? "This category always plays at 1×. Your speed comes back on the next video" : "Playback speed: 1×, 1.5× or 2×")
            VStack(spacing: 4) {
                let saved = model.isSavedForLater(video)
                Button { playback.toggleWatchLater() } label: { icon(saved ? "tray.and.arrow.down.fill" : "tray.and.arrow.down") }
                    .disabled(playback.finished && !saved)
                    .help(saved ? "In Watch Later. Click to take it off the list (⌘L)"
                                : "Watch Later: save this video and move on without marking it watched (⌘L)")
                Button { playback.toggleBookmark() } label: {
                    icon(model.isBookmarked(video) ? "bookmark.fill" : "bookmark")
                }
                .help(model.isBookmarked(video)
                      ? "Bookmarked: kept out of Automix and never deleted automatically. Click to remove (⌘B)"
                      : "Bookmark: keep this video out of Automix and never delete it automatically (⌘B)")
                Button { model.setPlayed(video, !model.isPlayed(video)) } label: {
                    icon(model.isPlayed(video) ? "checkmark.circle.fill" : "circle")
                }
                .help(model.isPlayed(video) ? "Watched — click to mark unwatched" : "Mark as watched")
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .glassCapsule()
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .frame(width: 22, height: 30)
            .contentShape(Rectangle())
    }

    static let circleSize: CGFloat = 42

    /// A button on its own: a circle, where the paired ones share a pill.
    private func circleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .frame(width: Self.circleSize, height: Self.circleSize)
            .contentShape(Circle())
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    /// Lets the video go into AVKit's own full screen and picture in picture (long videos).
    var fullScreen: PlayerFullScreen?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        // PlayerControls draws the controls, with previous and next where AVKit has rewind and fast-forward.
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = fullScreen != nil
        fullScreen?.view = view
        view.delegate = fullScreen
        view.pictureInPictureDelegate = fullScreen
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// AVKit's full screen for a PlayerView: just the video, with AVKit's Liquid Glass controls (15-second skips, a
/// scrubber, picture in picture). AVKit only puts its controls there for a view that has controls, so the view gets
/// the inline style for the trip and goes back to none (ours) on the way out.
@Observable
final class PlayerFullScreen: NSObject, AVPlayerViewDelegate, AVPlayerViewPictureInPictureDelegate {
    @ObservationIgnored weak var view: AVPlayerView?
    /// Whether the video is out in its picture-in-picture window, for the button to bring it back.
    private(set) var inPictureInPicture = false

    /// `enterFullScreen:` isn't in AVPlayerView's header, so it falls back to the window's full screen if it goes.
    func enter() {
        let selector = NSSelectorFromString("enterFullScreen:")
        guard let view, view.responds(to: selector) else {
            NSApp.keyWindow?.toggleFullScreen(nil)
            return
        }
        view.controlsStyle = .inline
        view.perform(selector, with: nil)
    }

    func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
        playerView.controlsStyle = .none
    }

    /// AVPlayerView keeps its picture-in-picture controller private and only starts it from its own button, which
    /// our controls replace, so this asks the controller directly (or presses the hidden button). Closing the
    /// floating window puts the video back in the player.
    func togglePictureInPicture() {
        guard let view else { return }
        let getter = NSSelectorFromString("pictureInPictureController")
        if view.responds(to: getter),
           let controller = view.perform(getter)?.takeUnretainedValue() as? AVPictureInPictureController {
            if controller.isPictureInPictureActive { controller.stopPictureInPicture() } else { controller.startPictureInPicture() }
            return
        }
        let selector = NSSelectorFromString("pictureInPictureButtonTapped:")
        if view.responds(to: selector) { view.perform(selector, with: nil) }
    }

    func playerViewWillStartPicture(inPicture playerView: AVPlayerView) { inPictureInPicture = true }
    func playerViewDidStopPicture(inPicture playerView: AVPlayerView) { inPictureInPicture = false }

    /// Closing the floating window with its "back" button puts the video back in the player, which is still there.
    func playerView(_ playerView: AVPlayerView,
                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        NSApp.activate()
        playerView.window?.makeKeyAndOrderFront(nil)
        completionHandler(true)
    }
}

// MARK: - Phone sync

struct SyncPopover: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            Text("Phone Sync").font(.headline)
            if !model.settings.syncEnabled {
                Text("Sync is off, so Curated isn't accepting any connections. Turn it on in Settings → Phone to copy your videos to your phone.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SettingsLink { Text("Open Settings…") }
            } else {
                Toggle(isOn: $model.settings.syncDiscoverable) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Discoverable")
                        Text(model.settings.syncDiscoverable
                             ? "Phones on this network can find “\(model.syncServiceName)”. Only paired phones can sync."
                             : "Hidden from the network. Paired phones can still sync using the address below or over USB.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                Toggle(isOn: $model.usbSyncEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USB Sync")
                        Text(usbStatus)
                            .font(.caption).foregroundStyle(model.usbSyncActive ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .disabled(AdbReverse.executable == nil)
                LabeledContent("Address") {
                    Text(addresses).textSelection(.enabled).monospacedDigit()
                }
                .font(.callout)
                Divider()
                PairingControl()
                Divider()
                SyncDeviceList()
            }
            if let error = model.syncError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var usbStatus: String { model.usbSyncStatus }
    private var addresses: String { syncAddresses }
}

extension AppModel {
    /// What USB sync is doing, for its toggle's caption.
    var usbSyncStatus: String {
        guard AdbReverse.executable != nil else { return "Needs adb from Android's platform tools, which isn't installed." }
        let forwarded = usbDevices.filter(\.forwarded).map(\.name)
        if !forwarded.isEmpty {
            return "Port \(AdbReverse.phonePort) is open on \(forwarded.formatted()) over USB. Only paired apps can sync."
        }
        guard usbSyncEnabled else { return "Off. Plugged-in phones can only sync over Wi-Fi." }
        if usbDevices.isEmpty { return "Plug in an Android phone with USB debugging on." }
        return "Couldn't open the port on \(usbDevices.map(\.name).formatted())."
    }
}

/// This Mac's sync addresses, one per line.
var syncAddresses: String {
    let list = SyncServer.localAddresses().map { "\($0):\(SyncServer.port)" }
    return list.isEmpty ? "Not connected to a network" : list.joined(separator: "\n")
}

/// "Pair a Phone…", or while pairing, the code to type on the phone and how long it lasts.
struct PairingControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let code = model.pairingCode, let expires = model.pairingExpires {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter this code on your phone").font(.callout)
                Text("\(code.prefix(3)) \(code.dropFirst(3))")
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Expires in \(formatClock(max(0, expires.timeIntervalSince(context.date))))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Spacer()
                    Button("Cancel") { model.endPairing() }.controlSize(.small)
                }
            }
        } else {
            Button("Pair a Phone…") { model.startPairing() }
        }
    }
}

struct SyncDeviceList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.syncDevices.isEmpty {
            Text("No phones paired yet.").font(.callout).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.syncDevices) { device in
                    HStack {
                        Image(systemName: "smartphone")
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                            Text(device.lastSync.map { "Synced \($0.formatted(.relative(presentation: .named)))" } ?? "Never synced")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Unpair") { model.removeSyncDevice(device.id) }
                            .controlSize(.small)
                            .help("This phone will have to pair again before it can sync")
                    }
                }
            }
        }
    }
}

// MARK: - Images

struct AvatarView: View {
    let library: CreatorLibrary
    let size: CGFloat

    var body: some View {
        Group {
            if let url = library.avatar, let image = NSImage(contentsOf: url) {
                // A playlist's is its YouTube thumbnail, cropped to the middle.
                Image(nsImage: image).resizable().scaledToFill()
            } else if library.creator.playlist {
                ZStack {
                    Circle().fill(.quaternary)
                    FormMark(name: "all", height: size * 0.5)
                }
            } else {
                ZStack {
                    // Vine authors without a picture get Vine green.
                    Circle().fill(library.creator.platform == .vine ? Vine.green.gradient : Color.accentColor.gradient)
                    // A Vine author's username is a number, so their name's first letter.
                    Text(String((library.creator.platform == .vine ? library.displayName : library.creator.username).prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(library.creator.platform.ring, lineWidth: max(1.5, size / 24))
        }
    }
}

/// A small platform mark: a music note with TikTok's cyan and magenta offsets, or YouTube's red play button.
/// Drawn from SF Symbols rather than the real logos.
struct PlatformIcon: View {
    let platform: Platform
    var size: CGFloat = 17

    var body: some View {
        Group {
            switch platform {
            case .tiktok:
                ZStack {
                    note.foregroundStyle(Platform.tikTokCyan).offset(x: -1.2, y: -1.2)
                    note.foregroundStyle(Platform.tikTokMagenta).offset(x: 1.2, y: 1.2)
                    note.foregroundStyle(.primary)
                }
            case .youtube:
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: size))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            case .vine:
                VineLogo(size: size)
            }
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch platform {
        case .tiktok: "TikTok"
        case .youtube: "YouTube Shorts"
        case .vine: "Vine"
        }
    }

    private var note: some View {
        Image(systemName: "music.note").font(.system(size: size, weight: .bold))
    }
}

extension Platform {
    /// TikTok's logo cyan; a deeper teal in light mode so text stays readable on white.
    static let tikTokCyan = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x25 / 255, green: 0xF4 / 255, blue: 0xEE / 255, alpha: 1)
            : NSColor(srgbRed: 0x00 / 255, green: 0xA8 / 255, blue: 0xA2 / 255, alpha: 1)
    })
    static let tikTokMagenta = Color(red: 0xFE / 255, green: 0x2C / 255, blue: 0x55 / 255)

    /// Creator names in queues.
    var tint: Color {
        switch self {
        case .youtube: .red
        case .vine: Vine.green
        case .tiktok: Platform.tikTokCyan
        }
    }

    /// Avatar outline: YouTube red, Vine green, or TikTok's cyan-to-magenta.
    var ring: AnyShapeStyle {
        switch self {
        case .youtube: AnyShapeStyle(Color.red)
        case .vine: AnyShapeStyle(Vine.green)
        case .tiktok: AnyShapeStyle(LinearGradient(colors: [Platform.tikTokCyan, Platform.tikTokMagenta],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

@MainActor
private let thumbnailCache = NSCache<NSURL, NSImage>()

struct ThumbnailView: View {
    let url: URL
    /// Where to take the frame from, when there's no poster image beside the video.
    var time: Double = 0.5
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            if let cached = thumbnailCache.object(forKey: url as NSURL) {
                image = cached
                return
            }
            // Long videos come with YouTube's thumbnail, saved beside them as a .jpg.
            let poster = url.deletingPathExtension().appendingPathExtension("jpg")
            if let posterImage = NSImage(contentsOf: poster) {
                thumbnailCache.setObject(posterImage, forKey: url as NSURL)
                image = posterImage
                return
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)  // portrait shorts or wide long videos
            if let (cg, _) = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)) {
                let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                thumbnailCache.setObject(ns, forKey: url as NSURL)
                image = ns
            }
        }
    }
}

// MARK: - Logo

/// The Curated logo + wordmark, switching artwork for light and dark mode. Falls back to plain text if missing.
/// The holidays with their own wordmark, used in place of the usual one while Settings → Appearance has holiday
/// wordmarks on.
enum Holiday: String, CaseIterable {
    case halloween, thanksgiving, christmas

    static let wordmarksKey = "holidayWordmarks"

    /// October is Halloween; November is Thanksgiving, up to and including Thanksgiving Day (the fourth Thursday);
    /// Christmas runs from the day after through January 5.
    static func current(on date: Date = Date(), calendar: Calendar = .current) -> Holiday? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        switch month {
        case 10: return .halloween
        case 11: return day <= thanksgivingDay(year: year, calendar: calendar) ? .thanksgiving : .christmas
        case 12: return .christmas
        case 1 where day <= 5: return .christmas
        default: return nil
        }
    }

    /// The day of November that's its fourth Thursday.
    static func thanksgivingDay(year: Int, calendar: Calendar = .current) -> Int {
        let first = calendar.date(from: DateComponents(year: year, month: 11, day: 1)).map { calendar.component(.weekday, from: $0) } ?? 5
        return 1 + (5 - first + 7) % 7 + 21  // weekday 5 is Thursday
    }

    var name: String { rawValue.capitalized }
}

struct LogoView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Holiday.wordmarksKey) private var holidayWordmarks = false
    let height: CGFloat
    /// For always-dark surfaces such as the player background.
    var forceDark = false
    /// The long-video wordmark, with landscape cards.
    var long = false

    private static func load(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    }

    private static let light = load("logo")
    private static let dark = load("logo-dark")
    private static let longLight = load("wordmark-long")
    private static let longDark = load("wordmark-long-dark")
    /// Each holiday's wordmark (and long-video wordmark), light then dark, loaded on first use.
    private static var holidayImages: [String: (NSImage?, NSImage?)] = [:]

    static func holidayImage(_ holiday: Holiday, dark: Bool, long: Bool = false) -> NSImage? {
        let name = long ? "wordmark-long-\(holiday.rawValue)" : "wordmark-\(holiday.rawValue)"
        if holidayImages[name] == nil { holidayImages[name] = (load(name), load("\(name)-dark")) }
        let (light, darkImage) = holidayImages[name]!
        return (dark ? darkImage : light) ?? light
    }

    var body: some View {
        let useDark = forceDark || colorScheme == .dark
        // Each sidebar has its own holiday wordmark: the long-video one has landscape cards.
        let holiday = holidayWordmarks ? Holiday.current() : nil
        let image = holiday.flatMap { Self.holidayImage($0, dark: useDark, long: long) }
            ?? (long ? (useDark ? Self.longDark : Self.longLight) ?? Self.longLight
                     : (useDark ? Self.dark : Self.light) ?? Self.light)
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .accessibilityLabel("Curated")
        } else {
            Text("Curated").font(.system(size: height * 0.7, weight: .bold))
        }
    }
}

/// Short videos' autoplay-next glyph: an up arrow with a dashed stem while on, slashed while off (each video loops).
/// Drawn in the current foreground style, like an SF Symbol; falls back to SF Symbols if the artwork is missing.
struct AutoplayGlyph: View {
    let on: Bool
    var size: CGFloat = 20

    private static func load(_ name: String) -> NSImage? {
        let image = Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        return image
    }

    private static let onImage = load("autoplay-on")
    private static let offImage = load("autoplay-off")

    var body: some View {
        if let image = on ? Self.onImage : Self.offImage {
            Image(nsImage: image).resizable().renderingMode(.template).frame(width: size, height: size)
        } else {
            Image(systemName: on ? "arrow.up" : "repeat.1").font(.system(size: size * 0.85))
        }
    }
}

/// The short (portrait cards) or long (landscape cards) Curated mark, the playlist mark for everything, or the Vine
/// mark (portrait cards with a Vine one in front), in its light or dark colors. Falls back to an SF Symbol if the artwork is missing (e.g. a debug build run outside the app
/// bundle).
struct FormMark: View {
    @Environment(\.colorScheme) private var colorScheme
    /// "short", "long", "all", "vine" or "suggested".
    let name: String
    let height: CGFloat

    init(form: VideoForm, height: CGFloat) {
        self.init(name: form.rawValue, height: height)
    }

    init(name: String, height: CGFloat) {
        self.name = name
        self.height = height
    }

    private static func load(_ name: String) -> NSImage? {
        Bundle.main.url(forResource: name, withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    }

    private static let images: [String: NSImage] = {
        var images: [String: NSImage] = [:]
        for kind in ["short", "long", "all", "vine", "suggested"] {
            images["mark-\(kind)"] = load("mark-\(kind)")
            images["mark-\(kind)-dark"] = load("mark-\(kind)-dark")
        }
        return images
    }()

    var body: some View {
        if let image = Self.images["mark-\(name)" + (colorScheme == .dark ? "-dark" : "")], image.size.height > 0 {
            // A fixed width too, or the footer's spacers can squeeze it to nothing.
            Image(nsImage: image)
                .resizable()
                .frame(width: height * image.size.width / image.size.height, height: height)
        } else {
            Image(systemName: ["long": "rectangle.stack", "all": "list.bullet.rectangle", "suggested": "sparkles.rectangle.stack"][name]
                  ?? "rectangle.portrait.on.rectangle.portrait")
        }
    }
}

/// What the menu bar's Commands can reach in the window: the rest of their actions live on `Playback`.
extension FocusedValues {
    @Entry var toggleTimeLimitFromMenu: EnvironmentAction? = nil
    @Entry var toggleUpNextFromMenu: EnvironmentAction? = nil
    @Entry var upNextShown: Bool? = nil
}
