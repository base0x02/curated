import AppKit
import SwiftUI

struct ManageView: View {
    @Environment(AppModel.self) private var model
    @State private var newUsername = ""
    /// Picked by clicking an icon, for a bare username. A pasted link picks its own platform instead.
    @State private var chosenPlatform: Platform?
    /// nil: the default, whatever the last creator added was given (`lastKeep`).
    @State private var newKeep: KeepRule?
    /// The rest of the last creator's keep rule, beside `settings.defaultDays`: its video count (0 for none) and
    /// whether it fetched older videos.
    @AppStorage("newCreatorKeepVideos") private var lastKeepVideos = 0
    @AppStorage("newCreatorKeepHistorical") private var lastKeepHistorical = false
    @State private var newCategory: UUID?
    /// For a new YouTube creator: Shorts, long videos or both. Starts with whichever sidebar is showing.
    @State private var newShorts = true
    @State private var newLongForm = false
    /// For a new playlist: how many of its newest videos to download (nil: all).
    @State private var newPlaylistLimit: Int?
    @State private var addError: String?
    @State private var search = ""
    @State private var removing: CreatorLibrary?
    @State private var filter = CreatorFilter.all
    /// Only creators with long videos turned on (combined with the category filter).
    @State private var longOnly = false
    @AppStorage("creatorSort") private var sort = CreatorSort.oldestAdded
    @AppStorage("groupCreatorsByCategory") private var grouped = false

    /// Creators in the chosen category whose name or handle contains the search text, in the chosen order.
    private var shownLibraries: [CreatorLibrary] {
        var libraries = model.libraries
        switch filter {
        case .all: break
        case .uncategorized: libraries = model.uncategorizedLibraries
        case .playlists: libraries = model.playlistManageLibraries
        case .category(let id): if model.category(id) != nil { libraries = model.libraries(in: id) }
        }
        if longOnly { libraries = libraries.filter(\.creator.downloadsLongForm) }
        let query = search.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        if !query.isEmpty {
            libraries = libraries.filter {
                $0.displayName.localizedStandardContains(query) || $0.creator.username.localizedStandardContains(query)
            }
        }
        return sorted(libraries)
    }

    /// The shown creators split by category, in the category bar's order; empty groups are left out.
    private var groups: [(title: String, symbol: String, libraries: [CreatorLibrary])] {
        let shown = shownLibraries
        var groups = model.categories.map { category in
            (title: category.name, symbol: category.symbol, libraries: shown.filter { $0.creator.category == category.id })
        }
        groups.append((title: "No Category", symbol: "tray",
                       libraries: shown.filter { model.category($0.creator.category) == nil && !$0.creator.playlist }))
        // Playlists are always their own group, last.
        groups.append((title: "Playlists", symbol: "list.bullet.rectangle", libraries: shown.filter(\.creator.playlist)))
        return groups.filter { !$0.libraries.isEmpty }
    }

    private func sorted(_ libraries: [CreatorLibrary]) -> [CreatorLibrary] {
        switch sort {
        case .oldestAdded: return libraries
        case .newestAdded: return libraries.reversed()
        case .name: return libraries.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        case .platform:
            // TikTok, then YouTube; each in the order they were added.
            func rank(_ library: CreatorLibrary) -> Int { Platform.allCases.firstIndex(of: library.creator.platform) ?? 0 }
            return libraries.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map(\.element)
        case .unplayed:
            // Stable, so ties keep the order they were added in.
            return libraries.enumerated()
                .sorted { (-model.unplayedCount($0.element), $0.offset) < (-model.unplayedCount($1.element), $1.offset) }
                .map(\.element)
        case .lastChecked:
            func checked(_ library: CreatorLibrary) -> Date { model.runState.creators[library.id]?.date ?? .distantPast }
            return libraries.enumerated()
                .sorted { checked($0.element) != checked($1.element) ? checked($0.element) > checked($1.element) : $0.offset < $1.offset }
                .map(\.element)
        }
    }

    /// Vine's row heads the list while it's turned on, unless a filter or search leaves it out.
    private var showsVine: Bool {
        guard model.settings.vineEnabled, filter == .all, !longOnly else { return false }
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || "Vine".localizedStandardContains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            addBar
            CategoryBar(filter: $filter, longOnly: $longOnly)
            Divider()
            if model.config.creators.isEmpty && !showsVine {
                ContentUnavailableView {
                    Label("No creators yet", systemImage: "person.2")
                } description: {
                    Text("Add the creators you actually want to watch. Curated downloads their recent videos so you can skip the feed.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shownLibraries.isEmpty && !search.isEmpty && !showsVine {
                // Fills the list's space, so the bars above stay at the top.
                ContentUnavailableView.search(text: search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shownLibraries.isEmpty && longOnly {
                ContentUnavailableView("No long-video creators here", systemImage: "rectangle.stack",
                                       description: Text("Light up the wide video icon on a YouTube creator to download their long videos."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shownLibraries.isEmpty && !showsVine {
                ContentUnavailableView("No creators here", systemImage: "person.2",
                                       description: Text("Set a creator's category with the menu on their row."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if grouped {
                // A section per category, in the category bar's order, then the uncategorized ones.
                List {
                    if showsVine {
                        Section {
                            VineManageRow()
                        } header: {
                            Label { Text("Vine") } icon: { VineLogo(size: 20) }
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 4)
                        }
                    }
                    ForEach(groups, id: \.title) { group in
                        Section {
                            ForEach(group.libraries) { lib in
                                CreatorManageRow(library: lib) { removing = lib }
                            }
                        } header: {
                            Label(group.title, systemImage: group.symbol)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                List {
                    if showsVine { VineManageRow() }
                    ForEach(shownLibraries) { lib in
                        CreatorManageRow(library: lib) { removing = lib }
                    }
                }
            }
            Divider()
            downloadBar
        }
        .navigationTitle("Creators & Downloads")
        .onAppear {
            resetForms()
            #if DEBUG
            // CURATED_TEST_PICK_LONG=1 opens the long-video picker, for tests.
            if ProcessInfo.processInfo.environment["CURATED_TEST_PICK_LONG"] != nil { model.pickLongDownload() }
            // CURATED_TEST_PICK_SUGGESTED=1 opens the suggestions picker (CURATED_TEST_SUGGESTIONS fakes the feed).
            if ProcessInfo.processInfo.environment["CURATED_TEST_PICK_SUGGESTED"] != nil { model.pickSuggested() }
            #endif
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search creators")
        // One dialog for the whole list rather than one per row, which redraw constantly while downloading.
        .confirmationDialog("Remove \(removing?.displayName ?? "")?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { lib in
            Button("Remove and Delete Videos", role: .destructive) { remove(lib, deleteFiles: true) }
            Button("Remove, Keep Videos on Disk") { remove(lib, deleteFiles: false) }
        } message: { _ in
            Text("They won't be downloaded anymore.")
        }
        .toolbar {
            ToolbarItem {
                Picker(selection: $sort) {
                    ForEach(CreatorSort.allCases) { Text($0.label).tag($0) }
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
                .pickerStyle(.menu)
                .help("Sort creators")
            }
        }
    }

    /// TikTok or YouTube from a pasted link; nil for a bare username.
    private var detectedPlatform: Platform? {
        let text = newUsername
        if text.range(of: #"(youtube\.com|youtu\.be)/"#, options: [.regularExpression, .caseInsensitive]) != nil { return .youtube }
        if text.range(of: #"tiktok\.com/"#, options: [.regularExpression, .caseInsensitive]) != nil { return .tiktok }
        return nil
    }

    private var platform: Platform? { detectedPlatform ?? chosenPlatform }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Gray until a link says which platform, or one is clicked for a bare username.
                HStack(spacing: 2) {
                    ForEach(Platform.addable) { option in
                        Button {
                            chosenPlatform = chosenPlatform == option ? nil : option
                        } label: {
                            PlatformIcon(platform: option, size: 18)
                                .frame(width: 32, height: 32)
                                .saturation(platform == option ? 1 : 0)
                                .opacity(platform == option ? 1 : 0.4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(detectedPlatform != nil)
                        .help(detectedPlatform != nil ? "Picked from the link"
                              : "\(option == .tiktok ? "TikTok" : "YouTube"): pick this for a username (a pasted link picks its own)")
                    }
                }
                if platform == .youtube && !isPlaylist {
                    VideoFormToggles(shorts: $newShorts, longForm: $newLongForm)
                }
                TextField("@username, a TikTok or YouTube link, or a YouTube playlist link", text: $newUsername)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.secondary.opacity(0.3)))
                    .onSubmit { if canAdd { add() } }
                if isPlaylist {
                    PlaylistLimitPicker(selection: $newPlaylistLimit)
                } else {
                    KeepButton(rule: Binding(get: { newKeep ?? lastKeep },
                                             set: { newKeep = $0 }),
                               shorts: platform != .youtube || newShorts,
                               longForm: platform == .youtube && newLongForm)
                }
                if !model.categories.isEmpty && !isPlaylist {
                    CategoryButton(selection: $newCategory)
                }
                Button(isPlaylist ? "Add Playlist" : "Add Creator", action: add)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            if let addError {
                Text(addError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    /// A pasted YouTube playlist link: added as a playlist (long videos, the whole list, the Playlists group).
    private var isPlaylist: Bool { Creator.playlistID(in: newUsername) != nil }

    private var canAdd: Bool { !newUsername.trimmingCharacters(in: .whitespaces).isEmpty && platform != nil }

    /// Sections for Short, Long, Suggested, Vine (while it's turned on) and Total, each headed by its mark and name, when it last
    /// downloaded, its numbers and a download button whose arrow pulses while that download runs.
    private var downloadBar: some View {
        let short = model.libraries.flatMap(\.videos), long = model.longLibraries.flatMap(\.videos)
        let suggested = model.library(for: Creator.suggestions.id, form: .long)?.videos ?? []
        // A download from the suggestions picker is a long one, but its own button pulses for it.
        let suggesting = model.longPick?.kind == .suggested
        let vine = model.settings.vineEnabled
        let vines = model.vineLibraries.flatMap(\.videos)
        let run = model.runState
        // Builds from before the per-form times fall back on the last download of any kind.
        return TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 0) {
                downloadSection("Short", mark: FormMark(name: "short", height: 24), videos: short, forms: [.short],
                                last: run.lastShortRun ?? run.lastRun, now: context.date,
                                help: "Download only short videos: TikTok, and YouTube Shorts",
                                disabled: !model.config.creators.contains(where: \.downloadsShorts),
                                action: model.downloadShortForm)
                Divider().frame(height: 44)
                downloadSection("Long", mark: FormMark(name: "long", height: 24), videos: long, forms: [.long],
                                running: suggesting ? false : nil, last: run.lastLongRun ?? run.lastRun, now: context.date,
                                help: "Pick which new long videos to download: YouTube creators with them turned on, and playlists",
                                disabled: !model.config.creators.contains(where: \.downloadsLongForm),
                                action: { model.pickLongDownload() })
                Divider().frame(height: 44)
                downloadSection("Suggested", mark: FormMark(name: "suggested", height: 24), videos: suggested, forms: [.long],
                                running: suggesting && model.isDownloading,
                                last: run.creators[Creator.suggestions.id]?.date, now: context.date,
                                help: "Pick from the long videos suggested on your YouTube home feed (signed in through "
                                    + "\(model.settings.youtubeCookieBrowser == .none ? "the browser picked in Settings" : model.settings.youtubeCookieBrowser.label))",
                                disabled: false, action: model.pickSuggested)
                Divider().frame(height: 44)
                if vine {
                    downloadSection("Vine", mark: FormMark(name: "vine", height: 24), videos: vines, forms: [], vine: true,
                                    last: run.creators[Vine.feedID]?.date, now: context.date,
                                    help: "Top Vine back up to \(model.settings.vineBatchSize) unwatched",
                                    disabled: false, action: model.downloadVine)
                    Divider().frame(height: 44)
                }
                downloadSection("Total", mark: FormMark(name: "all", height: 24), videos: short + long + vines,
                                forms: Set(VideoForm.allCases), vine: vine,
                                help: vine ? "Download everything: short and long videos, and Vines"
                                           : "Download everything: short and long videos",
                                disabled: model.config.creators.isEmpty && !vine,
                                action: model.downloadAll)
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
        }
    }

    /// One of the bar's sections: its mark and name with how long ago it last downloaded ("32m ago"), "120 videos · 45
    /// unwatched", "3h 10m · 2.1 GB", and a download button, Apple's download arrow, which pulses while a download of
    /// `forms` (and Vine, with `vine`) runs.
    private func downloadSection(_ title: String, mark: some View, videos: [Video], forms: Set<VideoForm>,
                                 vine: Bool = false, running: Bool? = nil, last: Date? = nil, now: Date = Date(), help: String, disabled: Bool,
                                 action: @escaping () -> Void) -> some View {
        let running = running ?? (model.isDownloading && model.downloadingForms == forms && model.downloadingVine == vine)
        let unwatched = videos.count { !model.isPlayed($0) }
        let size = videos.reduce(Int64(0)) { $0 + $1.size }
        return HStack(spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(title).font(.callout.weight(.semibold))
                    if let last {
                        Text(timeAgo(last, now: now)).font(.callout).foregroundStyle(.secondary)
                            .help("Last downloaded \(last.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                Group {
                    if videos.isEmpty {
                        Text("No videos")
                    } else {
                        Text("\(videos.count) video\(videos.count == 1 ? "" : "s") · \(unwatched) unwatched")
                        Text("\(formatLength(model.totalDuration(videos))) · \(size.formatted(.byteCount(style: .file)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Button(action: action) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .symbolEffect(.pulse, options: .repeating, isActive: running)
                    .foregroundStyle(running ? Color.accentColor : Color.primary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // The running one stays enabled so its animation isn't dimmed; a second download can't start anyway.
            .disabled(disabled || (model.isDownloading && !running))
            .help(running ? (forms == [.long] && model.longPick != nil ? "Downloading… Click to see the videos" : "Downloading…")
                  : model.longPick?.shown == false ? "Another pick is downloading" : help)
            .accessibilityLabel("Download \(title == "Total" ? "everything" : title.lowercased() + " videos")")
        }
        .padding(.horizontal, 18)
    }


    /// A search that only matched the removed creator goes back to the full list.
    private func remove(_ library: CreatorLibrary, deleteFiles: Bool) {
        model.removeCreator(library.id, deleteFiles: deleteFiles)
        if !search.isEmpty && shownLibraries.isEmpty { search = "" }
    }

    /// What a new creator starts with: the keep rule the last one was added with.
    private var lastKeep: KeepRule {
        KeepRule(days: model.settings.defaultDays, videos: lastKeepVideos > 0 ? lastKeepVideos : nil,
                 historical: lastKeepHistorical)
    }

    private func add() {
        guard let platform else { return }
        let keep = newKeep ?? lastKeep
        addError = model.addCreator(newUsername, platform: platform,
                                    keep: keep,
                                    category: model.category(newCategory)?.id,
                                    shorts: newShorts, longForm: newLongForm, playlistLimit: newPlaylistLimit)
        // Back to a blank form: no text, gray icons, Add Creator disabled.
        if addError == nil {
            // The next creator starts the same way (playlists have no keep rule).
            if !isPlaylist {
                model.settings.defaultDays = max(1, keep.days)
                lastKeepVideos = keep.videos ?? 0
                lastKeepHistorical = keep.historical
            }
            newUsername = ""
            chosenPlatform = nil
            newKeep = nil
            newCategory = nil
            newPlaylistLimit = nil
            resetForms()
        }
    }

    private func resetForms() {
        newShorts = model.form == .short
        newLongForm = model.form == .long
    }
}

/// Which creators Creators & Downloads lists, picked from the category bar.
enum CreatorFilter: Hashable {
    case all, uncategorized, playlists
    case category(UUID)
}

enum CreatorSort: String, CaseIterable, Identifiable {
    case oldestAdded, newestAdded, name, platform, unplayed, lastChecked
    var id: String { rawValue }
    var label: String {
        switch self {
        case .oldestAdded: "Oldest Added"
        case .newestAdded: "Newest Added"
        case .name: "Name"
        case .unplayed: "Most Unwatched"
        case .platform: "Platform"
        case .lastChecked: "Recently Checked"
        }
    }
}

struct CreatorManageRow: View {
    @Environment(AppModel.self) private var model
    let library: CreatorLibrary
    /// Asks the list to confirm removing this creator.
    let onRemove: () -> Void

    private var creator: Creator { library.creator }
    private var id: String { library.id }

    var body: some View {
        HStack(spacing: 12) {
            Group {	
                if creator.playlist {
                    FormMark(name: "all", height: 16).help("YouTube playlist")
                } else {
                    PlatformIcon(platform: creator.platform)
                }
            }
            .frame(width: 26)
            AvatarView(library: library, size: 40)
            // Two columns: the name over the @handle, then the counts over when it was last checked. The name column
            // is the same width on every row, so the second one lines up; both cut long text short with "…".
            VStack(alignment: .leading, spacing: 2) {
                Text(library.displayName).font(.headline).lineLimit(1)
                // Channels added by "UC…" ID have no handle worth showing.
                if library.nickname != nil, !creator.playlist,
                   !(creator.platform == .youtube && creator.username.hasPrefix("UC")) {
                    Text("@\(creator.username)").foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 150, alignment: .leading)
            .help(library.displayName)
            Divider().frame(height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(countsText)
                if let waitingText { Text(waitingText).foregroundStyle(.secondary) }
                checkedText
                // Cut short with "…" like the other lines; hovering shows all of it.
                if let errorText, let error = model.runState.creators[id]?.error { errorText.help(error) }
            }
            .font(.caption)
            .lineLimit(1)
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            // Same width on every row, so the controls after it line up between TikTok and YouTube creators.
            Divider().frame(height: 24)
            ZStack {
                Color.clear
                if creator.platform == .youtube && !creator.playlist {
                    VideoFormToggles(
                        shorts: Binding(get: { creator.shorts },
                                        set: { model.setForms(shorts: $0, longForm: creator.longForm, for: id) }),
                        longForm: Binding(get: { creator.longForm },
                                          set: { model.setForms(shorts: creator.shorts, longForm: $0, for: id) }))
                }
            }
            .frame(width: VideoFormToggles.width, height: 32)
            // A slot on every row, so the controls after it line up whether or not it's shown. (The clear fill keeps
            // an empty slot its width; an empty Group would take none.)
            ZStack(alignment: .leading) {
                Color.clear
                if creator.downloadsLongForm {
                    ResolutionPicker(selection: Binding(get: { creator.longFormHeight },
                                                        set: { model.setLongFormHeight($0, for: id) }))
                }
            }
            .frame(width: ResolutionPicker.width, height: 32)
            .padding(.trailing, 8)
            // A playlist has no day window: a menu of how many of its newest videos to download takes this place.
            Group {
                if creator.playlist {
                    PlaylistLimitPicker(selection: Binding(get: { creator.playlistLimit },
                                                           set: { model.setPlaylistLimit($0, for: id) }))
                } else {
                    KeepButton(rule: Binding(get: { KeepRule(creator) }, set: { model.setKeep($0, for: id) }),
                               shorts: creator.downloadsShorts, longForm: creator.downloadsLongForm)
                }
            }
            .frame(width: creator.playlist ? nil : KeepButton.width, alignment: .trailing)
            MinViewsPicker(selection: Binding(get: { library.creator.minViews }, set: { model.setMinViews($0, for: id) }))
            if !model.categories.isEmpty {
                if creator.playlist {
                    // Playlists are always in Playlists.
                    CategoryGlyph(symbol: "list.bullet.rectangle", dimmed: true)
                        .help("Playlists are always in Playlists")
                } else {
                    CategoryButton(selection: Binding(get: { model.category(library.creator.category)?.id },
                                                      set: { model.setCategory($0, for: id) }))
                }
            }
            Group {
                switch model.statuses[id] ?? .idle {
                case .downloading: ProgressView().controlSize(.small)
                case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
                case .idle:
                    // Long videos only (and playlists): pick which, as the download bar's Long does.
                    Button {
                        if creator.downloadsShorts { model.download([creator]) } else { model.pickLongDownload([creator]) }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: RowControl.iconSize))
                            .frame(width: RowControl.height, height: RowControl.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isDownloading)
                    .help("Download now")
                }
            }
            .frame(width: RowControl.height)
            Menu {
                Button("Show in Finder") {
                    NSWorkspace.shared.open(Library.folder(for: id, settings: model.settings))
                }
                if creator.downloadsLongForm && !creator.playlist {
                    Button("Show Long Videos in Finder") {
                        NSWorkspace.shared.open(Library.folder(for: creator, form: .long, settings: model.settings))
                    }
                }
                Button("Open on \(creator.platform.name)") {
                    NSWorkspace.shared.open(creator.profileURL)
                }
                if creator.canPickOlderLong {
                    Divider()
                    Button("Older Long Videos…") { model.pickOlderLong(creator) }
                        .disabled(model.isDownloading)
                }
                Divider()
                MarkAllMenuItems(library: creator.playlist ? model.library(for: id, form: .long) ?? library : library)
                if creator.keepsByCount, let extra = model.trimmableVideos([creator])[id]?.count {
                    Divider()
                    Button("Trim to \(KeepButton.videos(creator.keepVideos ?? 0)) Unwatched (\(extra) to Trash)…") {
                        confirmTrim(model, creators: [creator])
                    }
                }
                Divider()
                Button("Remove…", role: .destructive, action: onRemove)
            } label: {
                // The same size as the download button beside it. A plain button style, as a menu's own style
                // draws its icon at a fixed small size.
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: RowControl.iconSize))
                    .frame(width: RowControl.height, height: RowControl.height)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    /// "3 unwatched of 12", with a "long: …" part when long videos are on ("2 unwatched of 5" for a playlist).
    private var countsText: String {
        var counts: [String] = []
        if creator.downloadsShorts { counts.append("\(model.unplayedCount(library)) unwatched of \(library.videos.count)") }
        if creator.downloadsLongForm, let long = model.library(for: id, form: .long) {
            counts.append(creator.playlist ? "\(model.unplayedCount(long)) unwatched of \(long.videos.count)"
                          : "long: \(model.unplayedCount(long)) unwatched of \(long.videos.count)")
        }
        return counts.joined(separator: " · ")
    }

    /// "12 under 500K views", when the last check left some for having too few.
    private var waitingText: String? {
        guard let minViews = creator.minViews, let waiting = model.runState.creators[id]?.belowMinViews, waiting > 0
        else { return nil }
        return "\(waiting) under \(compactViews(minViews)) views"
    }

    /// "checked 13 hours ago, 0 new".
    private var checkedText: Text {
        guard let info = model.runState.creators[id] else { return Text("never downloaded").foregroundColor(.secondary) }
        return Text("checked \(info.date.formatted(.relative(presentation: .named))), \(info.newVideos) new")
            .foregroundColor(.secondary)
    }

    /// The last check's error: orange if some videos still came down, red if none did.
    private var errorText: Text? {
        guard let info = model.runState.creators[id], let error = info.error else { return nil }
        return Text(error).foregroundColor(info.newVideos > 0 ? .orange : .red)
    }
}

/// Vine's entry in the creator list, laid out like a creator's row. Its one setting is how many Vines each download
/// fetches; the authors come with whichever Vines those are.
struct VineManageRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let all = Vine.mixLibrary(model.vineLibraries)
        HStack(spacing: 12) {
            VineLogo(size: 18).frame(width: 26)
            // Round, where a creator's avatar would be.
            VineLogo(size: 40).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Vine").font(.headline)
                Text("Classics").foregroundStyle(.secondary)
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.unplayedCount(all)) unwatched of \(all.videos.count)"
                     + " · \(model.vineLibraries.count) creator\(model.vineLibraries.count == 1 ? "" : "s")")
                checkedText
            }
            .font(.caption)
            .lineLimit(1)
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            .help(model.runState.creators[Vine.feedID]?.error ?? "")
            Picker("Unwatched Vines to keep", selection: Binding(get: { model.settings.vineBatchSize },
                                                             set: { model.setVineBatchSize($0) })) {
                // Also lists a value set some other way (e.g. by editing config.json), so it never shows blank.
                ForEach(Set(Vine.batchSizes + [model.settings.vineBatchSize]).sorted(), id: \.self) {
                    Text("Keep \($0) unwatched").tag($0)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("How many unwatched Vines to keep. Each download fetches just enough new classics to get back to it")
            Group {
                switch model.statuses[Vine.feedID] ?? .idle {
                case .downloading: ProgressView().controlSize(.small)
                case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
                case .idle:
                    Button(action: model.downloadVine) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: RowControl.iconSize))
                            .frame(width: RowControl.height, height: RowControl.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isDownloading)
                    .help("Top up to \(model.settings.vineBatchSize) unwatched now")
                }
            }
            .frame(width: RowControl.height)
            Menu {
                Button("Open divine.video") { NSWorkspace.shared.open(Vine.classicsURL) }
                Divider()
                MarkAllMenuItems(library: all)
                if let extra = model.trimmableVideos([], vine: true)[Vine.feedID]?.count {
                    Divider()
                    Button("Trim to \(model.settings.vineBatchSize) Unwatched (\(extra) to Trash)…") {
                        confirmTrim(model, creators: [], vine: true)
                    }
                }
                Divider()
                Button("Turn Off Vine") { model.settings.vineEnabled = false }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: RowControl.iconSize))
                    .frame(width: RowControl.height, height: RowControl.height)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 4)
    }

    /// "checked 13 hours ago, 25 new", then any error.
    private var checkedText: Text {
        guard let info = model.runState.creators[Vine.feedID] else { return Text("never downloaded").foregroundColor(.secondary) }
        var text = Text("checked \(info.date.formatted(.relative(presentation: .named))), \(info.newVideos) new")
            .foregroundColor(.secondary)
        if let error = info.error {
            text = text + Text(" · \(error)").foregroundColor(info.newVideos > 0 ? .orange : .red)
        }
        return text
    }
}

/// The highest resolution to download a creator's long videos at, as a squircle like the views one: "Best", then
/// 1080p down to 144p. Tinted while a cap is set.
struct ResolutionPicker: View {
    @Binding var selection: Int?

    static let width: CGFloat = 62

    var body: some View {
        StepSquircle(selection: $selection, steps: [nil] + Creator.longFormHeights.map { Optional($0) },
                     width: Self.width, title: { $0.map { "\($0)p" } ?? "Best" },
                     menuTitle: { $0.map { "Up to \($0)p" } ?? "Best (the highest H.264, usually 1080p)" })
            .help((selection.map { "Long videos at up to \($0)p. " } ?? "Long videos at the best resolution. ")
                  + "Click for lower, Option-click for higher; right-click to pick one. Videos already downloaded stay as they are.")
            .accessibilityLabel("Long video resolution")
    }
}

/// How many of a playlist's videos to download: all of them, or only the newest few.
struct PlaylistLimitPicker: View {
    @Binding var selection: Int?

    var body: some View {
        Picker("Videos", selection: $selection) {
            Text("All videos").tag(Int?.none)
            Divider()
            // Also lists a value set some other way (e.g. by editing config.json), so it never shows blank.
            ForEach(Set(Creator.playlistLimits + [selection].compactMap { $0 }).sorted(), id: \.self) {
                Text("Newest \($0)").tag(Int?.some($0))
            }
        }
        .labelsHidden()
        .fixedSize()
        .help("Download every video in the playlist, or only its newest ones (by upload date, whatever order the playlist is in). Videos already downloaded stay.")
    }
}

/// A creator's minimum view count for downloading.
/// A squircle showing "All" or e.g. "500K+". Each click steps to the next minimum (All, 5K+, 10K+ … 1M+, then All
/// again), Option-click to the one before; right-click picks one directly. Tinted while a minimum is set.
struct MinViewsPicker: View {
    @Binding var selection: Int?

    static let presets = [5_000, 10_000, 20_000, 35_000, 50_000, 75_000, 100_000, 200_000, 500_000, 1_000_000]
    static let width: CGFloat = 58

    /// All, then each minimum from lowest to highest (including one set some other way).
    private var steps: [Int?] { [nil] + Set(Self.presets + [selection].compactMap { $0 }).sorted().map { Optional($0) } }

    var body: some View {
        StepSquircle(selection: $selection, steps: steps, width: Self.width,
                     title: { $0.map { "\(compactViews($0))+" } ?? "All" },
                     menuTitle: { $0.map { "\(compactViews($0))+ views" } ?? "All videos" })
            .help((selection != nil ? "Only videos with at least \(compactViews(selection ?? 0)) views. " : "Every video, any views. ")
                  + "Click for a higher minimum, Option-click for a lower one; right-click to pick one. Videos under it are checked again on every download.")
            .accessibilityLabel("Minimum views")
            .accessibilityValue(selection.map { "\(compactViews($0)) or more" } ?? "All")
    }
}

/// A rounded square showing one of `steps`. A click moves to the next (wrapping around), an Option-click to the one
/// before; right-click lists them all. Tinted while it's on anything but the first.
struct StepSquircle<Value: Hashable>: View {
    @Binding var selection: Value
    let steps: [Value]
    let width: CGFloat
    let title: (Value) -> String
    let menuTitle: (Value) -> String

    var body: some View {
        let on = selection != steps.first
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button {
            let i = steps.firstIndex(of: selection) ?? 0
            let back = NSEvent.modifierFlags.contains(.option)
            selection = steps[(i + (back ? steps.count - 1 : 1)) % steps.count]
        } label: {
            Text(title(selection))
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(width: width, height: RowControl.height)
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: shape)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .contextMenu {
            ForEach(steps, id: \.self) { step in
                Button(menuTitle(step)) { selection = step }
            }
        }
    }
}

/// "Keep" over "3 days" or "5 videos", which opens a small popover to choose between keeping the last few days of
/// videos and keeping a number of unwatched ones (with or without older, historical videos).
struct KeepButton: View {
    @Binding var rule: KeepRule
    /// Whether the creator has short videos, which are the only ones that can be kept by count.
    var shorts = true
    /// Whether the creator has long videos, which always use the day window.
    var longForm = false
    @State private var showing = false
    @State private var hovering = false

    /// The same on every row, so the controls beside it stay lined up. Fits "365".
    static let width: CGFloat = 70

    static let daysSymbol = "square.and.arrow.down.badge.clock"
    static let videosSymbol = "square.and.arrow.down.on.square"

    private var byCount: Bool { rule.videos != nil && shorts }

    /// A squircle like the views and resolution ones: the mode's symbol with its number beside it. The symbol is in
    /// the accent color while Historical is on.
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button { showing = true } label: {
            HStack(spacing: 5) {
                Image(systemName: byCount ? Self.videosSymbol : Self.daysSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(byCount && rule.historical ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                    .frame(width: 22)
                Text("\(byCount ? rule.videos ?? 0 : rule.days)")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: Self.width, height: RowControl.height)
            .background(hovering || showing ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            KeepOptions(rule: $rule, shorts: shorts, longForm: longForm)
        }
        .accessibilityLabel("Keep")
        .accessibilityValue(byCount ? Self.videos(rule.videos ?? 0) : Self.days(rule.days))
        .help(byCount ? "Keeps \(Self.videos(rule.videos ?? 0)) unwatched\(rule.historical ? ", older ones too" : ""). Click to change"
                      : "Downloads videos from the last \(Self.days(rule.days)). Click to change")
    }

    static func days(_ n: Int) -> String { "\(n) day\(n == 1 ? "" : "s")" }
    static func videos(_ n: Int) -> String { "\(n) video\(n == 1 ? "" : "s")" }
}

/// The Keep popover: two choices, each with its number, and the Historical checkbox for keeping by count.
private struct KeepOptions: View {
    @Binding var rule: KeepRule
    let shorts: Bool
    let longForm: Bool
    /// The count to go back to when switching from days to videos.
    @State private var lastCount = 5

    private var byCount: Bool { rule.videos != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep").font(.headline)
            choice(selected: !byCount, select: { rule.videos = nil }) {
                Image(systemName: KeepButton.daysSymbol).frame(width: 22)
                Text("Videos from the last")
                stepper(Binding(get: { rule.days }, set: { rule.days = $0 }), in: 1...365, label: KeepButton.days)
                    .disabled(byCount)
            }
            VStack(alignment: .leading, spacing: 6) {
                choice(selected: byCount, select: { rule.videos = lastCount }) {
                    Image(systemName: KeepButton.videosSymbol).frame(width: 22)
                    Text("The newest")
                    stepper(Binding(get: { rule.videos ?? lastCount }, set: { rule.videos = $0; lastCount = $0 }),
                            in: 1...100, label: { "\($0) unwatched" })
                        .disabled(!byCount)
                }
                Toggle(isOn: Binding(get: { rule.historical }, set: { rule.historical = $0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Historical")
                        Text("When there aren't enough new videos, also download older ones not yet downloaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!byCount)
                .padding(.leading, 26)
            }
            .disabled(!shorts)
            if let footnote {
                Divider()
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if byCount && longForm {
                Divider()
                HStack {
                    Text("Long videos from the last")
                    stepper(Binding(get: { rule.days }, set: { rule.days = $0 }), in: 1...365, label: KeepButton.days)
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .onAppear { if let videos = rule.videos { lastCount = videos } }
    }

    private var footnote: String? {
        if !shorts { return "Keeping a number of videos is for short videos. Long videos are kept until you watch or delete them." }
        if byCount { return nil }
        return longForm ? "How far back to look for new videos. Long videos are kept until you watch or delete them."
                        : "How far back to look for new videos."
    }

    /// A radio button with its row; clicking anywhere on the row's text picks it.
    private func choice(selected: Bool, select: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Button(action: select) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(width: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            content()
        }
    }

    private func stepper(_ value: Binding<Int>, in range: ClosedRange<Int>, label: @escaping (Int) -> String) -> some View {
        HStack(spacing: 4) {
            Text(label(value.wrappedValue)).monospacedDigit().fontWeight(.semibold)
            Stepper("", value: value, in: range).labelsHidden()
        }
    }
}

/// "500K", "1.2M".
func compactViews(_ views: Int) -> String { views.formatted(.number.notation(.compactName)) }

/// The one height every button on a creator's row shares: the squircles (resolution, Keep, views), the category
/// glyph, and the download and More buttons, whose circles fill it.
enum RowControl {
    static let height: CGFloat = 30
    static let iconSize: CGFloat = 26
}

/// A creator's category as its glyph; clicking it opens a popover with every category, each with its name.
struct CategoryButton: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    @State private var showing = false

    var body: some View {
        let category = model.category(selection)
        Button { showing = true } label: {
            CategoryGlyph(symbol: category?.symbol ?? "tray", dimmed: category == nil, highlighted: showing)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            CategoryChooser(selection: Binding(get: { selection }, set: { selection = $0; showing = false }))
        }
        .help(category.map { "Category: \($0.name). Click to change" } ?? "No category. Click to pick one")
        .accessibilityLabel("Category")
        .accessibilityValue(category?.name ?? "None")
    }
}

/// A category's symbol in a rounded square, the size of the squircles beside it.
struct CategoryGlyph: View {
    let symbol: String
    var dimmed = false
    var highlighted = false

    static let size = RowControl.height

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(width: Self.size, height: Self.size)
            .background(highlighted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary), in: shape)
            .contentShape(shape)
    }
}

/// Every category as a tile (its glyph over its name), then No Category. The chosen one is filled in the accent color.
private struct CategoryChooser: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 92), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category").font(.headline)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(model.categories) { category in
                    tile(category.name, symbol: category.symbol, selected: selection == category.id) {
                        selection = category.id
                    }
                }
                tile("No Category", symbol: "tray", selected: model.category(selection) == nil) { selection = nil }
            }
        }
        .padding(16)
        // Three to a row, four once there are more than six.
        .frame(width: model.categories.count + 1 > 9 ? 424 : 324)
    }

    private func tile(_ name: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                Text(name).font(.caption.weight(.medium)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: 92, height: 68)
            .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(name)
    }
}

/// Category pills under the add bar: click one to show only its creators. On the right: group the list by category,
/// add a category, and edit (the gear), where the pills wiggle like icons on iOS; then clicking one edits or deletes
/// it, and dragging one onto another reorders them. That order is the sidebar's, and the phones'.
/// Without room for every name, the pills drop to their glyph, with the name on hover.
struct CategoryBar: View {
    @Environment(AppModel.self) private var model
    @Binding var filter: CreatorFilter
    @Binding var longOnly: Bool
    @AppStorage("groupCreatorsByCategory") private var grouped = false
    @State private var isEditing = false
    @State private var editing: CategoryDraft?
    @State private var deleting: Category?
    /// The pill whose Edit/Delete choices are showing.
    @State private var actionsFor: UUID?
    /// While editing: the pill being dragged, how far it's moved, and the slot it would drop into. The bar keeps its
    /// layout during the drag (the pills it passes just slide aside), and is reordered once when it's let go.
    @State private var dragging: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var dropIndex = 0
    /// The pills' frames when the drag started, which don't change until it ends.
    @State private var dragFrames: [UUID: CGRect] = [:]
    /// The dropped pill gliding from where it was let go into its slot.
    @State private var settling: UUID?
    @State private var settleOffset: CGFloat = 0
    @State private var pillFrames: [UUID: CGRect] = [:]
    /// Letting go of a drag also counts as a click on the pill; this tells the two apart.
    @State private var dragEnded = Date.distantPast

    var body: some View {
        HStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                pills(showNames: true)
                pills(showNames: false)
                ScrollView(.horizontal, showsIndicators: false) { pills(showNames: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Button { longOnly.toggle() } label: {
                    VideoFormGlyph(form: .long, on: longOnly, offColor: .primary)
                        .frame(width: 28, height: 28)
                        .background(longOnly ? AnyShapeStyle(Color.red.opacity(0.18)) : AnyShapeStyle(.quaternary), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(longOnly ? "Showing creators with long videos. Click to show everyone" : "Show only creators with long videos")
                iconButton("rectangle.grid.1x2", on: grouped, help: grouped ? "Show one list" : "Group by category") {
                    grouped.toggle()
                }
                iconButton("plus", on: false, help: "New Category") { editing = CategoryDraft(nil) }
                iconButton("gearshape", on: isEditing,
                           help: isEditing ? "Done" : "Edit categories: click one to edit or delete it, drag to reorder") {
                    isEditing.toggle()
                    actionsFor = nil
                }
                .disabled(model.categories.isEmpty && !isEditing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        // A deleted category, or the last uncategorized creator getting one, falls back to everyone.
        .onChange(of: model.categories) {
            if !isAvailable(filter) { filter = .all }
            if model.categories.isEmpty { isEditing = false }
        }
        .onChange(of: model.uncategorizedLibraries.count) { if !isAvailable(filter) { filter = .all } }
        .sheet(item: $editing) { draft in
            CategoryEditor(draft: draft)
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Category", role: .destructive) { if let deleting { model.deleteCategory(deleting.id) } }
        } message: {
            Text("Its creators and videos stay — they just won't be in a category.")
        }
    }

    private func pills(showNames: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(model.categories.enumerated()), id: \.element.id) { index, category in
                Group {
                    if isEditing {
                        editablePill(category, index: index, showName: showNames)
                    } else {
                        pill(title: category.name, count: model.libraries(in: category.id).count, symbol: category.symbol,
                             showName: showNames, for: .category(category.id))
                    }
                }
                // The dragged (or settling) pill passes over the others, not under them.
                .zIndex(dragging == category.id || settling == category.id ? 1 : 0)
            }
            if !model.categories.isEmpty, !model.uncategorizedLibraries.isEmpty, !isEditing {
                pill(title: "No Category", count: model.uncategorizedLibraries.count, symbol: "tray",
                     showName: showNames, for: .uncategorized)
            }
            if !model.playlistManageLibraries.isEmpty, !isEditing {
                pill(title: "Playlists", count: model.playlistManageLibraries.count, symbol: "list.bullet.rectangle",
                     showName: showNames, for: .playlists)
            }
        }
        .fixedSize()
        .coordinateSpace(name: "pills")
        .onPreferenceChange(PillFrames.self) { pillFrames = $0 }
    }

    /// With no pill chosen, everyone shows; clicking the chosen pill again goes back to that.
    private func pill(title: String, count: Int, symbol: String, showName: Bool, for pillFilter: CreatorFilter) -> some View {
        let selected = filter == pillFilter
        return Button {
            filter = selected && pillFilter != .all ? .all : pillFilter
        } label: {
            pillLabel(title: title, count: count, symbol: symbol, showName: showName, selected: selected)
        }
        .buttonStyle(.plain)
        .help(showName ? "Show only \(title)" : "\(title) (\(count))")
    }

    /// While editing: wiggles; click for Edit and Delete. Dragging it along the bar moves it where it's let go.
    private func editablePill(_ category: Category, index: Int, showName: Bool) -> some View {
        Button {
            if dragging == nil && Date().timeIntervalSince(dragEnded) > 0.3 { actionsFor = category.id }
        } label: {
            pillLabel(title: category.name, count: model.libraries(in: category.id).count, symbol: category.symbol,
                      showName: showName, selected: actionsFor == category.id || dragging == category.id)
        }
        .buttonStyle(.plain)
        // Everything holds still during a drag, so the pills don't move under the pointer.
        .modifier(Wiggle(seed: index, paused: dragging != nil))
        .scaleEffect(dragging == category.id ? 1.08 : 1)
        .shadow(color: .black.opacity(dragging == category.id ? 0.3 : 0), radius: 6, y: 2)
        .background(GeometryReader { geo in
            Color.clear.preference(key: PillFrames.self, value: [category.id: geo.frame(in: .named("pills"))])
        })
        .offset(x: offset(for: category.id))
        .animation(dragging == category.id ? nil : .snappy(duration: 0.2), value: dropIndex)
        .simultaneousGesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("pills"))
                .onChanged { value in drag(category.id, by: value.translation.width) }
                .onEnded { _ in drop(category.id) }
        )
        .popover(isPresented: Binding(get: { actionsFor == category.id }, set: { if !$0 { actionsFor = nil } }),
                 arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Button("Edit…", systemImage: "pencil") {
                    actionsFor = nil
                    editing = CategoryDraft(category)
                }
                Button("Delete…", systemImage: "trash", role: .destructive) {
                    actionsFor = nil
                    deleting = category
                }
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .help("Click to edit or delete \(category.name); drag to reorder")
    }

    private static let pillSpacing: CGFloat = 6

    /// The dragged pill follows the pointer; the ones between its old slot and the drop slot move over by its width.
    private func offset(for id: UUID) -> CGFloat {
        if id == settling { return settleOffset }
        guard let dragging, let width = dragFrames[dragging]?.width else { return 0 }
        if id == dragging { return dragTranslation }
        let ids = model.categories.map(\.id)
        guard let from = ids.firstIndex(of: dragging), let i = ids.firstIndex(of: id) else { return 0 }
        let shift = width + Self.pillSpacing
        if from < i && i <= dropIndex { return -shift }
        if dropIndex <= i && i < from { return shift }
        return 0
    }

    private func drag(_ id: UUID, by translation: CGFloat) {
        if dragging != id {
            actionsFor = nil
            settling = nil
            dragFrames = pillFrames
            dragging = id
            dropIndex = model.categories.firstIndex { $0.id == id } ?? 0
        }
        dragTranslation = translation
        guard let start = dragFrames[id] else { return }
        // The slot is decided by which pills' middles the dragged pill's middle has passed.
        let x = start.midX + translation
        let newIndex = model.categories.filter { $0.id != id && (dragFrames[$0.id]?.midX ?? 0) < x }.count
        if newIndex != dropIndex { dropIndex = newIndex }
    }

    /// Reorders the bar in one step, then lets the dropped pill glide from where it was let go into its slot.
    private func drop(_ id: UUID) {
        defer {
            dragEnded = Date()
            actionsFor = nil
        }
        guard let start = dragFrames[id] else {
            dragging = nil
            return
        }
        var order = model.categories.map(\.id)
        order.removeAll { $0 == id }
        order.insert(id, at: min(dropIndex, order.count))
        // Where the pill's slot will be: the bar's start plus the widths before it.
        let barStart = dragFrames.values.map(\.minX).min() ?? start.minX
        var slotMinX = barStart
        for other in order.prefix(while: { $0 != id }) {
            slotMinX += (dragFrames[other]?.width ?? 0) + Self.pillSpacing
        }
        let droppedAt = start.minX + dragTranslation
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            model.setCategoryOrder(order)
            dragging = nil
            dragTranslation = 0
            settling = id
            settleOffset = droppedAt - slotMinX
        }
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.2)) { settleOffset = 0 }
        }
    }

    private func pillLabel(title: String, count: Int, symbol: String, showName: Bool, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if showName {
                Text(title)
                Text("\(count)").foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, showName ? 12 : 9)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        // A plain solid blue: the accent style can render see-through here, which shows a pill being dragged over.
        .background(selected ? AnyShapeStyle(Self.solidAccent) : AnyShapeStyle(.quaternary), in: Capsule())
        .contentShape(Capsule())
    }

    private static let solidAccent = Color(nsColor: NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue)

    private func iconButton(_ symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 28, height: 28)
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func isAvailable(_ filter: CreatorFilter) -> Bool {
        switch filter {
        case .all: true
        case .uncategorized: !model.uncategorizedLibraries.isEmpty
        case .playlists: !model.playlistManageLibraries.isEmpty
        case .category(let id): model.category(id) != nil
        }
    }
}

/// Where each category pill sits, for working out where a dragged one lands.
private struct PillFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The iOS home-screen jiggle: a small rock back and forth, each pill a little out of step with its neighbors.
/// It holds still while being dragged.
private struct Wiggle: ViewModifier {
    let seed: Int
    var paused = false

    /// The tilt comes from the clock rather than a repeating animation, so pausing for a drag and picking up again
    /// can't leave a pill stuck mid-tilt.
    func body(content: Content) -> some View {
        TimelineView(.animation(paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let cyclesPerSecond = 3.6 + Double(seed % 3) * 0.25
            let angle = paused ? 0 : sin(t * 2 * .pi * cyclesPerSecond + Double(seed) * 1.7) * 1.6
            content.rotationEffect(.degrees(angle))
        }
    }
}

struct CategoryDraft: Identifiable {
    let id = UUID()
    let categoryID: UUID?
    var name: String
    var symbol: String

    init(_ category: Category?) {
        categoryID = category?.id
        name = category?.name ?? ""
        symbol = category?.symbol ?? Category.defaultSymbol
    }
}

struct CategoryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: CategoryDraft
    @State private var error: String?

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.categoryID == nil ? "New Category" : "Edit Category").font(.headline)
            HStack(spacing: 10) {
                Image(systemName: draft.symbol)
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                TextField("Name, e.g. News", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
            }
            Text("Icon").font(.subheadline).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Category.symbolChoices, id: \.self) { symbol in
                        Button {
                            draft.symbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 36)
                                .background(symbol == draft.symbol ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
            }
            .frame(height: 210)
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.categoryID == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func save() {
        error = model.saveCategory(draft.categoryID, name: draft.name, symbol: draft.symbol)
        if error == nil { dismiss() }
    }
}

/// How long ago `date` was, short: "just now", "32m ago", then rounded to the hour ("1h ago") and past a day to the
/// day ("2d ago").
func timeAgo(_ date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    if seconds < 60 { return "just now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
    let hours = Int((seconds / 3600).rounded())
    if hours < 24 { return "\(hours)h ago" }
    let days = Int((seconds / 86400).rounded())
    if days >= 365 { return "\(days / 365)y ago" }
    return "\(max(1, days))d ago"
}

/// A YouTube creator's two kinds of video: a portrait glyph for Shorts and a landscape one for long videos, lit in
/// YouTube red while turned on. At least one stays on.
struct VideoFormToggles: View {
    @Binding var shorts: Bool
    @Binding var longForm: Bool

    static let width: CGFloat = 74

    var body: some View {
        HStack(spacing: 4) {
            toggle(.short, isOn: $shorts, otherOn: longForm)
            toggle(.long, isOn: $longForm, otherOn: shorts)
        }
    }

    private func toggle(_ form: VideoForm, isOn: Binding<Bool>, otherOn: Bool) -> some View {
        let on = isOn.wrappedValue
        let name = form == .short ? "Shorts" : "Long videos"
        return Button {
            if !on || otherOn { isOn.wrappedValue.toggle() }
        } label: {
            VideoFormGlyph(form: form, on: on, scale: 1.35)
                .frame(width: 35, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(!on ? "\(name): off. Click to download them too"
              : otherOn ? "\(name): on. Click to stop downloading them"
              : "\(name): on. One kind always stays on")
        .accessibilityLabel(name)
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// A tiny video frame with a play triangle: portrait for short videos, landscape for long ones.
struct VideoFormGlyph: View {
    let form: VideoForm
    let on: Bool
    var offColor = Color.secondary.opacity(0.6)
    /// 1 is the small size used on buttons; larger for the toggles on each creator's row.
    var scale: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3 * scale, style: .continuous)
        let off = offColor
        ZStack {
            if on {
                shape.fill(Color.red)
            } else {
                shape.strokeBorder(off, lineWidth: 1.5 * scale)
            }
            Image(systemName: "play.fill")
                .font(.system(size: (form == .short ? 6 : 7) * scale, weight: .bold))
                .foregroundStyle(on ? Color.white : off)
        }
        .frame(width: (form == .short ? 12 : 22) * scale, height: (form == .short ? 19 : 14) * scale)
    }
}

/// Every line logged by downloads this session, in its own window (Show Download Log in the File menu).
struct DownloadLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { i, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled).id(i)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                if model.log.isEmpty {
                    ContentUnavailableView("Nothing logged yet", systemImage: "text.alignleft",
                                           description: Text("Downloads write what they're doing here."))
                }
            }
            .onAppear { proxy.scrollTo(model.log.count - 1, anchor: .bottom) }
            .onChange(of: model.log.count) { _, count in proxy.scrollTo(count - 1, anchor: .bottom) }
        }
        .frame(minWidth: 520, minHeight: 240)
    }
}

/// Asks before trimming creators kept by count down to their count (`AppModel.trimToKeep`), then does it.
@MainActor
func confirmTrim(_ model: AppModel, creators: [Creator], vine: Bool = false) {
    let plan = model.trimmableVideos(creators, vine: vine)
    let count = plan.values.reduce(0) { $0 + $1.count }
    let alert = NSAlert()
    guard count > 0 else {
        alert.messageText = "Nothing to trim"
        alert.informativeText = "Every creator kept by count (and Vine) has no more unwatched videos than its count."
        alert.runModal()
        return
    }
    let names = plan.keys.compactMap { $0 == Vine.feedID ? "Vine" : model.library(for: $0)?.displayName }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    alert.messageText = "Trim \(count) unwatched video\(count == 1 ? "" : "s")?"
    alert.informativeText = "From \(names.formatted(.list(type: .and))). Each keeps its oldest unwatched videos, up to its count; "
        + "the rest go to the Trash and come out of the download history, so they download again later in their turn. "
        + "Watched and bookmarked videos stay."
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    if model.trimToKeep(creators, vine: vine) == nil {
        let busy = NSAlert()
        busy.messageText = "A download is running"
        busy.informativeText = "Try again when it finishes."
        busy.runModal()
    }
}
