import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(Router.self) private var router
    @Environment(Playback.self) private var playback
    /// On an iPhone held sideways the mixes are buttons in the bar, in place of the tiles.
    @Environment(\.sideways) private var sideways

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if app.isSyncing {
                    SyncProgressRow().padding(.horizontal, 4)
                }

                if !sideways { HStack(spacing: 10) {
                    if app.form == .short {
                        // What Automix will play: bookmarked videos stay out of it.
                        let unplayed = app.automixCount(in: nil)
                        WatchTile(symbol: "shuffle", tint: .logoRed, title: "Automix",
                                  subtitle: unplayed > 0 ? "\(unplayed) unwatched" : "All caught up",
                                  hold: { router.pick(.automix) }) {
                            startMix(.automix(nil))
                        }
                        WatchTile(symbol: "star.fill", tint: .topTint, title: "Top \(PlaybackMode.topCountAll)", subtitle: "Most viewed",
                                  hold: { router.pick(.top) }) {
                            startMix(.top(nil))
                        }
                    } else {
                        // Long videos: Latest (newest first) and Automix; no Top list.
                        let unwatched = app.latestCount(in: nil)
                        WatchTile(symbol: "clock", tint: .logoRed, title: "Latest",
                                  subtitle: unwatched > 0 ? "\(unwatched) unwatched" : "All caught up") {
                            startMix(.latest(nil))
                        }
                        WatchTile(symbol: "shuffle", tint: .topTint, title: "Automix", subtitle: "Mixed creators",
                                  hold: { router.pick(.longAutomix) }) {
                            startMix(.longAutomix(nil))
                        }
                    }
                } }

                // Watch Later and Bookmarks as small square icon buttons on the right, each while something is saved.
                let laterCount = app.watchLaterVideos(app.form).count
                let bookmarkCount = app.bookmarkedVideos(app.form).count
                if laterCount > 0 || bookmarkCount > 0 {
                    HStack(spacing: 10) {
                        Spacer()
                        if laterCount > 0 {
                            SavedButton(symbol: "tray.and.arrow.down", title: "Watch Later",
                                        mode: app.form == .short ? .watchLater : .longWatchLater, onPick: playSaved)
                                .accessibilityIdentifier("watchLaterRow")
                        }
                        if bookmarkCount > 0 {
                            SavedButton(symbol: "bookmark.fill", title: "Bookmarks",
                                        mode: app.form == .short ? .bookmarks : .longBookmarks, onPick: playSaved)
                                .accessibilityIdentifier("bookmarksRow")
                        }
                    }
                }

                Text("CREATORS")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)

                // The Mac lists its long-video creators even before any of their videos are downloaded here.
                if app.form == .long && app.longLibraries.allSatisfy(\.videos.isEmpty) { NoLongVideos() }
                // The long Home only shows categories that have a long-video creator.
                let shown = app.categories.filter { app.form == .short || !app.longLibraries(in: $0.id).isEmpty }
                ForEach(shown) { category in
                    CreatorCard(title: category.name, libraries: app.libraries(in: category.id, form: app.form),
                                cardKey: category.id, category: category.id, open: open, form: app.form)
                }
                let others = app.form == .short ? app.uncategorizedLibraries : app.uncategorizedLongLibraries
                if !others.isEmpty {
                    CreatorCard(title: shown.isEmpty ? "All Creators" : "Other Creators", libraries: others,
                                cardKey: "other", category: nil, open: open, form: app.form)
                }
                // The author of every Vine on the device, each like a creator.
                if app.form == .short && !app.vineLibraries.isEmpty {
                    CreatorCard(title: "Vine", libraries: app.vineLibraries, cardKey: "vine", category: nil, open: open,
                                vine: true)
                }
                // Always the last card.
                if app.form == .long && !app.playlistLibraries.isEmpty {
                    PlaylistsCard(playlists: app.playlistLibraries, open: open)
                }

                LibraryFooter()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        // Slowly drifting color for the glass cards to show; fainter than the pairing screen's so lists stay easy to read.
        .background { AuroraBackground(intensity: 0.65, frameInterval: 1.0 / 20).ignoresSafeArea() }
        // Kept for the back button and VoiceOver; the logo above replaces the visible title.
        .navigationTitle("Curated")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            // The logo and wordmark stand in for the title, level with the bar's buttons; light and dark artwork come
            // from the asset catalog. The long Home has its own wordmark (landscape cards).
            ToolbarItem(placement: .topBarLeading) {
                // A bar item gets no width to grow into, so it's given the artwork's own.
                let height: CGFloat = sideways ? 28 : 34
                let size = UIImage(named: app.logoName)?.size ?? CGSize(width: 4, height: 1)
                Image(app.logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: height * size.width / max(1, size.height), height: height)
                    .accessibilityLabel(app.form == .long ? "Curated, long videos" : "Curated")
                    .accessibilityAddTraits(.isHeader)
            }
            .hidingSharedBackground()
            if sideways {
                ToolbarItemGroup(placement: .topBarTrailing) { barMixButtons }
            }
            if app.pairing != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.addingCreator = true
                    } label: {
                        Label("Add Creator", systemImage: "plus")
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("homeAddCreator")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { FormSwitchButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.settingsShown = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .tint(.primary)
            }
        }
        .refreshable {
            if app.pairing != nil { await app.sync() }
        }
        .safeAreaInset(edge: .bottom) { NowPlayingBar() }
    }

    /// The main mixes as icons, each lit while it's the one playing; long-press Automix or Top 15 to pick its cards.
    @ViewBuilder private var barMixButtons: some View {
        if app.form == .short {
            BarMixButton(symbol: "shuffle", tint: .logoRed, title: "Automix", on: isPlaying { if case .automix(nil, _) = $0 { true } else { false } },
                         hold: { router.pick(.automix) }) { startMix(.automix(nil)) }
            BarMixButton(symbol: "star.fill", tint: .topTint, title: "Top \(PlaybackMode.topCountAll)",
                         on: isPlaying { if case .top(nil, _) = $0 { true } else { false } },
                         hold: { router.pick(.top) }) { startMix(.top(nil)) }
        } else {
            BarMixButton(symbol: "clock", tint: .logoRed, title: "Latest", on: isPlaying { $0 == .latest(nil) }) { startMix(.latest(nil)) }
            BarMixButton(symbol: "shuffle", tint: .topTint, title: "Automix", on: isPlaying { if case .longAutomix(nil, _) = $0 { true } else { false } },
                         hold: { router.pick(.longAutomix) }) { startMix(.longAutomix(nil)) }
        }
    }

    private func isPlaying(_ match: (PlaybackMode) -> Bool) -> Bool {
        playback.current != nil && playback.mode.map(match) == true
    }

    /// A video picked from Watch Later or Bookmarks: plays that list from there.
    private func playSaved(_ mode: PlaybackMode, _ videos: [Video], _ index: Int) {
        playback.start(videos, at: index, mode: mode)
        router.open(.player(mode))
    }

    /// Opens a mix with a new queue, even when it's the one already playing (the Now Playing bar carries on instead).
    private func startMix(_ mode: PlaybackMode) {
        playback.start(Queues.build(mode, app), mode: mode)
        router.open(.player(mode))
    }

    /// A creator's videos open as a list (a long-video creator's or playlist's as a gallery); mixes open in the player.
    private func open(_ mode: PlaybackMode) {
        switch mode {
        case .creator(let username): router.open(.creator(username))
        case .longCreator(let username): router.open(.gallery(username))
        default: router.open(.player(mode))
        }
    }
}

extension View {
    /// The rounded, faintly lit panel behind the tiles and creator cards.
    /// Liquid Glass on iOS 26 (a frosted material before), over the drifting color behind Home.
    @ViewBuilder func cardBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
                .contentShape(shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
                .contentShape(shape)
        }
    }
}

extension Color {
    /// The red and cyan of the Curated logo (its dark-mode artwork).
    static let logoRed = Color(red: 0xE3 / 255, green: 0x31 / 255, blue: 0x51 / 255)
    static let logoCyan = Color(red: 0x6C / 255, green: 0xE7 / 255, blue: 0xE2 / 255)
    /// The Top 15 star: the logo's cyan in dark mode, its red in light mode, where the cyan is too faint.
    static let topTint = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(logoCyan) : UIColor(logoRed)
    })
}

/// A square button for one of the main mixes, styled like the creator cards. Holding it runs `hold`. In the wide
/// layout's sidebar, the open mix's tile (`selected`) is filled with its icon's color, the icon and text turning to
/// the background color (black in dark mode, white in light) on it.
struct WatchTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var selected = false
    var hold: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        let onFill = Color(.systemBackground)
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(selected ? onFill : tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(selected ? onFill : .primary)
                Text(subtitle).font(.footnote).lineLimit(1)
                    .foregroundStyle(selected ? AnyShapeStyle(onFill.opacity(0.75)) : AnyShapeStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(TileBackground(fill: selected ? tint : nil))
        .tapAndHold(action: action, hold: hold, holdLabel: "Choose Categories")
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A tile's glass card, or a solid fill of `fill` (its selected look).
private struct TileBackground: ViewModifier {
    let fill: Color?

    func body(content: Content) -> some View {
        if let fill {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            content.background(fill, in: shape).contentShape(shape)
        } else {
            content.cardBackground()
        }
    }
}

/// Watch Later or Bookmarks: a glass square with just its icon (its name and count are for VoiceOver). Tapping it pops
/// a list of its videos out of the button, sized to the list; picking one plays the list from there (`onPick`).
struct SavedButton: View {
    @Environment(AppState.self) private var app
    let symbol: String
    let title: String
    let mode: PlaybackMode
    let onPick: (PlaybackMode, [Video], Int) -> Void
    @State private var showList = false

    var body: some View {
        let videos = mode.isBookmarks ? app.bookmarkedVideos(mode.form) : app.watchLaterVideos(mode.form)
        Button { showList = true } label: {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .modifier(SquareGlass())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(videos.count)")
        .popover(isPresented: $showList, arrowEdge: .top) {
            SavedList(title: title, videos: videos) { index in
                showList = false
                onPick(mode, videos, index)
            }
            // A popover on iPhone too, not a sheet.
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The 52pt squares' glass, with smaller corners than the cards'.
private struct SquareGlass: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: shape).contentShape(shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
                .contentShape(shape)
        }
    }
}

/// The videos in Watch Later or Bookmarks, in a popover only as tall as its rows (up to 460pt, then it scrolls).
private struct SavedList: View {
    @Environment(Playback.self) private var playback
    let title: String
    let videos: [Video]
    let pick: (Int) -> Void
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(title) · \(videos.count)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    Button { pick(index) } label: {
                        Group {
                            if video.isLong {
                                LongVideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: true)
                            } else {
                                VideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: true)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("savedListRow-\(index)")
                }
            }
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 340, height: min(max(height, 60), 460))
    }
}

/// Which mix a long press is picking cards for.
enum MixPick: String, Identifiable {
    case automix, top, longAutomix
    var id: String { rawValue }
}

/// A popup in the middle of the screen with the cards on Home as round glass toggles, each with its glyph (its name
/// below), and on the right a red round button that starts the mix (`onStart`) from the ones that are on. The cards with something unplayed
/// start on. Tapping outside it or swiping it away closes it (`dismiss`).
struct MixPicker: View {
    @Environment(AppState.self) private var app
    let pick: MixPick
    let dismiss: () -> Void
    let onStart: (PlaybackMode) -> Void
    @State private var picked: Set<String>?
    @State private var drag: CGSize = .zero
    @Environment(\.horizontalSizeClass) private var sizeClass

    private struct Option: Identifiable {
        let id: String
        let name: String
        let symbol: String?  // nil: the Vine V
        let count: Int
    }

    private var form: VideoForm { pick == .longAutomix ? .long : .short }
    private var title: String { pick == .top ? "Top \(PlaybackMode.topCountAll)" : "Automix" }
    /// The toggles' widest on iPhone Duo's inner display and iPad, so they stay tight. A compact width (a phone, and
    /// iPhone Duo's wide, short outer display) has no limit: the popup spans the screen.
    private var maxWidth: CGFloat { sizeClass == .compact ? .infinity : 300 }

    /// What a card adds to the mix. As on the Automix tile, bookmarked videos stay out of Automix.
    private func count(_ key: String) -> Int {
        switch pick {
        case .automix: app.automixLibraries(picked: [key]).reduce(0) { $0 + $1.videos.count { !app.isPlayed($0) && !app.isBookmarked($0) } }
        case .longAutomix: app.mixLibraries(picked: [key], form: .long).reduce(0) { $0 + $1.videos.count { !app.isPlayed($0) && !app.isBookmarked($0) } }
        case .top: app.mixLibraries(picked: [key], form: .short).reduce(0) { $0 + app.unplayedCount($1) }
        }
    }

    /// Home's cards in its order, the ones with nothing to play last. Top lists leave Vines out.
    private var options: [Option] {
        let shown = app.categories.filter { form == .short || !app.longLibraries(in: $0.id).isEmpty }
        var options = shown.map { Option(id: $0.id, name: $0.name, symbol: $0.symbol ?? "folder", count: count($0.id)) }
        let others = form == .short ? app.uncategorizedLibraries : app.uncategorizedLongLibraries
        if !others.isEmpty {
            options.append(Option(id: otherCard, name: shown.isEmpty ? "All Creators" : "Other Creators", symbol: "person.2", count: count(otherCard)))
        }
        if pick == .automix && !app.vineLibraries.isEmpty {
            options.append(Option(id: vineCard, name: "Vine", symbol: nil, count: count(vineCard)))
        }
        return options.filter { $0.count > 0 } + options.filter { $0.count == 0 }
    }

    var body: some View {
        let options = options
        // Automix starts from the categories it plays by default (Settings > Playback).
        let off = pick == .top ? [] : app.playbackRules.cards(form).automixOff
        let on = picked ?? Set(options.filter { $0.count > 0 && !off.contains($0.id) }.map(\.id))
        let total = options.filter { on.contains($0.id) }.reduce(0) { $0 + $1.count }
        HStack(spacing: 20) {
            // Scrolls only if there are too many categories for the screen.
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 18) {
                    ForEach(options) { option in
                        toggle(option, isOn: on.contains(option.id)) {
                            picked = on.symmetricDifference([option.id])
                        }
                    }
                }
                .padding(.top, 8)  // Room for the badges.
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: maxWidth)
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
                switch pick {
                case .automix: onStart(.automix(nil, picked: on))
                case .top: onStart(.top(nil, picked: on))
                case .longAutomix: onStart(.longAutomix(nil, picked: on))
                }
            } label: {
                Image(systemName: pick == .top ? "star.fill" : "shuffle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.logoRed, in: Circle())
                    .opacity(total == 0 ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(total == 0)
            .accessibilityLabel(title)
        }
        .padding(20)
        .popupBackground()
        .padding(.horizontal, 16)
        .offset(drag)
        .gesture(
            // A flick or a long drag in any direction closes it; a short one springs back.
            DragGesture()
                .onChanged { drag = $0.translation }
                .onEnded { value in
                    let moved = hypot(value.translation.width, value.translation.height)
                    let flung = hypot(value.predictedEndTranslation.width, value.predictedEndTranslation.height)
                    if moved > 90 || flung > 260 {
                        dismiss()
                    } else {
                        withAnimation(.snappy) { drag = .zero }
                    }
                }
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismiss)
    }

    /// A glass circle with the card's glyph and its name below. On, the glyph turns blue and the unplayed count shows as a
    /// badge; off, the glyph is the plain text color and the badge goes.
    private func toggle(_ option: Option, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let symbol = option.symbol {
                        Image(systemName: symbol).font(.system(size: 24, weight: .semibold))
                    } else {
                        Image("VineGlyph").resizable().renderingMode(.template).scaledToFit().frame(height: 24)
                    }
                }
                .foregroundStyle(isOn ? Color.blue : Color.primary)
                .frame(width: 64, height: 64)
                .pickerCircleBackground()
                .overlay(alignment: .topTrailing) {
                    if isOn {
                        UnplayedBadge(count: option.count)
                            .offset(x: 6, y: -4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(option.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityValue(option.count > 0 ? "\(option.count) unwatched" : "Nothing unwatched")
    }
}

extension View {
    /// The mix picker's panel: glass, or a material before iOS 26.
    @ViewBuilder func popupBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
                .shadow(color: .black.opacity(0.2), radius: 30, y: 10)
        }
    }

    /// The mix picker's round toggles: glass, or a material before iOS 26.
    @ViewBuilder func pickerCircleBackground() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.thinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.08)) }
        }
    }

    /// A tap runs `action`; holding (when `hold` is set) runs `hold` instead, with a haptic tap. VoiceOver gets the
    /// hold as a named action.
    func tapAndHold(action: @escaping () -> Void, hold: (() -> Void)?, holdLabel: String) -> some View {
        modifier(TapAndHold(action: action, hold: hold, holdLabel: holdLabel))
    }
}

private struct TapAndHold: ViewModifier {
    let action: () -> Void
    let hold: (() -> Void)?
    let holdLabel: String
    @State private var pressing = false
    @State private var held = 0

    func body(content: Content) -> some View {
        content
            .opacity(pressing ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: pressing)
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.4) {
                guard let hold else { return }
                held += 1
                hold()
            } onPressingChanged: { pressing = $0 }
            .sensoryFeedback(.impact(weight: .medium), trigger: held)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
            .accessibilityActions {
                if let hold { Button(holdLabel, action: hold) }
            }
    }
}

/// A category's creators as a collapsible card, like the Mac sidebar: a header with the unplayed count, a toggle for
/// the caught-up creators and the category's Automix and Top buttons, then a grid of avatars with count badges.
/// Only creators with something new show unless the toggle is on. A card with nothing to play starts collapsed.
struct CreatorCard: View {
    @Environment(AppState.self) private var app
    let title: String
    let libraries: [CreatorLibrary]
    let cardKey: String
    let category: String?
    /// Opens a creator or one of the category's mixes: pushed on iPhone, selected in the iPad sidebar.
    let open: (PlaybackMode) -> Void
    /// What the iPad sidebar has selected, highlighted here.
    var selection: PlaybackMode?
    var avatarSize: CGFloat = 58
    /// Short or long videos: decides the category's mixes and what a creator opens.
    var form = VideoForm.short
    /// The Vine card: the Vine V before its title, and a Vine Automix button.
    var vine = false

    /// Before the title, as in the mix picker: the category's glyph from the Mac, or two people for "Other Creators".
    private var glyph: String? {
        if let category { return app.category(category)?.symbol ?? "folder" }
        return cardKey == otherCard ? "person.2" : nil
    }

    /// Opened by hand while it has nothing to play; not saved, unlike collapsedCards.
    @State private var openedWhileEmpty = false
    @State private var showCaughtUp = false

    var body: some View {
        let unplayed = libraries.reduce(0) { $0 + app.unplayedCount($1) }
        let expanded = unplayed > 0 ? !app.collapsedCards.contains(cardKey) : openedWhileEmpty
        let caughtUp = libraries.filter { app.unplayedCount($0) == 0 }.count
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy) {
                        if unplayed > 0 { app.setCollapsed(cardKey, expanded) } else { openedWhileEmpty.toggle() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                        if vine {
                            Image("VineGlyph").resizable().scaledToFit().frame(height: 15).foregroundStyle(.secondary)
                        } else if let glyph {
                            Image(systemName: glyph).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        // The whole name first: the count goes when there isn't room for both (a narrow sidebar).
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                Text(title).font(.headline).fixedSize()
                                CountBadge(count: unplayed)
                            }
                            Text(title).font(.headline).fixedSize()
                            Text(title).font(.headline).lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(unplayed > 0 ? "\(unplayed) unwatched" : "All caught up")
                .accessibilityHint(expanded ? "Collapses" : "Expands")

                // The caught-up toggle and the mixes, close together.
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.snappy) {
                            showCaughtUp.toggle()
                            if showCaughtUp && !expanded {
                                if unplayed > 0 { app.setCollapsed(cardKey, false) } else { openedWhileEmpty = true }
                            }
                        }
                    } label: {
                        // After the Mac's toggle for the caught-up creators.
                        Image(systemName: "memories.badge.plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(caughtUp == 0 ? AnyShapeStyle(.tertiary) : showCaughtUp ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                            .frame(width: 32, height: 32)
                            .background(showCaughtUp ? Color.logoRed : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .frame(width: 34, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(caughtUp == 0)
                    .accessibilityLabel(showCaughtUp ? "Hide \(caughtUp) caught-up creators" : "Show \(caughtUp) caught-up creators")

                    if vine {
                        mixButton("shuffle", .vineAutomix, label: "Vine Automix")
                    }
                    if let category {
                        if form == .short {
                            mixButton("shuffle", .automix(category), label: "\(title) Automix")
                            mixButton("star", .top(category), label: "\(title) Top \(PlaybackMode.topCountCategory)")
                        } else {
                            mixButton("clock", .latest(category), label: "\(title) Latest")
                            mixButton("shuffle", .longAutomix(category), label: "\(title) Automix")
                        }
                    }
                }
                .fixedSize()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .frame(minHeight: 50)

            if expanded {
                // Most unplayed first, then (when shown) the caught-up ones alphabetically. An empty card has only
                // caught-up creators, so opening it shows them.
                let fresh = libraries.filter { app.unplayedCount($0) > 0 }.sorted {
                    let (a, b) = (app.unplayedCount($0), app.unplayedCount($1))
                    return a != b ? a > b : $0.creator.displayName.localizedCaseInsensitiveCompare($1.creator.displayName) == .orderedAscending
                }
                // The selected creator stays in view even when caught up, so the selection never vanishes.
                let rest = showCaughtUp || unplayed == 0
                    ? libraries.filter { app.unplayedCount($0) == 0 }.sorted {
                        $0.creator.displayName.localizedCaseInsensitiveCompare($1.creator.displayName) == .orderedAscending
                    }
                    : libraries.filter { app.unplayedCount($0) == 0 && selection == creatorMode($0.id) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: avatarSize + 18), spacing: 4)], spacing: 12) {
                    ForEach(fresh + rest) { library in
                        CreatorCell(library: library, size: avatarSize, selected: selection == creatorMode(library.id)) {
                            open(creatorMode(library.id))
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            }
        }
        .foregroundStyle(.primary)
        .cardBackground()
    }

    private func creatorMode(_ username: String) -> PlaybackMode {
        form == .short ? .creator(username) : .longCreator(username)
    }

    /// One of the category's mixes; its glyph turns blue while it's selected.
    private func mixButton(_ symbol: String, _ mode: PlaybackMode, label: String) -> some View {
        let selected = selection == mode
        return Button { open(mode) } label: {
            Image(systemName: symbol)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 34, height: 44)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct CreatorCell: View {
    @Environment(AppState.self) private var app
    let library: CreatorLibrary
    let size: CGFloat
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let unplayed = app.unplayedCount(library)
        Button(action: action) {
            AvatarView(username: library.id, size: size, dimmed: unplayed == 0 && !selected)
                .padding(3)
                .overlay { Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5) }
                .overlay(alignment: .topTrailing) { UnplayedBadge(count: unplayed).offset(x: 6, y: -4) }
                .padding(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { CreatorMenuButtons(library: library) }
        .accessibilityLabel(library.creator.displayName)
        .accessibilityValue(unplayed > 0 ? "\(unplayed) unwatched" : "Caught up")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("creator-\(library.id)")
    }
}

struct SyncProgressRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let progress = app.syncProgress {
                ProgressView(value: progress)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(app.syncStep).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct CreatorRow: View {
    @Environment(AppState.self) private var app
    let library: CreatorLibrary

    var body: some View {
        NavigationLink(value: Route.creator(library.id)) {
            HStack(spacing: 12) {
                AvatarView(username: library.id, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(library.creator.displayName).lineLimit(1)
                    Text("\(app.unplayedCount(library)) unwatched · \(library.videos.count) total")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu { CreatorMenuButtons(library: library) }
    }
}

/// Long-pressing a creator or playlist: its page on YouTube or TikTok, then marking all its videos.
struct CreatorMenuButtons: View {
    @Environment(\.openURL) private var openURL
    @Environment(Router.self) private var router
    let library: CreatorLibrary

    var body: some View {
        if library.form == .long && library.creator.isYouTube && !library.creator.isPlaylist {
            Button("Older Videos…", systemImage: "clock.arrow.circlepath") {
                router.olderVideos = OlderVideosTarget(id: library.id, name: library.creator.displayName)
            }
        }
        if let url = library.creator.pageURL {
            Button("Open in \(library.creator.siteName)", systemImage: "arrow.up.forward.app") { openURL(url) }
            Divider()
        }
        MarkAllButtons(library: library)
    }
}

struct MarkAllButtons: View {
    @Environment(AppState.self) private var app
    let library: CreatorLibrary

    var body: some View {
        let unplayed = app.unplayedCount(library)
        Button("Mark All as Watched", systemImage: "checkmark.circle") { app.setPlayed(library.videos, true) }
            .disabled(unplayed == 0)
        Button("Mark All as Unwatched", systemImage: "circle") { app.setPlayed(library.videos, false) }
            .disabled(unplayed == library.videos.count)
    }
}

struct LibraryFooter: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let videos = app.allVideos
        VStack(spacing: 2) {
            Text("\(videos.count) video\(videos.count == 1 ? "" : "s") on this \(UIDevice.current.localizedModel) · \(formatLength(videos.reduce(0) { $0 + ($1.duration ?? 0) }))")
            if let last = app.lastSyncAt {
                Text("Last synced \(last.formatted(.relative(presentation: .named)))")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct CreatorView: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    let username: String

    var body: some View {
        let library = app.library(username)
        Group {
            if let library, !library.videos.isEmpty {
                List {
                    ForEach(Array(library.videos.enumerated()), id: \.element.id) { index, video in
                        Button {
                            playback.start(library.videos, at: index, mode: .creator(username))
                            router.open(.player(.creator(username)))
                        } label: {
                            VideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: false)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            let played = app.isPlayed(video)
                            Button(played ? "Unwatched" : "Watched", systemImage: played ? "circle" : "checkmark.circle") {
                                app.setPlayed(video, !played)
                            }
                            .tint(.accentColor)
                        }
                    }
                }
                .listStyle(.plain)
            } else {
                ContentUnavailableView("No Videos Yet", systemImage: "film.stack",
                                       description: Text("Videos for \(library?.creator.displayName ?? "@\(creatorHandle(username))") appear here after the next sync."))
            }
        }
        .navigationTitle(library?.creator.displayName ?? "@\(creatorHandle(username))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let library, !library.videos.isEmpty {
                Menu("Mark All", systemImage: "ellipsis.circle") { MarkAllButtons(library: library) }
            }
        }
        .safeAreaInset(edge: .bottom) { NowPlayingBar() }
    }
}

/// A Music-style mini player shown while a video is loaded. Tap to go back to it, ✕ to stop.
struct NowPlayingBar: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    /// Sideways, the player is beside the screens, with the tray under them.
    @Environment(\.sideways) private var sideways

    var body: some View {
        if !sideways, let video = playback.current, let mode = playback.mode, !playback.finished {
            HStack(spacing: 12) {
                ZStack {
                    ThumbnailView(url: app.store.videoFile(video))
                    VideoSurface(playback: playback, gravity: .resizeAspectFill, pip: false)
                }
                // Wide for a long video, tall for a short one.
                .frame(width: video.isLong ? 64 : 36, height: video.isLong ? 36 : 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Now Playing · \(app.library(video.creator, form: video.isLong ? .long : .short)?.creator.displayName ?? "@\(creatorHandle(video.creator))")")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(video.isLong ? video.displayTitle : video.caption.isEmpty ? "No caption" : video.caption)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                Button {
                    playback.stop()
                } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
                }
                .accessibilityLabel("Stop")
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassBackground(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true)
            .contentShape(Rectangle())
            .onTapGesture { router.open(.player(mode)) }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("nowPlayingBar")
        }
    }
}

/// One of the main mixes as a bar button: its tile's symbol and color, on a tinted circle while it's the mix that's
/// playing (tapping that one leaves it playing). Long-press opens the mix's card picker, where it has one.
private struct BarMixButton: View {
    let symbol: String
    let tint: Color
    let title: String
    let on: Bool
    var hold: (() -> Void)?
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background { if on { Circle().fill(Color.accentColor.opacity(0.3)) } }
            .contentShape(Circle())
            .onTapGesture { if !on { action() } }
            .onLongPressGesture { hold?() }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { if !on { action() } }
    }
}

extension ToolbarContent {
    /// No glass behind an item that isn't a button (the wordmark), on iOS 26 and later.
    @ToolbarContentBuilder func hidingSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Switches Home between short and long videos. Shows the other one's mark: the long-video logo on the short Home,
/// and the other way round.
struct FormSwitchButton: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let other: VideoForm = app.form == .short ? .long : .short
        Button {
            withAnimation(.snappy) { app.form = other }
        } label: {
            CuratedMark(kind: other == .long ? .long : .short, height: 22)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(other == .long ? "Long videos" : "Short videos")
        .accessibilityIdentifier("formSwitch")
    }
}

/// The long Home with nothing synced yet: how to get long videos onto this device.
struct NoLongVideos: View {
    @Environment(AppState.self) private var app
    @Environment(Router.self) private var router

    var body: some View {
        VStack(spacing: 10) {
            CuratedMark(kind: .long, height: 36)
            Text("No long videos here yet").font(.headline)
            Text(app.longLibraries.isEmpty
                 ? "Turn on long videos for a YouTube creator (or add a playlist) on your Mac, then sync."
                 : "In Settings, set Sync to Long Videos or All Videos, then tap Sync.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !app.longLibraries.isEmpty {
                Button("Open Settings") { router.settingsShown = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }
}
