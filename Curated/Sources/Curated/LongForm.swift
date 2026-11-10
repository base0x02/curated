import SwiftUI

// Views for long videos: the full-width player with its Up Next panel, the creator gallery, and their thumbnails.

/// The player for long videos, full width. Its queue slides up from the bottom as an Up Next panel, like the phones'.
struct LongPlayerPane: View {
    #if DEBUG
    /// CURATED_TEST_UPNEXT=1 opens it straight away, for tests.
    @State private var showUpNext = ProcessInfo.processInfo.environment["CURATED_TEST_UPNEXT"] != nil
    #else
    @State private var showUpNext = false
    #endif

    var body: some View {
        PlayerPane(long: true)
            .environment(\.toggleUpNext, EnvironmentAction { setUpNext(!showUpNext) })
            .focusedSceneValue(\.toggleUpNextFromMenu, EnvironmentAction { setUpNext(!showUpNext) })
            .focusedSceneValue(\.upNextShown, showUpNext)
            .overlay(alignment: .bottom) {
                if showUpNext {
                    UpNextPanel { setUpNext(false) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    private func setUpNext(_ shown: Bool) {
        withAnimation(.snappy(duration: 0.3)) { showUpNext = shown }
    }
}

/// The loaded queue as wide rows with room for titles and descriptions, over the bottom half of the player.
/// Clicking a video plays it and closes the panel.
struct UpNextPanel: View {
    @Environment(Playback.self) private var playback
    let close: () -> Void

    var body: some View {
        @Bindable var playback = playback
        let showCreator = if case .creator = playback.mode { false } else { true }
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Up Next").font(.headline)
                Text("\(playback.unwatched.count) unwatched · \(formatLength(playback.unwatchedSecondsLeft)) left")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Autoplay", isOn: $playback.autoplayLong)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help("Start the next video when one ends")
                Button(action: close) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Hide Up Next")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(playback.queue.enumerated()), id: \.element.id) { index, video in
                        LongVideoRow(video: video, isCurrent: playback.current?.id == video.id, showCreator: showCreator)
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
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical) { height, _ in height * 0.55 }
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18))
        .shadow(color: .black.opacity(0.35), radius: 16, y: -2)
    }
}

/// A long video in a list: the thumbnail, then its title, creator, description and details.
struct LongVideoRow: View {
    @Environment(AppModel.self) private var model
    let video: Video
    let isCurrent: Bool
    let showCreator: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            LongThumbnail(video: video, isCurrent: isCurrent)
                .frame(width: 192)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.displayTitle).font(.headline).lineLimit(2)
                if showCreator, let library = model.library(for: video.creator, form: .long) {
                    Text(library.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                }
                if !video.details.isEmpty {
                    Text(video.details).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                LongVideoMeta(video: video)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

/// "Watched · 3 days ago · 1.2M views", with Watch Later and bookmark marks.
struct LongVideoMeta: View {
    @Environment(AppModel.self) private var model
    let video: Video
    /// Shown in bold after the view count, while managing videos.
    var size: Int64? = nil

    var body: some View {
        HStack(spacing: 6) {
            if model.isPlayed(video) {
                Label("Watched", systemImage: "checkmark.circle.fill")
                Text("·")
            } else if model.isSavedForLater(video) {
                Label("Later", systemImage: "tray.and.arrow.down.fill")
                Text("·")
            }
            if model.isBookmarked(video) {
                Image(systemName: "bookmark.fill").help("Bookmarked")
                Text("·")
            }
            Text(video.date, format: .relative(presentation: .named))
            if let views = video.viewCount {
                Text("·")
                Text("\(views.formatted(.number.notation(.compactName))) views")
            }
            if let size {
                Text("·")
                Text(size.formatted(.byteCount(style: .file)))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)  // white in dark mode
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// A long video's 16:9 thumbnail with rounded corners: its length in the bottom-right corner, a red bar for how far
/// it's been watched, and dimmed once it has been.
struct LongThumbnail: View {
    @Environment(AppModel.self) private var model
    let video: Video
    var isCurrent = false
    var cornerRadius: CGFloat = 10

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let length = model.duration(of: video)
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                // Without a poster, a frame a little way in: the very start is often black.
                ThumbnailView(url: video.url, time: min(60, (length ?? 0) * 0.1 + 0.5))
            }
            .overlay(alignment: .bottom) {
                if let progress = model.progress(of: video) {
                    GeometryReader { geo in
                        // A dark track, so the red reads on any thumbnail (even a red one).
                        // The red sits under a thin dark edge so it stands apart from the picture above it.
                        ZStack(alignment: .bottomLeading) {
                            Rectangle().fill(.black.opacity(0.7))
                            Rectangle().fill(Color.red).frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .clipShape(shape)
            .overlay(alignment: .bottomTrailing) {
                if let length, length > 0 {
                    Text(formatClock(length))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(.trailing, 6)
                        .padding(.bottom, model.progress(of: video) == nil ? 6 : 10)
                }
            }
            .opacity(model.isPlayed(video) && !isCurrent ? 0.5 : 1)
            .overlay {
                if isCurrent {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2.5)
                    Image(systemName: "play.fill").font(.title2).foregroundStyle(.white).shadow(radius: 3)
                }
            }
    }
}

/// Shown over the player when a long video ends with autoplay off: what's next, to play or skip.
struct UpNextCard: View {
    @Environment(Playback.self) private var playback
    let next: Video

    var body: some View {
        VStack(spacing: 12) {
            Text("Up Next").font(.headline).foregroundStyle(.secondary)
            LongThumbnail(video: next, cornerRadius: 12)
                .frame(width: 300)
            Text(next.displayTitle)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 320)
            HStack(spacing: 10) {
                Button { playback.replay() } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                }
                .glassButtonStyle()
                Button { playback.playNext() } label: {
                    Label("Play Next", systemImage: "play.fill")
                }
                .glassButtonStyle(prominent: true)
            }
            .controlSize(.large)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// A long-video creator from the sidebar: a gallery of their videos. Picking one hides the gallery and plays it; the
/// back button (or the video ending, with autoplay off) brings the gallery back.
struct LongCreatorView: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    let library: CreatorLibrary
    @State private var showGallery = true
    /// Shows a delete button on each thumbnail and each video's file size.
    #if DEBUG
    @State private var managing = ProcessInfo.processInfo.environment["CURATED_TEST_MANAGE"] != nil  // for tests
    #else
    @State private var managing = false
    #endif
    @State private var deleting: Video?

    private var isLoaded: Bool { playback.isLoaded(.creator(library.id), form: .long) && playback.current != nil }
    private var ended: Bool { playback.awaitingNext || playback.finished }

    var body: some View {
        Group {
            if showGallery || !isLoaded {
                gallery
            } else {
                LongPlayerPane()
                    .overlay(alignment: .topLeading) { backButton }
            }
        }
        .navigationTitle(library.displayName)
        .toolbar {
            if library.creator.canPickOlderLong {
                Button { model.pickOlderLong(library.creator) } label: {
                    Label("Older Videos", systemImage: "clock.arrow.circlepath")
                }
                .help("See this creator's older videos on YouTube, and pick some to download")
                .disabled(model.isDownloading)
            }
            Menu {
                Button(managing ? "Done Managing" : "Manage Videos",
                       systemImage: managing ? "checkmark" : "pencil") {
                    withAnimation(.snappy(duration: 0.2)) { managing.toggle() }
                    if managing { showGallery = true }
                }
                Divider()
                MarkAllMenuItems(library: library)
            } label: {
                Label("Manage", systemImage: managing ? "checklist.checked" : "checklist")
            }
            .help("Manage this creator's videos: delete them, see their sizes, or mark them all watched or unwatched")
            .disabled(library.videos.isEmpty)
        }
        .confirmationDialog("Are you sure you want to delete \(deleting.map { "“\($0.displayTitle)”" } ?? "this video")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { video in
            Button("Delete Video", role: .destructive) { delete(video) }
        } message: { _ in
            Text("It moves to the Trash and won't be downloaded again.")
        }
        .onChange(of: library.videos.isEmpty) { _, empty in if empty { managing = false } }
        .onAppear {
            // Coming back to a video that's still going (e.g. from Now Playing) shows the player.
            showGallery = !(isLoaded && !ended)
        }
        .onChange(of: ended) { _, ended in
            if ended && isLoaded { withAnimation(.snappy(duration: 0.3)) { showGallery = true } }
        }
    }

    private var backButton: some View {
        Button {
            playback.player.pause()
            withAnimation(.snappy(duration: 0.3)) { showGallery = true }
        } label: {
            Label("All Videos", systemImage: "chevron.left")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule()
        .environment(\.colorScheme, .dark)
        .padding(12)
        .help("Back to \(library.displayName)'s videos (pauses this one; it picks up where you left off)")
    }

    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    AvatarView(library: library, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(library.displayName).font(.title2.weight(.bold))
                        Text(summary).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        Text("\(totalSize.formatted(.byteCount(style: .file))) on disk")
                            .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if library.videos.isEmpty {
                    ContentUnavailableView("No long videos yet", systemImage: "rectangle.stack",
                                           description: Text("They're downloaded with this creator's other videos, or with Download Long-Form Videos in Creators & Downloads."))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 20, alignment: .top)],
                              alignment: .leading, spacing: 28) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            GalleryCard(video: video, isCurrent: isLoaded && playback.current?.id == video.id,
                                        size: managing ? Library.fileSize(video.url) : nil,
                                        onPlay: { play(index) },
                                        onDelete: managing ? { deleting = video } : nil)
                                .contextMenu { VideoContextMenu(video: video) }
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    /// A playlist keeps its own order; a creator's hand-picked videos come first.
    private var videos: [Video] { library.creator.playlist ? library.videos : model.handPickedFirst(library.videos) }

    /// "12 videos · 3 unwatched · 4h 20m"
    private var summary: String {
        let count = library.videos.count
        return "\(count) video\(count == 1 ? "" : "s") · \(model.unplayedCount(library)) unwatched · "
            + formatLength(model.totalDuration(library.videos))
    }

    /// The videos plus their posters.
    private var totalSize: Int64 {
        library.videos.reduce(0) { $0 + (Library.fileSize($1.url) ?? 0) + (Library.fileSize($1.posterURL) ?? 0) }
    }

    private func delete(_ video: Video) {
        if playback.current?.id == video.id { playback.stop() }
        model.trash(video)
    }

    private func play(_ index: Int) {
        playback.start(videos, at: index, mode: .creator(library.id), form: .long)
        withAnimation(.snappy(duration: 0.3)) { showGallery = false }
    }
}

/// One video in the creator gallery: thumbnail, then title, description and details underneath.
/// While managing, it also shows the file size and a delete button in the thumbnail's top-right corner.
struct GalleryCard: View {
    let video: Video
    let isCurrent: Bool
    var size: Int64? = nil
    let onPlay: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LongThumbnail(video: video, isCurrent: isCurrent, cornerRadius: 12)
                .overlay(alignment: .topTrailing) {
                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.7))
                                .shadow(radius: 2)
                                .padding(6)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Delete “\(video.displayTitle)”")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(hovering ? 1.02 : 1)
                .shadow(color: .black.opacity(hovering ? 0.25 : 0), radius: 8, y: 3)
            Text(video.displayTitle).font(.headline).lineLimit(2)
            if !video.details.isEmpty {
                Text(video.details).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            LongVideoMeta(video: video, size: size)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
        .accessibilityAddTraits(.isButton)
    }
}

/// The long sidebar's last card: one row per YouTube playlist, with its icon, name, how many videos are watched and
/// unwatched, and its length. A row opens the playlist's gallery.
struct PlaylistsCard: View {
    @Environment(AppModel.self) private var model
    let playlists: [CreatorLibrary]
    @Binding var selection: SidebarItem?
    @AppStorage("playlistsExpanded") private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 10)
                    FormMark(name: "all", height: 14)
                    Text("Playlists").fontWeight(.semibold).lineLimit(1)
                    UnplayedCountCapsule(count: playlists.reduce(0) { $0 + model.unplayedCount($1) })
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Collapse" : "Expand")
            if expanded {
                VStack(spacing: 2) {
                    ForEach(playlists) { row($0) }
                }
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

    private func row(_ playlist: CreatorLibrary) -> some View {
        let selected = selection == .creator(playlist.id)
        let unwatched = model.unplayedCount(playlist)
        let count = playlist.videos.count
        return Button {
            selection = .creator(playlist.id)
        } label: {
            HStack(spacing: 10) {
                PlaylistThumbnail(library: playlist, size: 36)
                // Name, then "12 videos · 4h 20m", then "3 watched / 9 unwatched", so a narrow sidebar cuts nothing off.
                VStack(alignment: .leading, spacing: 1) {
                    Text(playlist.displayName).font(.callout.weight(.medium)).lineLimit(2)
                    Group {
                        Text("\(count) video\(count == 1 ? "" : "s") · \(formatLength(model.totalDuration(playlist.videos)))")
                        Text("\(count - unwatched) watched / \(unwatched) unwatched")
                    }
                    .font(.caption)
                    .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                    .monospacedDigit()
                    .lineLimit(1)
                }
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(playlist.displayName) · \(unwatched) unwatched")
        .contextMenu {
            OpenCreatorButton(creator: playlist.creator)
            MarkAllMenuItems(library: playlist)
        }
    }
}

/// A playlist's YouTube thumbnail cropped to a rounded square, or the playlist mark if it has none yet.
struct PlaylistThumbnail: View {
    let library: CreatorLibrary
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Group {
            if let url = library.avatar, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                FormMark(name: "all", height: size * 0.6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.white.opacity(0.15)) }
    }
}
