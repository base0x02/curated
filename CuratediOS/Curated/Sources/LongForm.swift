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
                Label("Later", systemImage: "tray.and.arrow.down.fill")
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
    let video: Video
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LongThumbnail(video: video, isCurrent: isCurrent, cornerRadius: 12)
            Text(video.displayTitle).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
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
                Button("Save to Watch Later", systemImage: "tray.and.arrow.down") { app.setWatchLater([video], true) }
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
/// after the last touch. The Up Next and caught-up cards take their place at the end of a video.
struct LongVideoPlayer: View {
    @Environment(Playback.self) private var playback
    let fullscreen: Bool
    let toggleFullscreen: () -> Void
    @State private var controlsShown = true
    /// Each touch keeps the controls up 3 more seconds.
    @State private var touches = 0

    var body: some View {
        let ended = playback.finished || playback.awaitingNext
        ZStack {
            // Taps on the video bring the controls up; on the dimmed controls, put them away. The buttons sit above
            // both, each with a whole 44-point target of its own.
            VideoSurface(playback: playback)
                .aspectRatio(playback.videoAspect ?? 16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { setShown(true) }
                .accessibilityLabel("Video")
            if controlsShown && !ended { controls.transition(.opacity) }
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
        .task(id: [controlsShown, playback.isPlaying, touches] as [AnyHashable]) {
            guard controlsShown, playback.isPlaying else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            setShown(false)
        }
        .environment(\.colorScheme, .dark)
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
                .contentShape(Rectangle())
                .onTapGesture { setShown(false) }
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

/// The app turns freely, except while a long video is full screen on an iPhone: then it's held sideways, whichever way
/// the phone is turned, until the user leaves full screen (like YouTube). Leaving lets it turn again and puts it the way
/// the phone is actually held.
@MainActor
enum OrientationLock {
    private(set) static var landscapeLocked = false

    static func mask(for window: UIWindow?) -> UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return landscapeLocked ? .landscape : .allButUpsideDown
    }

    static func lockLandscape(_ locked: Bool, in scene: UIWindowScene?) {
        guard UIDevice.current.userInterfaceIdiom == .phone, landscapeLocked != locked else { return }
        // iPhone Duo's inner display (regular width) keeps its own layouts either way up.
        if locked, scene?.traitCollection.horizontalSizeClass == .regular { return }
        landscapeLocked = locked
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
