import AVFoundation
import AVKit
import SwiftUI

// The long-video screens and their pieces: the Curated marks, 16:9 thumbnails, list rows, the creator gallery, the
// Playlists card and the Up Next card, as on the Mac.

/// The short (portrait cards), long (landscape cards) or playlist Curated mark, in light or dark artwork.
struct CuratedMark: View {
    enum Kind: String { case short = "MarkShort", long = "MarkLong", all = "MarkAll" }
    let kind: Kind
    let height: CGFloat

    var body: some View {
        Image(kind.rawValue)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

private let posterCache = NSCache<NSString, UIImage>()

/// A long video's 16:9 thumbnail with rounded corners: the Mac's poster (YouTube's thumbnail) or, without one, a frame
/// a little way in. Its length sits in the bottom-right corner, a red bar shows how far it's been watched, and a watched
/// one is dimmed.
struct LongThumbnail: View {
    @Environment(AppState.self) private var app
    let video: Video
    var isCurrent = false
    var cornerRadius: CGFloat = 10
    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let progress = app.progress(video)
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image { Image(uiImage: image).resizable().scaledToFill() }
                }
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    // A dark track, so the red reads on any thumbnail.
                    GeometryReader { geo in
                        ZStack(alignment: .bottomLeading) {
                            Rectangle().fill(.black.opacity(0.7))
                            Rectangle().fill(.red).frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .clipShape(shape)
            .overlay(alignment: .bottomTrailing) {
                if let length = video.duration, length > 0 {
                    Text(formatClock(length))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.trailing, 6)
                        .padding(.bottom, progress == nil ? 6 : 10)
                }
            }
            .opacity(app.isPlayed(video) && !isCurrent ? 0.5 : 1)
            .overlay {
                if isCurrent {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2.5)
                    Image(systemName: "play.fill").font(.title2).foregroundStyle(.white).shadow(radius: 3)
                }
            }
            .task(id: video.id) { await load() }
    }

    private func load() async {
        if let cached = posterCache.object(forKey: video.id as NSString) {
            image = cached
            return
        }
        let poster = app.store.posterFile(video)
        var loaded = UIImage(contentsOfFile: poster.path)
        if loaded == nil {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: app.store.videoFile(video)))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            let at = min(60, (video.duration ?? 0) * 0.1) + 0.5
            if let (cg, _) = try? await generator.image(at: CMTime(seconds: at, preferredTimescale: 600)) {
                loaded = UIImage(cgImage: cg)
            }
        }
        if let loaded {
            posterCache.setObject(loaded, forKey: video.id as NSString)
            image = loaded
        }
    }
}

/// "Watched · 3 days ago · 1.2M views", with Watch Later and bookmark marks.
struct LongVideoMeta: View {
    @Environment(AppState.self) private var app
    let video: Video

    var body: some View {
        HStack(spacing: 5) {
            if app.isPlayed(video) {
                Label("Watched", systemImage: "checkmark.circle.fill")
                Text("·")
            } else if app.isSavedForLater(video) {
                Label("Later", systemImage: "arrowshape.bounce.forward.fill")
                Text("·")
            }
            if app.isBookmarked(video) {
                Image(systemName: "bookmark.fill").accessibilityLabel("Bookmarked")
                Text("·")
            }
            Text(video.date, format: .relative(presentation: .named))
            if let views = video.viewCount {
                Text("·")
                Text("\(views.formatted(.number.notation(.compactName))) views")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// A long video in a list (Up Next): the wide thumbnail, then its title, creator, description and details.
struct LongVideoRow: View {
    @Environment(AppState.self) private var app
    let video: Video
    let isCurrent: Bool
    let showCreator: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LongThumbnail(video: video, isCurrent: isCurrent, cornerRadius: 8)
                .frame(width: 150)
            VStack(alignment: .leading, spacing: 3) {
                Text(video.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                if showCreator, let library = app.library(video.creator, form: .long) {
                    Text(library.creator.displayName).font(.caption.weight(.semibold)).foregroundStyle(Color.youTubeRed)
                        .lineLimit(1)
                }
                if let details = video.details, !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                LongVideoMeta(video: video)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// One video in a creator's gallery: the thumbnail, then title, description and details underneath.
struct GalleryCard: View {
    @Environment(AppState.self) private var app
    let video: Video
    let isCurrent: Bool
    /// Latest mixes creators, so each card names its own.
    var showCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LongThumbnail(video: video, isCurrent: isCurrent, cornerRadius: 12)
            Text(video.displayTitle).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
            if showCreator, let library = app.library(video.creator, form: .long) {
                Text(library.creator.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.youTubeRed)
                    .lineLimit(1)
            }
            if let details = video.details, !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(.secondary).lineLimit(3).multilineTextAlignment(.leading)
            }
            LongVideoMeta(video: video)
        }
        .contentShape(Rectangle())
    }
}

/// The gallery itself: the creator (or playlist) on top, then a card per video, more across on wider screens.
struct LongGallery: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    let library: CreatorLibrary
    let play: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    if library.creator.isPlaylist {
                        PlaylistThumbnail(library: library, size: 56)
                    } else {
                        AvatarView(username: library.id, size: 56)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.creator.displayName).font(.title2.weight(.bold)).lineLimit(2)
                        let count = library.videos.count
                        Text("\(count) video\(count == 1 ? "" : "s") · \(app.unplayedCount(library)) unwatched · "
                             + formatLength(library.videos.reduce(0) { $0 + ($1.duration ?? 0) }))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if library.videos.isEmpty {
                    ContentUnavailableView("No Videos Yet", systemImage: "rectangle.stack",
                                           description: Text("They appear here after the next sync."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], spacing: 22) {
                        ForEach(Array(app.longVideos(library).enumerated()), id: \.element.id) { index, video in
                            Button { play(index) } label: {
                                GalleryCard(video: video,
                                            isCurrent: playback.mode == .longCreator(library.id) && playback.current?.id == video.id)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { VideoMenu(video: video) }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Long videos' Latest as a gallery, like a creator's: the unwatched Suggestions first, then everything else newest
/// first (AppState.latestVideos). Picking a video plays the list from there.
struct LatestGallery: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    let category: String?
    let play: ([Video], Int) -> Void

    var body: some View {
        let videos = app.latestVideos(in: category)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "clock")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.logoRed.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(category, app)).font(.title2.weight(.bold)).lineLimit(2)
                        Text("\(videos.count) unwatched · " + formatLength(videos.reduce(0) { $0 + ($1.duration ?? 0) }))
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if videos.isEmpty {
                    ContentUnavailableView("All Caught Up", systemImage: "checkmark.circle",
                                           description: Text("New long videos appear here after the next sync."))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], spacing: 22) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            Button { play(videos, index) } label: {
                                GalleryCard(video: video,
                                            isCurrent: playback.mode == .latest(category) && playback.current?.id == video.id,
                                            showCreator: true)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { VideoMenu(video: video) }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    static func title(_ category: String?, _ app: AppState) -> String {
        [app.category(category)?.name, "Latest"].compactMap { $0 }.joined(separator: " ")
    }
}

/// Latest on iPhone (and in the sideways layout's right pane): its gallery. Picking a video opens the player.
struct LatestView: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    @Environment(\.sideways) private var sideways
    let category: String?

    var body: some View {
        LatestGallery(category: category) { videos, index in
            playback.start(videos, at: index, mode: .latest(category))
            router.open(.player(.latest(category)))
        }
        .navigationTitle(LatestGallery.title(category, app))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Long Home lands here when upright, so the form switch is on hand without going Back.
            if !sideways, category == nil { ToolbarItem(placement: .topBarTrailing) { FormSwitchButton() } }
        }
        .safeAreaInset(edge: .bottom) { if !sideways { NowPlayingBar() } }
        .modifier(SidebarHeader {
            if !sideways {
                CreatorStrip(category: category) { router.open(.gallery($0)) } all: { router.path.removeAll() }
            }
        })
    }
}

/// Latest's row of creators upright on a phone: every long creator and playlist, scrolling sideways, the ones with the
/// newest unwatched video first. Picking one opens its gallery; All, pinned at the end with the row scrolling under it,
/// goes to the long Home.
struct CreatorStrip: View {
    @Environment(AppState.self) private var app
    let category: String?
    let open: (String) -> Void
    let all: () -> Void
    private let size: CGFloat = 52

    var body: some View {
        let libraries = ordered
        ZStack(alignment: .trailing) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(libraries, id: \.id) { library in
                        let unwatched = app.unplayedCount(library)
                        Button { open(library.id) } label: {
                            VStack(spacing: 4) {
                                Group {
                                    if library.creator.isPlaylist {
                                        PlaylistThumbnail(library: library, size: size)
                                            .opacity(unwatched == 0 ? 0.45 : 1)
                                    } else {
                                        AvatarView(username: library.id, size: size, dimmed: unwatched == 0)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if unwatched > 0 {
                                        Circle().fill(Color.youTubeRed).frame(width: 11, height: 11)
                                            .overlay { Circle().strokeBorder(.background, lineWidth: 2) }
                                    }
                                }
                                Text(library.creator.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(unwatched == 0 ? .secondary : .primary)
                                    .lineLimit(1)
                                    .frame(width: size + 12)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(library.creator.displayName), \(unwatched) unwatched")
                    }
                }
                .padding(.leading, 16)
                // Room to scroll the last creator out from under All.
                .padding(.trailing, 76)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            Button(action: all) {
                Text("All")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 24)
            .padding(.trailing, 12)
            .frame(maxHeight: .infinity)
            // The row fades out as it slides under All.
            .background {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: Color(uiColor: .systemBackground), location: 0.35)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Newest unwatched video first; caught-up ones after, by their newest video.
    private var ordered: [CreatorLibrary] {
        app.longLibraries(in: category)
            .filter { !$0.videos.isEmpty }
            .map { library in
                let unwatched = library.videos.filter { !app.isPlayed($0) }.map(\.date).max()
                return (library, unwatched, library.videos.map(\.date).max() ?? .distantPast)
            }
            .sorted { a, b in
                switch (a.1, b.1) {
                case let (x?, y?): x > y
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): a.2 > b.2
                }
            }
            .map(\.0)
    }
}

/// Played, Watch Later and Bookmark, for a video's long-press menu.
struct VideoMenu: View {
    @Environment(AppState.self) private var app
    let video: Video

    var body: some View {
        if app.isPlayed(video) {
            Button("Mark as Unwatched", systemImage: "circle") { app.setPlayed(video, false) }
        } else {
            Button("Mark as Watched", systemImage: "checkmark.circle") { app.setPlayed(video, true) }
            if app.isSavedForLater(video) {
                Button("Remove from Watch Later", systemImage: "tray.and.arrow.up") { app.setWatchLater([video], false) }
            } else {
                Button("Save to Watch Later", systemImage: "arrowshape.bounce.forward") { app.setWatchLater([video], true) }
            }
        }
        if app.isBookmarked(video) {
            Button("Remove Bookmark", systemImage: "bookmark.slash") { app.setBookmarked(video, false) }
        } else {
            Button("Bookmark", systemImage: "bookmark") { app.setBookmarked(video, true) }
        }
    }
}

/// A long-video creator or playlist on iPhone: its gallery. Picking a video plays it full screen.
struct LongCreatorView: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    @Environment(Router.self) private var router
    let username: String

    var body: some View {
        let library = app.library(username, form: .long)
        Group {
            if let library {
                LongGallery(library: library) { index in
                    playback.start(app.longVideos(library), at: index, mode: .longCreator(username))
                    router.open(.player(.longCreator(username)))
                }
            } else {
                ContentUnavailableView("No Videos Yet", systemImage: "rectangle.stack")
            }
        }
        .navigationTitle(library?.creator.displayName ?? "@\(creatorHandle(username))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let library, library.creator.isYouTube, !library.creator.isPlaylist {
                Button("Older Videos", systemImage: "clock.arrow.circlepath") {
                    router.olderVideos = OlderVideosTarget(id: library.id, name: library.creator.displayName)
                }
                .accessibilityIdentifier("olderVideos")
            }
            if let library, !library.videos.isEmpty {
                Menu("Mark All", systemImage: "ellipsis.circle") { MarkAllButtons(library: library) }
            }
        }
        .safeAreaInset(edge: .bottom) { NowPlayingBar() }
    }
}

/// A playlist's YouTube thumbnail cropped to a rounded square, or the playlist mark until it has one.
struct PlaylistThumbnail: View {
    @Environment(AppState.self) private var app
    let library: CreatorLibrary
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        ZStack {
            Rectangle().fill(.quaternary)
            if let image = UIImage(contentsOfFile: app.store.avatarFile(library.id).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                CuratedMark(kind: .all, height: size * 0.55)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.15)) }
    }
}

/// The long Home's last card: one row per YouTube playlist, with its thumbnail, name, how many videos are watched and
/// unwatched, and its length. A row opens the playlist's gallery.
struct PlaylistsCard: View {
    @Environment(AppState.self) private var app
    let playlists: [CreatorLibrary]
    let open: (PlaybackMode) -> Void
    /// What the iPad sidebar has selected, highlighted here.
    var selection: PlaybackMode?

    var body: some View {
        let expanded = !app.collapsedCards.contains("playlists")
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { app.setCollapsed("playlists", expanded) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    CuratedMark(kind: .all, height: 16)
                    Text("Playlists").font(.headline).lineLimit(1)
                    CountBadge(count: playlists.reduce(0) { $0 + app.unplayedCount($1) })
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .accessibilityHint(expanded ? "Collapses" : "Expands")
            if expanded {
                VStack(spacing: 2) {
                    ForEach(playlists) { row($0) }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
        .cardBackground()
    }

    private func row(_ playlist: CreatorLibrary) -> some View {
        let selected = selection == .longCreator(playlist.id)
        let unwatched = app.unplayedCount(playlist)
        let count = playlist.videos.count
        return Button { open(.longCreator(playlist.id)) } label: {
            HStack(spacing: 12) {
                PlaylistThumbnail(library: playlist, size: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.creator.displayName).font(.body.weight(.medium)).lineLimit(1)
                    Group {
                        Text("\(count) video\(count == 1 ? "" : "s") · \(formatLength(playlist.videos.reduce(0) { $0 + ($1.duration ?? 0) }))")
                        Text("\(count - unwatched) watched / \(unwatched) unwatched")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { CreatorMenuButtons(library: playlist) }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// When a long video ends with autoplay off: what's next, to play, or the one that just ended again.
struct UpNextCard: View {
    @Environment(Playback.self) private var playback
    let next: Video

    var body: some View {
        VStack(spacing: 12) {
            Text("Up Next").font(.headline).foregroundStyle(.secondary)
            LongThumbnail(video: next, cornerRadius: 12).frame(width: 260)
            Text(next.displayTitle).font(.title3.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
                .frame(maxWidth: 300)
            HStack(spacing: 10) {
                Button { playback.replay() } label: { Label("Replay", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(GlassChipStyle(selected: false))
                Button { playback.playNext() } label: { Label("Play Next", systemImage: "play.fill") }
                    .buttonStyle(GlassChipStyle(selected: true))
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .glassBackground(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(24)
        .environment(\.colorScheme, .dark)
    }
}

/// Long videos play in Apple's own player (AVPlayerViewController), like the TV app: its controls skip back and ahead
/// 10 seconds, scrub, change speed, and go full screen (turning an iPhone sideways) or picture in picture. It shares
/// Playback's one AVPlayer, so the queue, resume and Up Next work as for short videos.
struct StockPlayerView: UIViewControllerRepresentable {
    let playback: Playback
    /// Off when the screen has its own controls (iPhone Duo partly folded).
    var showsControls = true

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        // Playback keeps the lock screen and Control Center up to date itself.
        controller.updatesNowPlayingInfoCenter = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        controller.view.backgroundColor = .clear
        controller.delegate = context.coordinator
        playback.show(in: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.showsPlaybackControls = showsControls
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.playback.hide(from: controller)
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        let playback: Playback
        init(playback: Playback) { self.playback = playback }

        // Full screen holds an iPhone sideways until it's left (OrientationLock).
        nonisolated func playerViewController(_ controller: AVPlayerViewController,
                                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            MainActor.assumeIsolated {
                playback.isStockFullscreen = true
                OrientationLock.lockLandscape(true, in: controller.view.window?.windowScene)
            }
        }

        nonisolated func playerViewController(_ controller: AVPlayerViewController,
                                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
            MainActor.assumeIsolated {
                let scene = controller.view.window?.windowScene
                coordinator.animate(alongsideTransition: nil) { [playback] context in
                    guard !context.isCancelled else { return }
                    OrientationLock.lockLandscape(false, in: scene)
                    playback.isStockFullscreen = false
                }
            }
        }

        nonisolated func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
            MainActor.assumeIsolated { playback.setStockPip(true) }
        }

        nonisolated func playerViewController(_ controller: AVPlayerViewController,
                                              failedToStartPictureInPictureWithError error: Error) {
            Diagnostics.log("Stock player PiP failed to start: \(error)")
        }

        nonisolated func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
            MainActor.assumeIsolated { playback.setStockPip(false) }
        }

        nonisolated func playerViewController(_ controller: AVPlayerViewController,
                                              restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
            completion(true)
        }
    }
}

/// A long video full screen (from the player's full screen button, upright or sideways): only the video, held sideways
/// until the exit button (OrientationLock), like YouTube.
struct LongFullscreen: View {
    @Environment(Playback.self) private var playback
    let exit: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LongVideoPlayer(fullscreen: true, toggleFullscreen: exit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .environment(\.colorScheme, .dark)
    }
}

/// A long video on an iPhone, upright or full screen: our own layer and controls rather than the stock player's, so
/// both are the same player and full screen is ours to hold sideways. A tap shows the controls (back and ahead 10
/// seconds, play or pause, the scrub bar, full screen or exit; picture in picture is in the page's buttons); while playing they go away 3 seconds
/// after the last touch. Full screen adds the speed menu, picture in picture, bookmark and watched at the top right,
/// double taps on either half to skip, and holding the right half for 2×. The Up Next and caught-up cards take their
/// place at the end of a video.
struct LongVideoPlayer: View {
    @Environment(AppState.self) private var app
    @Environment(Playback.self) private var playback
    let fullscreen: Bool
    let toggleFullscreen: () -> Void
    @State private var controlsShown = true
    /// Each touch keeps the controls up 3 more seconds.
    @State private var touches = 0
    /// Full screen: the last tap's side (-1 left, 1 right) and time, to tell a double tap.
    @State private var lastTapSide = 0
    @State private var lastTapAt = Date.distantPast
    /// A single tap waits to see if it's the start of a double tap.
    @State private var pendingTap: Task<Void, Never>?
    /// Holding the right half: 2× after a moment.
    @State private var holdTask: Task<Void, Never>?
    @State private var pressing = false
    /// The skip being shown: its side (0 for none), the seconds so far, and a count to keep it up while taps go on.
    @State private var skipSide = 0
    @State private var skipSeconds = 0
    @State private var skips = 0
    /// Full screen: pinch to zoom, from the whole video past filling the screen (as on Android).
    @State private var zoom = VideoZoom()
    /// The pinch's magnification when last seen, to zoom by each change.
    @State private var lastMagnification: CGFloat = 1
    /// This touch pinched or panned the zoomed video, so it's not a tap or a hold.
    @State private var zoomTouch = false
    @State private var lastTranslation: CGSize = .zero

    var body: some View {
        let ended = playback.finished || playback.awaitingNext
        ZStack {
            VideoSurface(playback: playback)
                .aspectRatio(playback.videoAspect ?? 16 / 9, contentMode: .fit)
                .scaleEffect(fullscreen ? zoom.scale : 1)
                .offset(fullscreen ? zoom.pan : .zero)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            // Taps anywhere bring the controls up or put them away. Full screen: double-tap the right half to skip
            // ahead 10 seconds and the left half to go back (each further tap 10 more), and hold the right half for
            // 2×. The buttons sit above it, each with a whole 44-point target of its own.
            gestureLayer
            if controlsShown && !ended { controls.transition(.opacity) }
            if skipSide != 0 { skipFlash.transition(.opacity) }
            if playback.isHoldingFast {
                Label("2×", systemImage: "forward.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .glassBackground(in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 20)
                    .allowsHitTesting(false)
            }
            if playback.finished && !playback.endsInSunshine { FinishedCard().frame(maxWidth: .infinity, maxHeight: .infinity) }
            if playback.awaitingNext, let next = playback.upNext {
                UpNextCard(next: next).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            // Always there at the end of a video in full screen, when the cards replace the other controls.
            if fullscreen && (controlsShown || ended) {
                GlassIconButton(symbol: "arrow.down.right.and.arrow.up.left", label: "Exit Full Screen", action: toggleFullscreen)
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // Faded rather than removed, so the speed menu stays open if the controls go away under it.
            if fullscreen, let video = playback.current {
                let shown = controlsShown || ended
                fullscreenButtons(video)
                    .padding(16)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                    .animation(.easeOut(duration: 0.2), value: shown)
            }
        }
        .task(id: [controlsShown, playback.isPlaying, touches] as [AnyHashable]) {
            guard controlsShown, playback.isPlaying else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            setShown(false)
        }
        .task(id: skips) {
            guard skipSide != 0 else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { skipSide = 0 }
        }
        .onDisappear {
            holdTask?.cancel()
            if playback.isHoldingFast { playback.holdFast(false) }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { zoom.container = $0 }
        .onChange(of: playback.videoAspect, initial: true) { _, aspect in zoom.aspect = aspect ?? 16 / 9 }
        .onChange(of: playback.current?.id) { zoom.reset() }
        .environment(\.colorScheme, .dark)
    }

    private var gestureLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if abs(value.translation.width) > 20 || abs(value.translation.height) > 20 { holdTask?.cancel() }
                            if !pressing {
                                pressing = true
                                zoomTouch = false
                                lastTranslation = .zero
                                if fullscreen && value.startLocation.x > geo.size.width / 2 {
                                    holdTask = Task {
                                        try? await Task.sleep(for: .milliseconds(350))
                                        if !Task.isCancelled { playback.holdFast(true) }
                                    }
                                }
                            }
                            // Zoomed in: one finger pans, once it's moved past a tap's wobble.
                            let moved = hypot(value.translation.width, value.translation.height)
                            guard fullscreen, zoom.scale > 1, !playback.isHoldingFast, zoomTouch || moved > 10 else { return }
                            holdTask?.cancel()
                            if !zoomTouch { zoomTouch = true }
                            zoom.drag(by: CGSize(width: value.translation.width - lastTranslation.width,
                                                 height: value.translation.height - lastTranslation.height))
                            lastTranslation = value.translation
                        }
                        .onEnded { value in
                            holdTask?.cancel()
                            pressing = false
                            if playback.isHoldingFast { return playback.holdFast(false) }
                            guard !zoomTouch else { return zoomTouch = false }
                            guard abs(value.translation.width) < 12, abs(value.translation.height) < 12 else { return }
                            tapped(side: value.location.x > geo.size.width / 2 ? 1 : -1)
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            holdTask?.cancel()
                            zoomTouch = true
                            zoom.pinch(by: value.magnification / lastMagnification, about: value.startLocation)
                            lastMagnification = value.magnification
                        }
                        .onEnded { _ in
                            lastMagnification = 1
                            withAnimation(.spring(duration: 0.35)) { zoom.settle() }
                        },
                    including: fullscreen ? .all : .subviews
                )
        }
        .accessibilityElement()
        .accessibilityLabel("Video")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { setShown(!controlsShown) }
        .accessibilityAction(named: "Back 10 seconds") { skip(-1) }
        .accessibilityAction(named: "Ahead 10 seconds") { skip(1) }
    }

    private func tapped(side: Int) {
        guard fullscreen else { return setShown(!controlsShown) }
        let now = Date()
        pendingTap?.cancel()
        if side == lastTapSide && now.timeIntervalSince(lastTapAt) < 0.3 {
            skip(side)
        } else {
            pendingTap = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                setShown(!controlsShown)
            }
        }
        lastTapSide = side
        lastTapAt = now
    }

    private func skip(_ side: Int) {
        let length = playback.current?.duration ?? 0
        let target = max(0, playback.position + Double(side * 10))
        playback.seek(to: length > 0 ? min(length, target) : target)
        if skipSide == side { skipSeconds += 10 } else { skipSeconds = 10 }
        withAnimation(.easeOut(duration: 0.15)) { skipSide = side }
        skips += 1
        if controlsShown { touches += 1 }
    }

    /// How far the double taps went, on their side.
    private var skipFlash: some View {
        VStack(spacing: 6) {
            Image(systemName: skipSide > 0 ? "goforward" : "gobackward").font(.title2.weight(.semibold))
            Text("\(skipSeconds) sec").font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .frame(width: 88, height: 88)
        .glassBackground(in: Circle())
        .frame(maxWidth: .infinity, alignment: skipSide > 0 ? .trailing : .leading)
        .padding(.horizontal, 60)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Full screen's buttons at the top right: the speed (a menu of speeds), picture in picture, bookmark and watched.
    private func fullscreenButtons(_ video: Video) -> some View {
        let bookmarked = app.isBookmarked(video)
        let played = app.isPlayed(video)
        return HStack(spacing: 12) {
            Menu {
                Picker("Playback Speed", selection: Binding(get: { playback.shownSpeed }, set: { playback.setSpeed($0) })) {
                    ForEach(Playback.speeds, id: \.self) { Text(formatSpeed($0)).tag($0) }
                }
            } label: {
                Text(formatSpeed(playback.shownSpeed))
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 44, height: 44)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Playback speed \(formatSpeed(playback.shownSpeed))")
            .speedLock(playback.speedLocked)
            if playback.canStartPip {
                GlassIconButton(symbol: "pip.enter", label: "Picture in Picture") { playback.startPip() }
            }
            GlassIconButton(symbol: bookmarked ? "bookmark.fill" : "bookmark",
                            label: bookmarked ? "Bookmarked. Remove bookmark" : "Bookmark") {
                touches += 1
                playback.toggleBookmark()
            }
            GlassIconButton(symbol: played ? "checkmark.circle.fill" : "circle",
                            label: played ? "Watched. Mark as unwatched" : "Mark as watched") {
                touches += 1
                app.setPlayed(video, !played)
            }
        }
        .foregroundStyle(.white)
    }

    private func setShown(_ shown: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { controlsShown = shown }
        touches += 1
    }

    /// A control: its action, and the controls stay up 3 more seconds.
    private func control(_ label: String, symbol: String, size: CGFloat = 44, font: Font? = nil,
                         action: @escaping () -> Void) -> some View {
        Button {
            touches += 1
            action()
        } label: {
            Group {
                if let font { Image(systemName: symbol).font(font) } else { Image(systemName: symbol) }
            }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var controls: some View {
        ZStack {
            Color.black.opacity(0.3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            HStack(spacing: fullscreen ? 44 : 32) {
                control("Back 10 seconds", symbol: "gobackward.10", size: 56) {
                    playback.seek(to: max(0, playback.position - 10))
                }
                control(playback.isPlaying ? "Pause" : "Play", symbol: playback.isPlaying ? "pause.fill" : "play.fill",
                        size: 68, font: .system(size: fullscreen ? 44 : 38)) {
                    playback.togglePlayPause()
                }
                control("Ahead 10 seconds", symbol: "goforward.10", size: 56) {
                    let length = playback.current?.duration ?? 0
                    playback.seek(to: length > 0 ? min(length, playback.position + 10) : playback.position + 10)
                }
            }
            .font(.system(size: fullscreen ? 28 : 24, weight: .medium))
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    if let length = playback.current?.duration, length > 0 {
                        Text(formatClock(playback.position)).monospacedDigit()
                        ScrubBar(length: length)
                            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in touches += 1 })
                        Text(formatClock(length)).monospacedDigit()
                    } else {
                        Spacer()
                    }
                    if !fullscreen {
                        control("Full Screen", symbol: "arrow.up.left.and.arrow.down.right",
                                font: .system(size: 18, weight: .medium), action: toggleFullscreen)
                    }
                }
                .font(.caption.weight(.medium))
                .padding(.leading, fullscreen ? 24 : 12)
                .padding(.trailing, fullscreen ? 16 : 4)
            }
        }
        .foregroundStyle(.white)
    }
}

/// Pinch zoom for a long video full screen, as on Android (`VideoZoom.kt`). A scale of 1 shows the whole video (fit);
/// `fill` is where it covers the whole screen. Around `fill` the pinch holds still for a stretch (with a tick), so it's
/// easy to land on, then carries on past it. While zoomed in, one finger pans, never past the video's edges.
@MainActor @Observable
final class VideoZoom {
    private(set) var scale: CGFloat = 1
    private(set) var pan: CGSize = .zero
    /// The video area's size and the video's width / height, kept up to date by the player.
    var container: CGSize = .zero {
        didSet { if container != oldValue { reset() } }
    }
    var aspect: CGFloat = 16 / 9
    /// The pinch's own scale, before the hold at fill; scale is worked out from it.
    @ObservationIgnored private var raw: CGFloat = 1
    @ObservationIgnored private let tick = UIImpactFeedbackGenerator(style: .light)

    /// How much pinching (as a log of the scale, about ±12%) the hold at fill takes up.
    private static let snapBand: CGFloat = 0.12

    /// The video's size on screen at a scale of 1.
    private var fitted: CGSize {
        guard container.width > 0, container.height > 0, aspect > 0 else { return container }
        return container.width / container.height > aspect
            ? CGSize(width: container.height * aspect, height: container.height)
            : CGSize(width: container.width, height: container.width / aspect)
    }

    var fill: CGFloat {
        let f = fitted
        guard f.width > 0, f.height > 0 else { return 1 }
        return max(container.width / f.width, container.height / f.height)
    }

    private var maxScale: CGFloat { max(4, fill * 2) }
    private var hasSnap: Bool { fill > 1.02 }

    func reset() {
        scale = 1
        raw = 1
        pan = .zero
    }

    /// The scale shown for a raw pinch scale: the same, less a band around fill (in log terms) that sticks at fill.
    private func shown(_ raw: CGFloat) -> CGFloat {
        guard hasSnap else { return raw }
        let r = log(raw / fill)
        return abs(r) < Self.snapBand ? fill : fill * exp(r - (r < 0 ? -1 : 1) * Self.snapBand)
    }

    private func rawFor(_ shown: CGFloat) -> CGFloat {
        guard hasSnap, shown != fill else { return shown }
        let r = log(shown / fill)
        return fill * exp(r + (r < 0 ? -1 : 1) * Self.snapBand)
    }

    private func clamped(_ offset: CGSize, scale: CGFloat) -> CGSize {
        let maxX = max(0, (fitted.width * scale - container.width) / 2)
        let maxY = max(0, (fitted.height * scale - container.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }

    /// Two fingers: zoom by `factor` about `centroid` (in the video area).
    func pinch(by factor: CGFloat, about centroid: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }
        raw *= factor
        var next = shown(raw)
        if next < 1 || next > maxScale {
            next = min(maxScale, max(1, next))
            raw = rawFor(next)
        }
        if next == fill && scale != fill && hasSnap { tick.impactOccurred() }
        // Keep the point under the fingers where it is.
        let c = CGSize(width: centroid.x - container.width / 2, height: centroid.y - container.height / 2)
        let ratio = next / scale
        pan = clamped(CGSize(width: c.width + (pan.width - c.width) * ratio,
                             height: c.height + (pan.height - c.height) * ratio), scale: next)
        scale = next
    }

    func drag(by delta: CGSize) {
        pan = clamped(CGSize(width: pan.width + delta.width, height: pan.height + delta.height), scale: scale)
    }

    /// Fingers lifted: a scale only just above 1 settles back to the whole video (animated by the caller).
    func settle() {
        guard scale < 1.05, scale != 1 else { return }
        reset()
    }
}

/// The app turns as Settings allow, and while a long video is full screen on an iPhone it's held sideways, whichever
/// way the phone is turned, until the user leaves full screen (like YouTube). Leaving lets it turn again and puts it
/// the way the phone is actually held.
/// Settings can keep it upright (`landscapeAllowed`, kept up to date by RootView). iPad and iPhone Duo's inner display
/// may turn anyway; RootView then shows the upright layout.
@MainActor
enum OrientationLock {
    private(set) static var landscapeLocked = false
    /// Turning sideways is allowed for what's showing (Settings), or a long video can go full screen.
    private(set) static var landscapeAllowed = true
    /// Upright after leaving a turned long video's full screen, until the phone is held upright; otherwise it would go
    /// straight back to full screen.
    private(set) static var portraitHeld = false

    static func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        if landscapeLocked { return .landscape }
        if portraitHeld || !landscapeAllowed { return pad ? [.portrait, .portraitUpsideDown] : .portrait }
        return pad ? .all : .allButUpsideDown
    }

    static func setLandscapeAllowed(_ allowed: Bool, in scene: UIWindowScene?) {
        guard landscapeAllowed != allowed else { return }
        landscapeAllowed = allowed
        refresh(scene, turnUpright: !allowed)
    }

    static func holdPortrait(in scene: UIWindowScene?) {
        landscapeLocked = false
        // Already held upright: nothing to wait for.
        portraitHeld = UIDevice.current.userInterfaceIdiom == .phone && UIDevice.current.orientation != .portrait
        refresh(scene, turnUpright: true)
    }

    /// The phone is held upright: it may turn again.
    static func releasePortrait(in scene: UIWindowScene?) {
        guard portraitHeld else { return }
        portraitHeld = false
        refresh(scene, turnUpright: false)
    }

    private static func refresh(_ scene: UIWindowScene?, turnUpright: Bool) {
        guard let scene else { return }
        for window in scene.windows { window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        guard turnUpright, !scene.effectiveGeometry.interfaceOrientation.isPortrait else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
            Diagnostics.log("Turning upright failed: \(error)")
        }
    }

    static func lockLandscape(_ locked: Bool, in scene: UIWindowScene?) {
        guard UIDevice.current.userInterfaceIdiom == .phone, landscapeLocked != locked else { return }
        // iPhone Duo's inner display (regular width) keeps its own layouts either way up.
        if locked, scene?.traitCollection.horizontalSizeClass == .regular { return }
        landscapeLocked = locked
        if locked { portraitHeld = false }
        guard let scene else { return }
        for window in scene.windows { window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        if locked {
            guard scene.effectiveGeometry.interfaceOrientation.isPortrait else { return }
            // The way the phone is tipped, if it is; otherwise the usual way (top to the left).
            let device = UIDevice.current.orientation
            let side: UIInterfaceOrientationMask = device == .landscapeRight ? .landscapeLeft : .landscapeRight
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: side)) { error in
                Diagnostics.log("Turning sideways for full screen failed: \(error)")
            }
        } else if !UIDevice.current.orientation.isLandscape, !scene.effectiveGeometry.interfaceOrientation.isPortrait {
            // Held upright (or flat) after full screen: back to the upright player.
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
                Diagnostics.log("Turning upright after full screen failed: \(error)")
            }
        }
    }
}

/// Asks OrientationLock which ways the app may turn.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.mask(for: window) }
    }
}
