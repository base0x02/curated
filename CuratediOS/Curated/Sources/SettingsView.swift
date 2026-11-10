import SwiftUI

/// Settings' pages.
private enum SettingsPage: String, CaseIterable, Identifiable {
    case sync, playback, appearance, storage

    var id: Self { self }

    var title: String {
        switch self {
        case .sync: "Sync"
        case .playback: "Playback"
        case .appearance: "Appearance"
        case .storage: "Storage"
        }
    }

    var symbol: String {
        switch self {
        case .sync: "arrow.triangle.2.circlepath"
        case .playback: "play.fill"
        case .appearance: "paintpalette.fill"
        case .storage: "internaldrive.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sync: .green
        case .playback: .logoRed
        case .appearance: .orange
        case .storage: .purple
        }
    }

    @MainActor @ViewBuilder var content: some View {
        switch self {
        case .sync: SyncSettings()
        case .playback: PlaybackSettings()
        case .appearance: AppearanceSettings()
        case .storage: StorageSettings()
        }
    }
}

/// Full screen in every layout. An upright phone (or any narrow window) gets tabs along the bottom. Anything wider, an
/// iPad either way up or a phone on its side, gets the pages listed on the left and the chosen one on the right. The
/// chosen page carries over when the shape changes.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var page = SettingsView.firstPage

    private static var firstPage: SettingsPage {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-curatedSettingsPlayback") { return .playback }
        if arguments.contains("-curatedAppearanceFirst") { return .appearance }
        #endif
        return .sync
    }

    var body: some View {
        // Read here so a new page updates this view: nothing else in `body` itself reads it, and turning the phone
        // would run the closure below with the page as it was at the last update.
        let current = page
        GeometryReader { geo in
            if sizeClass == .regular || geo.size.width > geo.size.height {
                HStack(spacing: 0) {
                    pageList.frame(width: min(320, max(240, geo.size.width * 0.32)))
                    Divider().ignoresSafeArea()
                    NavigationStack { current.content }
                        .id(current)  // Each page starts at its top.
                }
            } else {
                tabs
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private var doneButton: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("settingsDone")
        }
    }

    private var tabs: some View {
        TabView(selection: $page) {
            ForEach(SettingsPage.allCases) { page in
                NavigationStack {
                    page.content.toolbar { doneButton }
                }
                .tabItem { Label(page.title, systemImage: page.symbol) }
                .tag(page)
            }
        }
    }

    private var pageList: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SettingsPage.allCases) { option in
                        Button { page = option } label: {
                            HStack(spacing: 12) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(option.tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                Text(option.title).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(page == option ? Color.accentColor.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == option ? .isSelected : [])
                        .accessibilityIdentifier("settings-\(option.rawValue)")
                    }
                }
                .padding(12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { doneButton }
        }
    }
}

/// Pairing, or once paired, the Mac and what syncs from it.
private struct SyncSettings: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// Here, on the page: a sheet on a section inside the form closes Settings instead of opening.
    @State private var addingCreator = false

    var body: some View {
        Form {
            if let pairing = app.pairing {
                PairedSections(pairing: pairing, addingCreator: $addingCreator)
            } else {
                PairSections()
            }
            VersionFooter()
        }
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingCreator) { AddCreatorView() }
        // Only while it's on screen is the Mac's download followed.
        .onAppear { app.watchMacDownload() }
        .onDisappear { app.stopWatchingMacDownload(keepingRequested: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.watchMacDownload() }
            if phase == .background { app.stopWatchingMacDownload() }
        }
    }
}

private struct AppearanceSettings: View {
    var body: some View {
        Form {
            AppearanceSection()
            LowPowerSection()
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What's on this device.
private struct StorageSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let videos = app.allVideos
        Form {
            Section {
                LabeledContent("Videos", value: "\(videos.count) · \(formatBytes(app.store.bytesUsed()))")
                LabeledContent("Watch time", value: formatLength(videos.reduce(0) { $0 + ($1.duration ?? 0) }))
            } header: {
                Text("On this \(UIDevice.current.localizedModel)")
            } footer: {
                Text("Videos your Mac deletes are removed here on the next sync. Watched videos sync both ways.")
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Short and long videos' options. Autoplay is this device's; the rest is shared with the Mac and other phones.
private struct PlaybackSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle("Autoplay", isOn: $app.autoplayShort)
                    .accessibilityIdentifier("autoplayShort")
                Picker("Time Limit", selection: Binding(
                    get: { app.timeLimitMinutes },
                    set: { minutes in app.updatePlaybackRules { $0.timeLimitMinutes = minutes } })) {
                    ForEach(Set(PlaybackRules.timeLimitChoices + [app.timeLimitMinutes]).sorted(), id: \.self) {
                        Text("\($0) min").tag($0)
                    }
                }
                .accessibilityIdentifier("timeLimit")
            } header: {
                formHeader("Short Videos", mark: .short)
            } footer: {
                Text("With Autoplay off, each video plays on a loop. Time Limit is how long a Time Limit mix plays before suggesting some sunshine.")
            }
            CategoryRulesSection(form: .short)

            Section {
                Toggle("Autoplay", isOn: $app.autoplayLong)
                    .accessibilityIdentifier("autoplayLong")
                Picker("Back Up When Resuming", selection: Binding(
                    get: { app.playbackRules.resumeRewindSeconds },
                    set: { seconds in app.updatePlaybackRules { $0.resumeRewindSeconds = seconds } })) {
                    ForEach(Set(PlaybackRules.rewindChoices + [app.playbackRules.resumeRewindSeconds]).sorted(), id: \.self) {
                        Text($0 == 0 ? "Off" : "\($0) sec").tag($0)
                    }
                }
                .accessibilityIdentifier("resumeRewind")
            } header: {
                formHeader("Long Videos", mark: .long)
            } footer: {
                Text("With Autoplay off, a video stops at its end with an Up Next card. Backing up starts a video a little before where you left off.")
            }
            CategoryRulesSection(form: .long)
        }
        .navigationTitle("Playback")
        .navigationBarTitleDisplayMode(.inline)
        // See what another device changed. If the Mac can't be reached, these still work here.
        .task { await app.exchangePositions() }
    }

    private func formHeader(_ title: String, mark: CuratedMark.Kind) -> some View {
        HStack(spacing: 6) {
            CuratedMark(kind: mark, height: 14)
            Text(title)
        }
    }
}

/// A form's cards from Home in rows: whether Automix plays each by default, and whether it stays at 1×.
private struct CategoryRulesSection: View {
    @Environment(AppState.self) private var app
    let form: VideoForm

    private static let column: CGFloat = 60

    private struct Row: Identifiable {
        let id: String
        let name: String
        let symbol: String?  // nil: the Vine V
        var inMixes = true
    }

    /// As in the Automix picker, plus long videos' playlists, which are never in a mix.
    private var rows: [Row] {
        let shown = app.categories.filter { form == .short || !app.longLibraries(in: $0.id).isEmpty }
        var rows = shown.map { Row(id: $0.id, name: $0.name, symbol: $0.symbol ?? "folder") }
        let others = form == .short ? app.uncategorizedLibraries : app.uncategorizedLongLibraries
        if !others.isEmpty {
            rows.append(Row(id: otherCard, name: shown.isEmpty ? "All Creators" : "Other Creators", symbol: "person.2"))
        }
        if form == .short && !app.vineLibraries.isEmpty {
            rows.append(Row(id: vineCard, name: "Vine", symbol: nil))
        }
        if form == .long && !app.playlistLibraries.isEmpty {
            rows.append(Row(id: playlistCard, name: "Playlists", symbol: "list.bullet.rectangle", inMixes: false))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Group {
                            if let symbol = row.symbol {
                                Image(systemName: symbol)
                            } else {
                                Image("VineGlyph").resizable().renderingMode(.template).scaledToFit().frame(height: 15)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if row.inMixes {
                            check("\(row.name) in Automix", id: "automix-\(row.name)", isOn: !cards.automixOff.contains(row.id)) { on in
                                change { if on { $0.automixOff.remove(row.id) } else { $0.automixOff.insert(row.id) } }
                            }
                        } else {
                            Text("–").foregroundStyle(.tertiary).frame(width: Self.column)
                        }
                        check("\(row.name) 1× only", id: "oneX-\(row.name)", isOn: cards.normalSpeed.contains(row.id)) { on in
                            change { if on { $0.normalSpeed.insert(row.id) } else { $0.normalSpeed.remove(row.id) } }
                        }
                    }
                }
            } header: {
                HStack(spacing: 10) {
                    Text("Categories")
                    Spacer(minLength: 4)
                    Text("Automix").frame(width: Self.column)
                    Text("1× only").frame(width: Self.column)
                }
                .font(.caption2.weight(.medium))
                .textCase(nil)
            } footer: {
                Text("Automix plays the checked categories. Long-pressing it still lets you pick others for that mix, and a category's own Automix always plays it. A 1× only category plays at normal speed, and your chosen speed comes back on the next video.")
            }
        }
    }

    private var cards: PlaybackRules.Cards { app.playbackRules.cards(form) }

    private func change(_ edit: (inout PlaybackRules.Cards) -> Void) {
        app.updatePlaybackRules { rules in
            if form == .long { edit(&rules.long) } else { edit(&rules.short) }
        }
    }

    private func check(_ label: String, id: String, isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Button { set(!isOn) } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: Self.column, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// The right of the Force Download row: a ring that fills as the Mac downloads, then a checkmark until the next sync.
private struct MacDownloadIndicator: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            if app.macDownloadFinished {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("macDownloadDone")
                    .accessibilityLabel("Download finished on your Mac")
            } else if app.macDownload != nil || app.isRequestingDownload {
                Circle().stroke(.quaternary, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: app.macDownload?.progress ?? 0)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.8), value: app.macDownload?.progress)
                Image(systemName: "arrow.down")
                    .font(.caption2.bold())
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.spring(duration: 0.4), value: app.macDownloadFinished)
        .accessibilityElement(children: app.macDownload != nil ? .ignore : .contain)
        .accessibilityIdentifier(app.macDownload != nil ? "macDownloadProgress" : "macDownloadIndicator")
    }
}

/// The app's version and build, centered under everything else.
private struct VersionFooter: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Curated \(short) (\(build))"
    }

    var body: some View {
        Section {
        } footer: {
            Text(version)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("appVersion")
        }
    }
}

/// Lighter versions of the effects that cost the most battery.
private struct LowPowerSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Toggle("Low Power", isOn: $app.lowPower)
                .accessibilityIdentifier("lowPower")
        } footer: {
            Text("Uses less battery: Home's colors are drawn more simply and move less often, and short videos play on black instead of over a blur of themselves.")
        }
    }
}

private struct AppearanceSection: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Picker("Appearance", selection: $app.appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Picker("Background", selection: $app.backgroundStyle) {
                ForEach(BackgroundStyle.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("backgroundStyle")
            PaletteRow()
            Toggle(isOn: $app.holidayWordmarks) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Holiday wordmarks")
                    // The short Home's, then the long Home's.
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach([false, true], id: \.self) { long in
                                HStack(spacing: 14) {
                                    ForEach(Holiday.allCases, id: \.self) { holiday in
                                        Image(holiday.imageName(long: long)).resizable().scaledToFit().frame(height: 20)
                                            .accessibilityLabel(long ? "\(holiday.name), long videos" : holiday.name)
                                    }
                                }
                            }
                        }
                    }
                    .opacity(app.holidayWordmarks ? 1 : 0.45)
                }
            }
        } header: {
            Text("Appearance")
        }
    }
}

/// The chosen background style's palettes as round swatches to tap, scrolling sideways.
private struct PaletteRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        // Opens scrolled to the current pick.
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(app.backgroundStyle.palettes) { palette in
                    let selected = app.palette.id == palette.id
                    Button {
                        if app.backgroundStyle == .holiday { app.holidayPalette = palette.id } else { app.auroraPalette = palette.id }
                    } label: {
                        VStack(spacing: 6) {
                            PaletteSwatch(palette: palette)
                                .frame(width: 46, height: 46)
                                .clipShape(Circle())
                                .padding(4)
                                .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5) } }
                            Text(palette.name)
                                .font(.caption2)
                                .foregroundStyle(selected ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 86)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(palette.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .id(palette.id)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear { proxy.scrollTo(app.palette.id, anchor: .center) }
        .onChange(of: app.backgroundStyle) { proxy.scrollTo(app.palette.id, anchor: .center) }
        }
    }
}

/// A still of a palette's aurora: its four blobs at rest, blurred over its base, in light or dark to match.
private struct PaletteSwatch: View {
    @Environment(\.colorScheme) private var scheme
    let palette: AuroraPalette

    private static let spots: [(x: Double, y: Double, size: Double)] = [
        (0.22, 0.2, 0.75), (0.82, 0.38, 0.7), (0.45, 0.82, 0.85), (0.65, 0.62, 0.6),
    ]

    var body: some View {
        let dark = scheme == .dark
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.3
            ZStack {
                dark ? palette.darkBase : palette.lightBase
                ForEach(Array(zip(Self.spots, palette.blobs).enumerated()), id: \.offset) { _, pair in
                    let (spot, (color, strength)) = pair
                    let shaded = AuroraPalette.shade(color, dark: dark)
                    RadialGradient(colors: [shaded.opacity(min(1, AuroraPalette.strength(dark: dark) * 1.3 * strength)), .clear],
                                   center: .center, startRadius: 0, endRadius: side * spot.size / 2)
                        .frame(width: side * spot.size, height: side * spot.size)
                        .position(x: spot.x * geo.size.width, y: spot.y * geo.size.height)
                }
            }
            .blur(radius: min(geo.size.width, geo.size.height) * 0.12)
        }
        .drawingGroup()
    }
}

private struct PairSections: View {
    @Environment(AppState.self) private var app
    @State private var found: [FoundMac] = []
    @State private var searching = false
    @State private var selected: FoundMac?
    @State private var address = ""
    @State private var code = ""
    @State private var pairing = false
    @State private var error: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        Section {
        } footer: {
            Text("On your Mac, open Curated, click the antenna button at the bottom of the sidebar and choose **Pair a Phone**. Then pick your Mac here and enter the code it shows.")
                .font(.subheadline)
        }

        Section {
            if found.isEmpty && !searching {
                Text("No Macs found. Check that phone sync is on and the Mac is discoverable, or enter its address below.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(found) { mac in
                Button {
                    selected = mac
                    address = ""
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(mac.name).foregroundStyle(.primary)
                                Text("\(mac.host):\(mac.port)").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "laptopcomputer")
                        }
                        Spacer()
                        if selected == mac && address.isEmpty {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Macs on this network")
                Spacer()
                if searching {
                    ProgressView()
                } else {
                    Button("Search Again") { Task { await search() } }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        }

        Section {
            TextField("192.168.1.20:8765", text: $address)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("addressField")
        } header: {
            Text("Or enter the Mac's address")
        } footer: {
            Text("Shown in the Mac's sync panel.")
        }

        Section("Pairing code") {
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.title2.monospacedDigit())
                .focused($codeFocused)
                .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                .accessibilityIdentifier("codeField")
        }

        Section {
            Button {
                Task { await pair() }
            } label: {
                HStack {
                    Spacer()
                    if pairing { ProgressView().padding(.trailing, 6) }
                    Text(pairing ? "Pairing…" : "Pair").fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(target == nil || code.count != 6 || pairing)
        } footer: {
            if let error {
                Text(error).foregroundStyle(.red)
            }
        }
        .task { await search() }
    }

    private var target: (String, Int)? {
        if !address.trimmingCharacters(in: .whitespaces).isEmpty { return parseMacAddress(address) }
        return selected.map { ($0.host, $0.port) }
    }

    private func search() async {
        searching = true
        found = await Discovery.find()
        if selected == nil, address.isEmpty { selected = found.first }
        searching = false
    }

    private func pair() async {
        guard let (host, port) = target else { return }
        codeFocused = false
        pairing = true
        error = await app.pair(host: host, port: port, code: code)
        pairing = false
        if error == nil { app.syncInBackground() }
    }
}

/// A Mac's address as typed: "host" or "host:port".
func parseMacAddress(_ text: String) -> (String, Int)? {
    var s = text.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("http://") { s.removeFirst(7) }
    while s.hasSuffix("/") { s.removeLast() }
    guard !s.isEmpty else { return nil }
    let parts = s.split(separator: ":")
    if parts.count == 2 {
        guard let port = Int(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }
    return (s, SyncClient.defaultPort)
}

private struct PairedSections: View {
    @Environment(AppState.self) private var app
    let pairing: Pairing
    @State private var confirmUnpair = false
    @Binding var addingCreator: Bool

    var body: some View {
        @Bindable var app = app
        Section("Paired Mac") {
            LabeledContent {
                Text("\(pairing.host):\(String(pairing.port))").font(.caption).foregroundStyle(.secondary)
            } label: {
                Label(pairing.macName, systemImage: "laptopcomputer")
            }
            Button("Unpair", role: .destructive) { confirmUnpair = true }
                .disabled(app.isSyncing)
        }

        Section {
            HStack {
                Button {
                    app.syncInBackground()
                } label: {
                    Label(app.isSyncing ? "Syncing…" : "Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .disabled(app.isSyncing)
                .accessibilityIdentifier("syncNow")
                Spacer()
                if !app.isSyncing, let message = app.lastSyncMessage {
                    let when = app.lastSyncAt.map { " · \($0.formatted(.relative(presentation: .named)))" } ?? ""
                    Text(message + when)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            if app.isSyncing {
                SyncProgressRow()
            }
            Picker("Sync:", selection: $app.syncForms) {
                ForEach(SyncForms.allCases) { Text($0.menuTitle).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("syncForms")
            Toggle("Sync Automatically", isOn: $app.autoSync)
            HStack {
                Button {
                    Task { await app.forceDownload() }
                } label: {
                    Label("Update Mac", systemImage: "laptopcomputer.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("forceDownload")
                .disabled(app.isRequestingDownload || app.macDownload != nil)
                Spacer()
                if let last = app.lastMacDownloadAt {
                    Text("Last: \(last.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                MacDownloadIndicator()
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let download = app.macDownload {
                    Text(macDownloadStatus(download)).lineLimit(2)
                }
                if let message = app.forceDownloadMessage {
                    Text(message)
                }
            }
        }

        Section {
            Button { addingCreator = true } label: {
                Label("Add Creator", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("addCreator")
        }
        .confirmationDialog("Unpair from \(pairing.macName)?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { app.unpair() }
        } message: {
            Text("Its videos and your watched history, Watch Later and bookmarks are removed from this \(UIDevice.current.localizedModel). Your Mac keeps its copies, so pairing again brings them back.")
        }
    }

    /// "Downloading on your Mac · 3 of 8 · @someone, @another".
    private func macDownloadStatus(_ download: MacDownloadProgress) -> String {
        var parts = ["Downloading on your Mac"]
        if let done = download.done, let total = download.total { parts.append("\(done) of \(total)") }
        if let current = download.current, !current.isEmpty { parts.append(current.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}
