import SwiftUI

// The long-video picker: the Long download button in Creators & Downloads lists every new long video first, as a grid
// of thumbnails to pick from, skip (marked watched, never downloaded) or leave for later. Only manual long downloads
// go through it; the scheduled download and Total fetch everything as before.

/// The picker's state, kept in `AppModel.longPick` so it outlives the sheet while its download runs minimized.
struct LongPick {
    /// New long videos from followed creators, suggestions from the YouTube home feed (the Suggested button), or one
    /// creator's videos going back as far as YouTube lists them, a few at a time (`pickOlderLong`).
    enum Kind { case long, suggested, older }

    /// Stops the listing.
    let runner: ProcessRunner
    let kind: Kind
    /// Whose older videos these are.
    var creatorName: String?
    /// How many of the older videos are showing. Load More reveals more of what's already listed; the tiles left out
    /// aren't made, so their thumbnails aren't fetched.
    var olderLimit = DownloadEngine.olderVideosPerLoad
    /// Every creator's new videos as they're listed. A video in a playlist and a creator's list is here twice.
    private(set) var videos: [PendingVideo] = []
    private(set) var errors: [String] = []
    var loading = true
    /// Picked to download; everything starts picked.
    var selected: Set<String> = []
    /// Marked watched and never downloaded, once the download starts.
    var skipped: Set<String> = []
    /// Videos picked to download at another resolution than their creator's, by id (a nil value is Best).
    private(set) var heights: [String: Int?] = [:]
    /// The download is running (or ran), with each picked video's progress.
    var started = false
    var finished = false
    var states: [String: PendingVideo.State] = [:]
    /// False while minimized to the download bar.
    var shown = true

    init(runner: ProcessRunner, kind: Kind = .long) {
        self.runner = runner
        self.kind = kind
    }

    /// Each video once, newest first. An older-videos listing already is, and its dates are too rough to sort by
    /// (YouTube only says "3 years ago").
    var allVideos: [PendingVideo] {
        var seen = Set<String>()
        let unique = videos.filter { seen.insert($0.id).inserted }
        if kind == .older { return unique }
        return unique.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// What's showing: an older-videos listing only as far as Load More has got.
    var shownVideos: [PendingVideo] {
        kind == .older ? Array(allVideos.prefix(olderLimit)) : allVideos
    }

    /// Load More.
    mutating func loadMore() { olderLimit += DownloadEngine.olderVideosPerLoad }

    /// What the download fetches: selected and not skipped.
    var picked: Set<String> { selected.subtracting(skipped) }

    mutating func add(_ found: [PendingVideo], error: String?, selecting: Bool = true) {
        videos += found
        if selecting { selected.formUnion(found.map(\.id)) }
        if let error, !errors.contains(error) { errors.append(error) }
    }

    func isPicked(_ id: String) -> Bool { selected.contains(id) && !skipped.contains(id) }

    /// Clicking a tile: picks or unpicks it; a skipped one comes back picked.
    mutating func toggle(_ id: String) {
        if skipped.remove(id) != nil { selected.insert(id) }
        else if selected.remove(id) == nil { selected.insert(id) }
    }

    mutating func toggleSkip(_ id: String) {
        if skipped.remove(id) == nil { skipped.insert(id) }
    }

    /// The resolution video `id` downloads at: the one picked for it, or else its creator's (`creatorHeight`).
    func height(_ id: String, creatorHeight: Int?) -> Int? { heights[id] ?? creatorHeight }

    /// Picking the creator's own resolution clears the override.
    mutating func setHeight(_ height: Int?, for id: String, creatorHeight: Int?) {
        if height == creatorHeight { heights.removeValue(forKey: id) } else { heights[id] = .some(height) }
    }

    mutating func selectAll() { selected = Set(videos.map(\.id)).subtracting(skipped) }
    mutating func selectNone() { selected = [] }

    /// A creator finished: any of its picked videos that never finished failed.
    mutating func finish(_ ids: Set<String>) {
        for id in ids where states[id] != .done { states[id] = .failed }
    }
}

/// The picker's sheet: the grid while picking, then the picked videos' progress, which can be minimized.
struct LongPickerView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 16)]

    var body: some View {
        if let pick = model.longPick {
            let videos = pick.started ? pick.allVideos.filter { pick.states[$0.id] != nil } : pick.shownVideos
            VStack(spacing: 0) {
                header(pick, count: videos.count)
                Divider()
                if videos.isEmpty && !pick.loading {
                    Group {
                        if pick.kind == .older {
                            ContentUnavailableView(pick.errors.isEmpty ? "No Older Videos" : "Couldn't List the Videos",
                                                   systemImage: pick.errors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                                                   description: Text(pick.errors.first
                                                       ?? "Every long video from this creator is already downloaded, watched or skipped."))
                        } else if pick.kind == .suggested {
                            ContentUnavailableView(pick.errors.isEmpty ? "No New Suggestions" : "Couldn't Read Your Suggestions",
                                                   systemImage: pick.errors.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                                                   description: Text(pick.errors.first
                                                       ?? "Every long video on your YouTube home feed is already downloaded, watched or skipped."))
                        } else {
                            ContentUnavailableView("No New Long Videos", systemImage: "checkmark.circle",
                                                   description: Text("Every long video in your creators' windows is already downloaded."))
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        if !pick.errors.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(pick.errors, id: \.self) { Text($0) }
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .top], 20)
                        }
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(videos) { video in
                                PendingTile(video: video, pick: pick)
                            }
                        }
                        .padding(20)
                        if pick.kind == .older && !pick.started && !videos.isEmpty {
                            loadMore(pick)
                        }
                    }
                    #if DEBUG
                    // CURATED_TEST_SCROLL=bottom opens at the end of the list, for screenshots.
                    .defaultScrollAnchor(ProcessInfo.processInfo.environment["CURATED_TEST_SCROLL"] == "bottom" ? .bottom : .top)
                    #endif
                }
                Divider()
                footer(pick)
            }
            .frame(minWidth: 760, idealWidth: 940, minHeight: 520, idealHeight: 680)
        }
    }

    /// A text link under the older videos, or a spinner while more are still being listed.
    @ViewBuilder private func loadMore(_ pick: LongPick) -> some View {
        Group {
            if pick.allVideos.count > pick.olderLimit {
                Button("Load More") { model.longPick?.loadMore() }
                    .buttonStyle(.link)
                    .help("Show the next \(DownloadEngine.olderVideosPerLoad) videos")
            } else if pick.loading {
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: 24)
        .padding(.bottom, 20)
    }

    private func header(_ pick: LongPick, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(pick)).font(.title2.weight(.semibold))
                Text(summary(pick, count: count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if !pick.started {
                // A channel's whole history is rarely what anyone means to download.
                if pick.kind != .older {
                    Button("Select All") { model.longPick?.selectAll() }
                        .disabled(pick.videos.allSatisfy { pick.isPicked($0.id) || pick.skipped.contains($0.id) })
                }
                Button("Select None") { model.longPick?.selectNone() }
                    .disabled(pick.selected.isEmpty)
            }
        }
        .padding(20)
    }

    private func title(_ pick: LongPick) -> String {
        switch (pick.kind, pick.started) {
        case (.long, false): "New Long Videos"
        case (.long, true): "Downloading Long Videos"
        case (.suggested, false): "Suggested for You"
        case (.suggested, true): "Downloading Suggestions"
        case (.older, false): "Older Videos from \(pick.creatorName ?? "This Creator")"
        case (.older, true): "Downloading from \(pick.creatorName ?? "This Creator")"
        }
    }

    private func summary(_ pick: LongPick, count: Int) -> String {
        if pick.started {
            let done = pick.states.values.count { $0 == .done }
            let failed = pick.states.values.count { $0 == .failed }
            return "\(done) of \(pick.states.count) downloaded" + (failed > 0 ? " · \(failed) failed" : "")
        }
        var parts: [String]
        if pick.kind == .older {
            let total = pick.allVideos.count
            parts = [total > count ? "\(count) of \(total)\(pick.loading ? "…" : "") videos" : "\(count) video\(count == 1 ? "" : "s")\(pick.loading ? "…" : "")"]
        } else if pick.kind == .suggested {
            let following = pick.shownVideos.count { $0.creatorID != Creator.suggestions.id }
            parts = ["\(count) video\(count == 1 ? "" : "s") from your YouTube home feed"]
            if following > 0 { parts.append("\(following) from creators you follow") }
        } else {
            let creators = Set(pick.videos.map(\.creatorID)).count
            parts = ["\(count) video\(count == 1 ? "" : "s") from \(creators) creator\(creators == 1 ? "" : "s")"]
        }
        if count > 0 { parts.append("\(pick.picked.count) selected") }
        if !pick.skipped.isEmpty { parts.append("\(pick.skipped.count) to skip") }
        return parts.joined(separator: " · ")
    }

    private func footer(_ pick: LongPick) -> some View {
        HStack(spacing: 12) {
            if pick.loading {
                ProgressView().controlSize(.small)
                Text(pick.kind == .suggested ? "Reading your YouTube home feed…"
                     : pick.kind == .older ? "Listing this creator's videos…" : "Looking for new long videos…")
                    .foregroundStyle(.secondary)
            } else if pick.started, !pick.finished, let progress = model.downloadProgress {
                ProgressView(value: progress).frame(maxWidth: 260)
                if let activity = model.lastActivity {
                    Text(activity).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            } else if pick.finished, let message = model.downloadMessage {
                Text(message).foregroundStyle(.secondary)
            } else if !pick.started, !pick.videos.isEmpty {
                Text(pick.kind == .older
                     ? "Videos you pick come first until you've watched them, and stay until you delete them, however old they are. Skipped ones are marked watched and never offered again."
                     : pick.kind == .suggested
                     ? "Videos from creators you follow go to their long videos; the rest go to the Suggestions playlist. Skipped ones are marked watched and never suggested again."
                     : "Unselected videos stay for a later download. Skipped ones are marked watched and never downloaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if pick.started && !pick.finished {
                Button("Stop", role: .destructive) { model.cancelDownloads() }
                Button("Minimize") { model.closeLongPick() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .help("Keep downloading in the download bar. Click the \(pick.kind == .suggested ? "Suggested" : "Long") download button to come back here")
            } else if pick.finished || (!pick.loading && pick.videos.isEmpty) {
                Button("Close") { model.closeLongPick() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { model.closeLongPick() }
                    .keyboardShortcut(.cancelAction)
                Button(startTitle(pick)) { model.startPickedDownload() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled((pick.loading && pick.kind != .older) || (pick.picked.isEmpty && pick.skipped.isEmpty)
                              || (model.isDownloading && !pick.picked.isEmpty))
                    .help(model.isDownloading ? "Another download is running" : "")
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func startTitle(_ pick: LongPick) -> String {
        let count = pick.picked.count
        if count > 0 { return "Download \(count) Video\(count == 1 ? "" : "s")" }
        if !pick.skipped.isEmpty { return "Skip \(pick.skipped.count)" }
        return "Download"
    }
}

/// One new video: YouTube's thumbnail, its title, creator and date. Picked ones have an accent ring and a check;
/// skipped ones are grayed out. Once downloading, its progress.
private struct PendingTile: View {
    @Environment(AppModel.self) private var model
    let video: PendingVideo
    let pick: LongPick
    @State private var hovering = false

    var body: some View {
        let picked = pick.isPicked(video.id), skipped = pick.skipped.contains(video.id)
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    AsyncImage(url: video.thumbnail) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                }
                .clipShape(shape)
                .overlay {
                    if pick.started {
                        stateBadge
                    } else if skipped {
                        Label("Skip · mark watched", systemImage: "eye.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.7), in: Capsule())
                    }
                }
                .overlay {
                    if picked && !pick.started { shape.strokeBorder(Color.accentColor, lineWidth: 3) }
                }
                .overlay(alignment: .topTrailing) {
                    if !pick.started && !skipped {
                        Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, picked ? Color.accentColor : .black.opacity(0.35))
                            .shadow(radius: 2)
                            .padding(8)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if !pick.started && (hovering || skipped) {
                        Button { model.longPick?.toggleSkip(video.id) } label: {
                            Label(skipped ? "Don't Skip" : "Skip", systemImage: skipped ? "eye" : "eye.slash")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.black.opacity(0.65))
                        .controlSize(.small)
                        .padding(8)
                        .help(skipped ? "Download it after all" : "Don't download this one: mark it watched instead")
                    }
                }
            Text(video.title ?? video.id)
                .font(.callout.weight(.medium))
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                Text(byline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !skipped { resolution }
            }
            if pick.kind == .suggested { destination }
        }
        .saturation(skipped ? 0 : 1)
        .opacity(skipped ? 0.45 : !picked && !pick.started ? 0.75 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !pick.started { model.longPick?.toggle(video.id) } }
        .onHover { hovering = $0 }
        .help(pick.started ? "" : skipped ? "Skipped: marked watched and never downloaded. Click to download it instead"
              : picked ? "Click to leave this one for a later download" : "Click to download it")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// The creator's resolution for long videos (nil: Best).
    private var creatorHeight: Int? {
        model.config.creators.first { $0.id == video.creatorID }?.longFormHeight
    }

    /// While picking, a menu of the resolution this video downloads at: its creator's to begin with, tinted once
    /// changed. Once downloading, just the resolution, if it was changed.
    @ViewBuilder private var resolution: some View {
        let height = pick.height(video.id, creatorHeight: creatorHeight)
        let changed = height != creatorHeight
        let title = height.map { "\($0)p" } ?? "Best"
        if !pick.started {
            Menu {
                Picker("Resolution", selection: Binding(
                    get: { height },
                    set: { model.longPick?.setHeight($0, for: video.id, creatorHeight: creatorHeight) })) {
                    ForEach([nil] + Creator.longFormHeights.map { Optional($0) }, id: \.self) { option in
                        Text((option.map { "Up to \($0)p" } ?? "Best")
                             + (option == creatorHeight ? " (creator's)" : "")).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .tint(changed ? .accentColor : nil)
            .controlSize(.mini)
            .fixedSize()
            .help(changed ? "This video downloads at \(height.map { "up to \($0)p" } ?? "the best resolution") instead of its creator's \(creatorHeight.map { "\($0)p" } ?? "Best")"
                  : "The resolution this video downloads at. Pick another for just this video")
            .accessibilityLabel("Resolution")
            .accessibilityValue(title)
        } else if changed {
            Text(title)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var byline: String {
        let name = video.channel ?? model.library(for: video.creatorID, form: .long)?.displayName ?? video.creatorID
        let parts = [name, video.date.map { timeAgo($0) }, video.duration.map { formatLength(TimeInterval($0)) }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Suggested videos: where it goes, its followed creator's long videos or the Suggestions playlist.
    private var destination: some View {
        let following = video.creatorID != Creator.suggestions.id
        let name = following ? model.library(for: video.creatorID, form: .long)?.displayName ?? video.channel ?? "" : "Suggestions"
        return Label(following ? "Following · \(name)" : "Suggestions playlist",
                     systemImage: following ? "person.crop.circle.badge.checkmark" : "sparkles")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(following ? Color.accentColor : .secondary)
            .lineLimit(1)
            .help(following ? "You follow this channel, so it downloads with \(name)'s long videos"
                            : "Downloads to the Suggestions playlist in the long-video sidebar")
    }

    @ViewBuilder private var stateBadge: some View {
        switch pick.states[video.id] ?? .queued {
        case .queued:
            ZStack {
                Rectangle().fill(.black.opacity(0.45))
                Image(systemName: "clock").font(.title).foregroundStyle(.white)
            }
        case .downloading:
            ZStack {
                Rectangle().fill(.black.opacity(0.45))
                ProgressView().controlSize(.large).tint(.white)
            }
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .green)
                .shadow(radius: 3)
        case .failed:
            ZStack {
                Rectangle().fill(.black.opacity(0.55))
                Label("Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}
