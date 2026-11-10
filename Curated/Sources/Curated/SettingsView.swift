import AppKit
import SwiftUI

/// The Settings window's sections, down its sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case downloads, playback, storage, phone, ipod, appearance, advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .playback: "Playback"
        case .storage: "Storage"
        case .phone: "Phone"
        case .ipod: "iPod"
        case .appearance: "Appearance"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .downloads: "icloud.and.arrow.down.fill"
        case .playback: "play.fill"
        case .storage: "internaldrive.fill"
        case .phone: "iphone"
        case .ipod: "ipod"
        case .appearance: "paintpalette.fill"
        case .advanced: "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .downloads: .curatedBlue
        case .playback: .logoRed
        case .storage: .purple
        case .phone: .green
        case .ipod: .pink
        case .appearance: .orange
        case .advanced: .gray
        }
    }
}

/// System Settings–style: a sidebar of sections with colored icon tiles, each section a grouped form. Each section
/// opens with a status card where there's something to show (the next download, disk use, phone sync).
struct SettingsView: View {
    #if DEBUG
    /// CURATED_TEST_SETTINGS=<pane> opens on that section, for tests.
    @State private var pane = ProcessInfo.processInfo.environment["CURATED_TEST_SETTINGS"].flatMap(SettingsPane.init) ?? .downloads
    #else
    @State private var pane = SettingsPane.downloads
    #endif

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(symbol: pane.symbol, tint: pane.tint, size: 22)
                }
                .tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch pane {
                case .downloads: DownloadsSettings()
                case .playback: PlaybackSettings()
                case .storage: StorageSettings()
                case .phone: PhoneSettings()
                case .ipod: IPodSettings()
                case .appearance: AppearanceSettings()
                case .advanced: AdvancedSettings()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(width: 720, height: 690)
    }
}

// MARK: - Pieces

/// A white symbol on a rounded square of color, like System Settings' icons.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// The card at the top of a section: a large icon, a headline and a line or two under it, and an optional control.
struct SettingsStatusCard<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.vertical, 6)
    }
}

extension SettingsStatusCard where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: String, detail: String) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

/// A row with a title and a gray line under it, and its control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(title)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A section's one-line note.
private func note(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
}

private func plural(_ count: Int, _ word: String) -> String { "\(count.formatted()) \(word)\(count == 1 ? "" : "s")" }

// MARK: - Downloads

/// Custom cards rather than a form: the download's status up top, then each setting as a picture-led card, side by
/// side where two belong together.
private struct DownloadsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                CardGroup("Schedule") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            SettingsIcon(symbol: "clock.fill", tint: .indigo, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Download automatically").font(.body.weight(.medium))
                                Text("Even when Curated is closed")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Toggle("Download automatically", isOn: $model.settings.scheduleEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.settings.scheduleTimes.indices, id: \.self) { i in
                                HStack(spacing: 6) {
                                    Text("every day at").font(.callout).foregroundStyle(.secondary)
                                    DatePicker("Time", selection: scheduleTime(i), displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .focusable(false)
                                    if model.settings.scheduleTimes.count > 1 {
                                        Button {
                                            model.settings.scheduleTimes.remove(at: i)
                                        } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove this time")
                                    }
                                }
                            }
                            Button("Add a Time", systemImage: "plus", action: addScheduleTime)
                                .controlSize(.small)
                        }
                        .padding(.leading, 50)
                        .opacity(model.settings.scheduleEnabled ? 1 : 0.4)
                        .disabled(!model.settings.scheduleEnabled)
                    }
                    .card()
                }

                CardGroup("When Curated Opens") {
                    HStack(spacing: 12) {
                        LaunchTile(title: "TikTok", isOn: $model.settings.downloadOnLaunch) {
                            PlatformIcon(platform: .tiktok, size: 26)
                        }
                        LaunchTile(title: "YouTube Shorts", isOn: $model.settings.downloadYouTubeOnLaunch) {
                            ShortsGlyph(height: 30)
                        }
                    }
                }

                CardGroup("Sign-In", note: "Only needed if downloads fail asking you to log in or prove you're not a bot. Curated borrows the sign-in from that browser (Safari needs Full Disk Access).") {
                    HStack(alignment: .top, spacing: 12) {
                        SignInCard(title: "TikTok", browser: $model.settings.cookieBrowser) {
                            PlatformIcon(platform: .tiktok, size: 22)
                        }
                        SignInCard(title: "YouTube", browser: $model.settings.youtubeCookieBrowser) {
                            PlatformIcon(platform: .youtube, size: 24)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }

                CardGroup("Vine") {
                    HStack(spacing: 14) {
                        VineLogo(size: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Classic Vines").font(.body.weight(.medium))
                            Text("From divine.video's archive, mixed into Automix")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Picker("Keep", selection: Binding(get: { model.settings.vineBatchSize },
                                                          set: { model.setVineBatchSize($0) })) {
                            ForEach(Set(Vine.batchSizes + [model.settings.vineBatchSize]).sorted(), id: \.self) {
                                Text("Keep \($0)").tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .help("How many unwatched Vines to keep; each download tops it back up")
                        .opacity(model.settings.vineEnabled ? 1 : 0.4)
                        .disabled(!model.settings.vineEnabled)
                        Toggle("Classic Vines", isOn: $model.settings.vineEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .card()
                }
            }
            .padding(24)
        }
        .testScrollAnchor()
    }

    /// The download's status on a blue card, with the cloud graphic and Download Now (or Stop and its progress).
    private var hero: some View {
        HStack(spacing: 18) {
            CloudDownloadGraphic(active: model.isDownloading)
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.title3.weight(.semibold))
                Text(statusDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if model.isDownloading {
                    ProgressView(value: model.downloadProgress ?? 0)
                        .tint(.white)
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            Group {
                if model.isDownloading {
                    Button("Stop") { model.cancelDownloads() }
                } else {
                    Button("Download Now", action: model.downloadAll)
                        .disabled(model.config.creators.isEmpty && !model.settings.vineEnabled)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.curatedBlue.opacity(0.35), Color.logoCyan.opacity(0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.curatedBlue.opacity(0.35))
                }
        }
    }

    private var statusTitle: String {
        if model.isDownloading { return "Downloading…" }
        guard let next = Scheduler.nextRun(model.settings) else { return "Automatic downloads are off" }
        return "Next download at \(next.formatted(date: .omitted, time: .shortened))"
    }

    /// When the next one is ("In 3 hours"), then how the last one went.
    private var statusDetail: String {
        if model.isDownloading { return model.lastActivity ?? "Starting…" }
        let next = Scheduler.nextRun(model.settings).map { $0.formatted(.relative(presentation: .named)).capitalizedFirst }
        let last = model.runState.lastRun.map { "last download \($0.formatted(.relative(presentation: .named)))" }
            ?? "nothing downloaded yet"
        return ([next, last, model.downloadMessage].compactMap { $0 }.joined(separator: " · ")).capitalizedFirst
    }

    private func scheduleTime(_ i: Int) -> Binding<Date> {
        Binding {
            let times = model.settings.scheduleTimes
            guard times.indices.contains(i) else { return Date() }
            return Calendar.current.date(bySettingHour: times[i].hour, minute: times[i].minute, second: 0, of: Date()) ?? Date()
        } set: { date in
            guard model.settings.scheduleTimes.indices.contains(i) else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.settings.scheduleTimes[i] = ScheduleTime(hour: c.hour ?? 3, minute: c.minute ?? 0)
        }
    }

    /// Adds a time six hours after the latest one (or the next free hour after that), keeping the list in order.
    private func addScheduleTime() {
        var times = model.settings.scheduleTimes.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        guard var new = times.last else { return }
        new.hour = (new.hour + 6) % 24
        while times.contains(new) { new.hour = (new.hour + 1) % 24 }
        times.append(new)
        times.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        model.settings.scheduleTimes = times
    }
}

/// A heading over one or more cards, and a note under them.
struct CardGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).padding(.leading, 4)
            content
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// CURATED_TEST_SCROLL=bottom opens a scrolling section at its end, for screenshots (debug builds only).
    @ViewBuilder func testScrollAnchor() -> some View {
        #if DEBUG
        defaultScrollAnchor(ProcessInfo.processInfo.environment["CURATED_TEST_SCROLL"] == "bottom" ? .bottom : .top)
        #else
        self
        #endif
    }

    /// A settings card: a soft rounded panel with a hairline edge.
    func card(highlighted: Bool = false) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(highlighted ? 0.07 : 0.045),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08),
                                  lineWidth: highlighted ? 1.5 : 1)
            }
    }
}

/// A platform to check when Curated opens: its logo and name, the whole card a toggle, lit while on.
private struct LaunchTile<Logo: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var logo: Logo

    var body: some View {
        Button { withAnimation(.snappy(duration: 0.2)) { isOn.toggle() } } label: {
            HStack(spacing: 12) {
                logo.frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium))
                    Text(isOn ? "Checks for new videos" : "Waits for the schedule")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .card(highlighted: isOn)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Which browser's sign-in a platform's downloads borrow: the platform's logo and name over a menu of browsers,
/// each with its own app icon.
private struct SignInCard<Logo: View>: View {
    let title: String
    @Binding var browser: CookieBrowser
    @ViewBuilder var logo: Logo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                logo.frame(width: 28, height: 28)
                Text(title).font(.body.weight(.medium))
            }
            Menu {
                ForEach(CookieBrowser.allCases) { option in
                    Button { browser = option } label: {
                        if let icon = option.icon {
                            Label { Text(option.menuLabel) } icon: { Image(nsImage: icon) }
                        } else {
                            Label(option.menuLabel, systemImage: "person.crop.circle.badge.xmark")
                        }
                    }
                }
            } label: {
                MenuPill {
                    if let icon = browser.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "person.crop.circle.badge.xmark").foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    Text(browser.menuLabel)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .card()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A menu's face in the cards: an icon and the current choice on a soft rounded fill, with up-down chevrons.
struct MenuPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) {
            content.lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

extension CookieBrowser {
    var menuLabel: String { self == .none ? "Not signed in" : label }

    private var bundleID: String? {
        switch self {
        case .none: nil
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .firefox: "org.mozilla.firefox"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        }
    }

    /// The browser's app icon, if it's installed.
    var icon: NSImage? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}

/// YouTube Shorts as a picture: a tall red video with a white play mark.
struct ShortsGlyph: View {
    var height: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 1, green: 0.2, blue: 0.2), Color(red: 0.85, green: 0, blue: 0.05)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: height * 0.62, height: height)
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: height * 0.32, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}

/// Downloads' own picture: a white cloud with an arrow coming down out of it, on a blue tile, with a few sparkles of
/// signal around it. The arrow bobs while a download runs.
struct CloudDownloadGraphic: View {
    var active = false
    var size: CGFloat = 76
    @State private var bob = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.7, blue: 1), .curatedBlue],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .curatedBlue.opacity(0.45), radius: 10, y: 4)
            // Signal dots, like data on its way.
            ForEach(Array([(-0.3, -0.3, 0.07), (0.32, -0.26, 0.05), (0.3, 0.3, 0.06)].enumerated()), id: \.offset) { _, dot in
                Circle().fill(.white.opacity(0.55))
                    .frame(width: size * dot.2, height: size * dot.2)
                    .offset(x: size * dot.0, y: size * dot.1)
            }
            Image(systemName: "cloud.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                .offset(y: -size * 0.05)
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.2, weight: .heavy))
                .foregroundStyle(Color.curatedBlue)
                .offset(y: size * (bob ? 0.03 : -0.01))
        }
        .frame(width: size, height: size)
        .onChange(of: active, initial: true) { _, active in
            if active {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { bob = true }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { bob = false }
            }
        }
        .accessibilityHidden(true)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Playback

private struct PlaybackSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback

    private static let quickPicks = [5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        @Bindable var model = model
        @Bindable var playback = playback
        let timeLimit = Binding(get: { model.settings.timeLimitMinutes }, set: { model.setTimeLimit($0) })
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                formHeading("Short Videos", symbol: "rectangle.portrait.fill", tint: .curatedBlue)

                autoplayCard(detail: "Go on to the next video when one ends, instead of playing it on a loop.",
                             isOn: $playback.autoplayShort)

                CardGroup("Time Limit") {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                SettingsIcon(symbol: "stopwatch.fill", tint: .orange, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Time Limit mix").font(.body.weight(.medium))
                                    Text("How long it plays before it ends and suggests some sunshine")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Quick picks").font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    ForEach(Self.quickPicks, id: \.self) { pick in
                                        let on = model.settings.timeLimitMinutes == pick
                                        Button { withAnimation(.snappy) { model.setTimeLimit(pick) } } label: {
                                            Text("\(pick)")
                                                .font(.callout.weight(.medium)).monospacedDigit()
                                                .frame(minWidth: 26)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .foregroundStyle(on ? Color.white : Color.primary)
                                                .background(on ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.primary.opacity(0.07)),
                                                            in: Capsule())
                                                .contentShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        TimeLimitDial(minutes: timeLimit)
                    }
                    .card()
                }

                CategoryRulesGroup(form: .short)

                CardGroup("Sound") {
                    HStack(spacing: 14) {
                        WaveformGraphic(evened: model.settings.evenOutVolume)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Even out the volume of short videos").font(.body.weight(.medium))
                            Text("Each one is set to the same loudness after it downloads, so quiet videos aren't drowned out. The picture isn't touched.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle("Even out the volume of short videos", isOn: $model.settings.evenOutVolume)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .card()
                }

                formHeading("Long Videos", symbol: "rectangle.fill", tint: .logoRed)
                    .padding(.top, 10)

                autoplayCard(detail: "Start the next video when one ends, instead of stopping with an Up Next card.",
                             isOn: $playback.autoplayLong)

                CardGroup("Resuming") {
                    HStack(spacing: 14) {
                        SettingsIcon(symbol: "gobackward", tint: .teal, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Back up when resuming").font(.body.weight(.medium))
                            Text("Start a little before where you left off, to pick the thread up again.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Picker("Back up when resuming", selection: Binding(
                            get: { model.settings.playbackRules.resumeRewindSeconds },
                            set: { seconds in model.updatePlaybackRules { $0.resumeRewindSeconds = seconds } })) {
                            ForEach(Set(PlaybackRules.rewindChoices + [model.settings.playbackRules.resumeRewindSeconds]).sorted(), id: \.self) {
                                Text($0 == 0 ? "Off" : "\($0) seconds").tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .card()
                }

                CategoryRulesGroup(form: .long)
            }
            .padding(24)
        }
        .testScrollAnchor()
    }

    private func formHeading(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: symbol, tint: tint, size: 26)
            Text(title).font(.title2.weight(.semibold))
        }
    }

    private func autoplayCard(detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: "play.square.stack.fill", tint: .indigo, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Autoplay").font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle("Autoplay", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
        .card()
    }
}

/// A form's sidebar cards in rows: whether Automix plays each by default, and whether it stays at 1×.
private struct CategoryRulesGroup: View {
    @Environment(AppModel.self) private var model
    let form: VideoForm

    private static let column: CGFloat = 70

    private struct Row: Identifiable {
        let id: String
        let name: String
        let symbol: String?  // nil: the Vine V
        var inMixes = true
    }

    /// As in the Automix picker, plus long videos' playlists, which are never in a mix.
    private var rows: [Row] {
        let shown = form == .short ? model.categories : model.categories.filter { !model.watchLibraries(.long, in: $0.id).isEmpty }
        var rows = shown.map { Row(id: $0.id.uuidString, name: $0.name, symbol: $0.symbol) }
        if !model.uncategorizedWatchLibraries(form).isEmpty {
            rows.append(Row(id: otherCard, name: shown.isEmpty ? "All Creators" : "Other Creators", symbol: "person.2"))
        }
        if form == .short && !model.vineLibraries.isEmpty {
            rows.append(Row(id: vineCard, name: "Vine", symbol: nil))
        }
        if form == .long && !model.playlistLibraries.isEmpty {
            rows.append(Row(id: playlistCard, name: "Playlists", symbol: "list.bullet.rectangle", inMixes: false))
        }
        return rows
    }

    var body: some View {
        CardGroup("Categories", note: "Automix plays the checked categories. Holding its button still lets you pick others for that mix, and a category's own Automix always plays it. A 1× only category plays at normal speed, and your chosen speed comes back on the next video.") {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    Spacer()
                    Text("Automix").frame(width: Self.column)
                    Text("1× only").frame(width: Self.column)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                let rows = rows
                if rows.isEmpty {
                    Text("No categories yet.").font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Group {
                            if let symbol = row.symbol {
                                Image(systemName: symbol)
                            } else {
                                VineGlyph(height: 15)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                        Text(row.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Group {
                            if row.inMixes {
                                Toggle("\(row.name) in Automix", isOn: inAutomix(row.id))
                            } else {
                                Text("–").foregroundStyle(.tertiary).help("Playlists are watched on their own, not in Automix")
                            }
                        }
                        .frame(width: Self.column)
                        Toggle("\(row.name) 1× only", isOn: normalSpeed(row.id))
                            .frame(width: Self.column)
                    }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
            }
            .card()
        }
    }

    private var keyPath: WritableKeyPath<PlaybackRules, PlaybackRules.Cards> { form == .long ? \.long : \.short }

    private func inAutomix(_ key: String) -> Binding<Bool> {
        Binding {
            !model.settings.playbackRules[keyPath: keyPath].automixOff.contains(key)
        } set: { on in
            model.updatePlaybackRules { rules in
                if on { rules[keyPath: keyPath].automixOff.remove(key) } else { rules[keyPath: keyPath].automixOff.insert(key) }
            }
        }
    }

    private func normalSpeed(_ key: String) -> Binding<Bool> {
        Binding {
            model.settings.playbackRules[keyPath: keyPath].normalSpeed.contains(key)
        } set: { on in
            model.updatePlaybackRules { rules in
                if on { rules[keyPath: keyPath].normalSpeed.insert(key) } else { rules[keyPath: keyPath].normalSpeed.remove(key) }
            }
        }
    }
}

/// A round dial for the Time Limit, 0 to 60 minutes clockwise from the top: drag the knob (or anywhere on the ring),
/// or use the arrow keys. A time limit under a minute means nothing, so it stops at 1.
private struct TimeLimitDial: View {
    @Binding var minutes: Int
    var size: CGFloat = 160

    private static let maxMinutes = 60
    private static let ring: CGFloat = 14

    var body: some View {
        let fraction = Double(min(minutes, Self.maxMinutes)) / Double(Self.maxMinutes)
        let radius = (size - Self.ring) / 2
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: Self.ring)
            // A tick a minute inside the ring, longer every five.
            ForEach(0..<Self.maxMinutes, id: \.self) { i in
                Capsule()
                    .fill(Color.primary.opacity(i % 5 == 0 ? 0.4 : 0.15))
                    .frame(width: i % 5 == 0 ? 2 : 1, height: i % 5 == 0 ? 7 : 4)
                    .offset(y: -(radius - Self.ring / 2 - 8))
                    .rotationEffect(.degrees(Double(i) * 6))
            }
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [Color(red: 1, green: 0.75, blue: 0.2), .orange, .logoRed],
                                        center: .center, startAngle: .zero, endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: Self.ring, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(.white)
                .frame(width: Self.ring + 6, height: Self.ring + 6)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(y: -radius)
                .rotationEffect(.degrees(360 * fraction))
            VStack(spacing: -2) {
                Text("\(minutes)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(minutes)))
                Text(minutes == 1 ? "minute" : "minutes").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { set(at: $0.location) })
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .rightArrow]) { _ in step(1) }
        .onKeyPress(keys: [.downArrow, .leftArrow]) { _ in step(-1) }
        .accessibilityElement()
        .accessibilityLabel("Time Limit")
        .accessibilityValue("\(minutes) minutes")
        .accessibilityAdjustableAction { direction in
            _ = step(direction == .increment ? 1 : -1)
        }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        withAnimation(.snappy) { minutes = min(Self.maxMinutes, max(1, min(minutes, Self.maxMinutes) + delta)) }
        return .handled
    }

    /// The minute under `point`, clockwise from the top. Dragging past the top doesn't wrap: it holds at 60 (or 1).
    private func set(at point: CGPoint) {
        let dx = point.x - size / 2, dy = point.y - size / 2
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        var value = Int((degrees / 360 * Double(Self.maxMinutes)).rounded())
        let current = min(minutes, Self.maxMinutes)
        if current >= 45 && value <= 15 { value = Self.maxMinutes }
        if current <= 15 && value >= 45 { value = 1 }
        value = min(Self.maxMinutes, max(1, value))
        if value != minutes { withAnimation(.snappy(duration: 0.15)) { minutes = value } }
    }
}

// MARK: - Storage

private struct StorageSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(Playback.self) private var playback
    @State private var old: [URL] = []
    @State private var oldSize: Int64 = 0
    @State private var confirmUnwatched = false
    @State private var confirmOld = false
    @State private var confirmWatched = false
    @State private var confirmLibrary = false
    @State private var confirmReset = false
    @State private var resultMessage: String?

    var body: some View {
        @Bindable var model = model
        let short = model.libraries.flatMap(\.videos), long = model.longLibraries.flatMap(\.videos)
        let vines = model.vineLibraries.flatMap(\.videos)
        let all = short + long + vines
        let watched = all.filter { model.isPlayed($0) && !model.isBookmarked($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                StorageUsage(parts: [("Short", Color.curatedBlue, short), ("Long", Color.logoRed, long)]
                             + (vines.isEmpty ? [] : [("Vine", Color.green, vines)]))
                    .card()

                CardGroup("Location") {
                    HStack(spacing: 14) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.settings.libraryPath))
                            .resizable().frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.settings.libraryURL.lastPathComponent).font(.body.weight(.medium))
                            Text(model.settings.libraryPath.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.head)
                        }
                        Spacer(minLength: 12)
                        Button("Change…", action: chooseFolder)
                        Button("Show in Finder") {
                            try? FileManager.default.createDirectory(at: model.settings.libraryURL, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(model.settings.libraryURL)
                        }
                    }
                    .card()
                }

                CardGroup("Automatic Cleanup") {
                    HStack(spacing: 14) {
                        BroomGraphic()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete videos older than their creator's limit").font(.body.weight(.medium))
                            Text("Long videos and bookmarks are always kept. Deleted videos are never downloaded again.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 12)
                        Toggle("Delete videos older than their creator's limit", isOn: $model.settings.deleteOutsideWindow)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .card()
                }

                CardGroup("Clean Up Now", note: "Bookmarked videos are never deleted. Your phone drops deleted videos on its next sync.") {
                    HStack(spacing: 12) {
                        CleanupCard(symbol: "calendar.badge.clock", tint: .orange, title: "Old videos",
                                    count: old.count, size: oldSize, disabled: model.isDownloading) { confirmOld = true }
                        CleanupCard(symbol: "eye.fill", tint: .teal, title: "Watched videos",
                                    count: watched.count, size: watched.reduce(0) { $0 + $1.size },
                                    disabled: model.isDownloading) { confirmWatched = true }
                    }
                }

                CardGroup("Library") {
                    ActionRow(symbol: "arrow.counterclockwise", tint: .blue, title: "Mark everything as unwatched",
                              detail: plural(model.played.count, "video") + " marked watched",
                              button: "Mark All as Unwatched…", disabled: model.played.isEmpty) { confirmUnwatched = true }
                        .card()
                }

                CardGroup("Start Over", note: "Both move files to the Trash, so they can be put back until it's emptied.") {
                    VStack(spacing: 0) {
                        ActionRow(symbol: "film.stack.fill", tint: .red, title: "Delete the video library",
                                  detail: "Every downloaded video. Creators, categories and settings stay; the next download starts afresh.",
                                  button: "Delete Library…", destructive: true,
                                  disabled: all.isEmpty || model.isDownloading) { confirmLibrary = true }
                        Divider().padding(.vertical, 12)
                        ActionRow(symbol: "exclamationmark.arrow.trianglehead.counterclockwise.rotate.90",
                                  tint: Color(red: 0.6, green: 0.05, blue: 0.1), title: "Reset Curated",
                                  detail: "Erases everything: videos, creators, history, paired phones and every setting. Curated starts again like new.",
                                  button: "Reset Everything…", destructive: true,
                                  disabled: model.isDownloading) { confirmReset = true }
                    }
                    .card()
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.red.opacity(0.45))
                    }
                }
            }
            .padding(24)
        }
        .testScrollAnchor()
        .onAppear(perform: measureOld)
        .onChange(of: model.libraries.map(\.videos.count)) { measureOld() }
        .confirmationDialog("Mark every video as unwatched?", isPresented: $confirmUnwatched) {
            Button("Mark All as Unwatched", role: .destructive) {
                model.markAllUnplayed()
                resultMessage = "Every video is marked unwatched."
            }
        } message: {
            Text("Every downloaded video shows up again in Automix, Top lists and each creator's queue.")
        }
        .confirmationDialog("Delete \(plural(old.count, "old video"))?", isPresented: $confirmOld) {
            Button("Delete \(plural(old.count, "Video"))", role: .destructive) {
                let removed = model.deleteOldVideos()
                resultMessage = "Deleted \(plural(removed, "video"))."
                measureOld()
            }
        } message: {
            Text("These are older than their creator's limit. The files are deleted, and they won't be downloaded again.")
        }
        .confirmationDialog("Delete \(plural(watched.count, "watched video"))?", isPresented: $confirmWatched) {
            Button("Delete \(plural(watched.count, "Video"))", role: .destructive) {
                let removed = model.deleteWatchedVideos()
                resultMessage = "Deleted \(plural(removed, "watched video"))."
            }
        } message: {
            Text("The files are deleted from this Mac, and from your phone on its next sync. Curated remembers them, so they won't be downloaded again.")
        }
        .confirmationDialog("Delete the whole video library?", isPresented: $confirmLibrary) {
            Button("Move \(plural(all.count, "Video")) to the Trash", role: .destructive) {
                if let removed = model.deleteLibrary() {
                    resultMessage = "Moved \(plural(removed, "video")) to the Trash."
                    measureOld()
                }
            }
        } message: {
            Text("\(plural(all.count, "video")) (\(all.reduce(0) { $0 + $1.size }.formatted(.byteCount(style: .file)))) and each creator's download history go to the Trash, and your phone drops them on its next sync. Your creators, categories, watched history and settings stay.")
        }
        .sheet(isPresented: $confirmReset) {
            ResetSheet { model.resetEverything(stopping: playback) }
        }
        .alert(resultMessage ?? "", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") {}
        }
    }

    private func measureOld() {
        old = model.oldVideos()
        oldSize = old.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.libraryURL
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.libraryPath = url.path
        }
    }
}

/// One of the Clean Up Now cards: what it removes, how many and how much space, and a Delete button.
private struct CleanupCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let count: Int
    let size: Int64
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: symbol, tint: tint, size: 32)
                Text(title).font(.body.weight(.medium))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(count.formatted()).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text(count == 0 ? "videos" : "videos · \(size.formatted(.byteCount(style: .file)))")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Delete…", action: action)
                    .disabled(count == 0 || disabled)
            }
        }
        .card()
    }
}

/// A row in a card: an icon tile, a title over a line of detail, and a button.
private struct ActionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let button: String
    var destructive = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(button, role: destructive ? .destructive : nil, action: action)
                .tint(destructive ? .red : nil)
                .disabled(disabled)
        }
    }
}

/// Reset Everything's last word: what goes, and a box to type RESET into before the button wakes up.
private struct ResetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let reset: () -> Void
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                SettingsIcon(symbol: "exclamationmark.triangle.fill", tint: .red, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset Curated?").font(.title2.weight(.bold))
                    Text("This can't be undone from inside Curated.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["Every downloaded video goes to the Trash",
                         "Creators, categories and playlists are removed",
                         "Watched history, Watch Later, bookmarks and resume points are erased",
                         "Paired phones are forgotten and will need to pair again",
                         "Every setting, and the overnight download, go back to new"], id: \.self) { line in
                    Label(line, systemImage: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
            }
            .font(.callout)
            VStack(alignment: .leading, spacing: 6) {
                Text("Type RESET to confirm").font(.caption).foregroundStyle(.secondary)
                TextField("RESET", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if typed == "RESET" { dismiss(); reset() } }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Reset Everything", role: .destructive) {
                    dismiss()
                    reset()
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .disabled(typed != "RESET")
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// How much space the videos take: the total, a bar split by kind, and a legend with each kind's size.
private struct StorageUsage: View {
    let parts: [(name: String, color: Color, videos: [Video])]

    var body: some View {
        let sizes = parts.map { $0.videos.reduce(Int64(0)) { $0 + $1.size } }
        let total = sizes.reduce(0, +)
        let count = parts.reduce(0) { $0 + $1.videos.count }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(total.formatted(.byteCount(style: .file))).font(.title2.weight(.semibold)).monospacedDigit()
                Text("in \(plural(count, "video"))").foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                        if sizes[i] > 0 {
                            Rectangle().fill(part.color.gradient)
                                .frame(width: max(3, geo.size.width * Double(sizes[i]) / Double(max(total, 1)) - 2))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .background(.quaternary)
                .clipShape(Capsule())
            }
            .frame(height: 10)
            HStack(spacing: 16) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    HStack(spacing: 5) {
                        Circle().fill(part.color).frame(width: 8, height: 8)
                        Text(part.name)
                        Text(sizes[i] == 0 ? "None" : sizes[i].formatted(.byteCount(style: .file)))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Phone

private struct PhoneSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                SettingsStatusCard(symbol: "iphone", tint: .green, title: statusTitle, detail: statusDetail) {
                    Toggle("Phone sync", isOn: $model.settings.syncEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            // Hidden while sync is off: the card says how to turn it on.
            if model.settings.syncEnabled {
                Section {
                    Toggle(isOn: $model.settings.syncDiscoverable) {
                        Text("Let phones find this Mac")
                        Text("Shows up as “\(model.syncServiceName)” on this network.")
                    }
                    Toggle(isOn: $model.usbSyncEnabled) {
                        Text("Sync over USB")
                        Text(model.usbSyncStatus)
                    }
                    .disabled(AdbReverse.executable == nil)
                    LabeledContent("Address") {
                        Text(syncAddresses).textSelection(.enabled).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if let error = model.syncError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    SyncDeviceList()
                    PairingControl()
                } header: {
                    Text("Paired Phones")
                } footer: {
                    note("Only phones paired with a code can sync. Sync isn't encrypted, so use it on networks you trust.")
                }
            }
        }
    }

    private var statusTitle: String {
        guard model.settings.syncEnabled else { return "Phone sync is off" }
        return model.usbSyncActive ? "Phone sync is on · USB connected" : "Phone sync is on"
    }

    private var statusDetail: String {
        guard model.settings.syncEnabled else { return "Curated isn't accepting any connections. Turn it on to copy your videos to your phone." }
        let phones = model.syncDevices.isEmpty ? "No phones paired yet" : plural(model.syncDevices.count, "phone") + " paired"
        return phones + (model.settings.syncDiscoverable ? " · Discoverable on this network" : " · Hidden from the network")
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(Holiday.wordmarksKey) private var holidayWordmarks = false
    @AppStorage(PaneStyle.key) private var paneStyle = PaneStyle.glass
    @AppStorage(AuroraPalette.auroraKey) private var auroraPalette = AuroraPalette.curated.id
    @AppStorage(AuroraPalette.holidayKey) private var holidayPalette = AuroraPalette.holiday[0].id

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ForEach(PaneStyle.allCases) { style in
                        Button { withAnimation(.snappy) { paneStyle = style } } label: {
                            VStack(spacing: 6) {
                                preview(style)
                                    .frame(height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(paneStyle == style ? Color.accentColor : Color.primary.opacity(0.12),
                                                          lineWidth: paneStyle == style ? 3 : 1)
                                    }
                                Text(style.label)
                                    .font(.callout.weight(paneStyle == style ? .semibold : .regular))
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Sidebar and Queue")
            } footer: {
                note(paneStyle == .glass ? "A blur of whatever's behind the window. Full screen shows the Aurora colors instead."
                     : paneStyle == .aurora ? "Slow, drifting color, like the phones."
                     : "The Aurora in a holiday's colors.")
            }

            Section("Logo") {
                Toggle(isOn: $holidayWordmarks) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Holiday wordmarks")
                        // The short sidebar's, then the long sidebar's.
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach([false, true], id: \.self) { long in
                                HStack(spacing: 18) {
                                    ForEach(Holiday.allCases, id: \.self) { holiday in
                                        if let image = LogoView.holidayImage(holiday, dark: colorScheme == .dark, long: long) {
                                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 24)
                                                .help(long ? "\(holiday.name), long videos" : holiday.name)
                                        }
                                    }
                                }
                            }
                        }
                        .opacity(holidayWordmarks ? 1 : 0.45)
                        .saturation(holidayWordmarks ? 1 : 0.3)
                        .animation(.easeOut(duration: 0.2), value: holidayWordmarks)
                    }
                    .padding(.vertical, 4)
                }
                .toggleStyle(.switch)
            }

            if paneStyle != .glass {
                Section("Colors") {
                    let selection = paneStyle == .holiday ? $holidayPalette : $auroraPalette
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 12) {
                        ForEach(paneStyle.palettes) { palette in
                            Button { withAnimation(.snappy) { selection.wrappedValue = palette.id } } label: {
                                VStack(spacing: 6) {
                                    PaletteSwatch(palette: palette)
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                        .overlay { Circle().strokeBorder(Color.primary.opacity(0.12)) }
                                        .padding(3)
                                        .overlay {
                                            if selection.wrappedValue == palette.id {
                                                Circle().strokeBorder(Color.accentColor, lineWidth: 2.5)
                                            }
                                        }
                                    Text(palette.name)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2, reservesSpace: true)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private func preview(_ style: PaneStyle) -> some View {
        switch style {
        case .glass:
            // A desktop, with a window and a few shapes on it, seen through frosted glass.
            ZStack {
                LinearGradient(colors: [.blue.opacity(0.75), .purple.opacity(0.6), .orange.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(.yellow.opacity(0.8)).frame(width: 34).offset(x: -42, y: -14)
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.85)).frame(width: 58, height: 40).offset(x: 30, y: 10)
                Circle().fill(.pink.opacity(0.8)).frame(width: 24).offset(x: -10, y: 26)
            }
            .overlay(.ultraThinMaterial)
        case .aurora: PaletteSwatch(palette: .named(auroraPalette, in: AuroraPalette.aurora))
        case .holiday: PaletteSwatch(palette: .named(holidayPalette, in: AuroraPalette.holiday))
        }
    }
}

/// A still of a palette's aurora: its four blobs, blurred over its base, in light or dark to match the window.
struct PaletteSwatch: View {
    @Environment(\.colorScheme) private var colorScheme
    let palette: AuroraPalette

    /// Where each blob sits (as fractions) and how big it is, as in `AuroraView`'s drifts at rest.
    private static let spots: [(x: Double, y: Double, size: Double)] = [
        (0.22, 0.2, 0.75), (0.82, 0.38, 0.7), (0.45, 0.82, 0.85), (0.65, 0.62, 0.6),
    ]

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height) * 1.3
            ZStack {
                Color(nsColor: dark ? palette.darkBase : palette.lightBase)
                ForEach(Array(zip(Self.spots, palette.blobs).enumerated()), id: \.offset) { _, pair in
                    let (spot, (color, opacity)) = pair
                    let shaded = Color(nsColor: AuroraPalette.shade(color, dark: dark))
                    RadialGradient(colors: [shaded.opacity(AuroraPalette.strength(dark: dark) * 1.3 * opacity), .clear],
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

// MARK: - Advanced

private struct AdvancedSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var versions: [String: String] = [:]
    @State private var updating = false
    @State private var updateResult: String?

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                tool("yt-dlp", purpose: "Downloads the videos")
                tool("ffmpeg", purpose: "Joins and evens out video and sound")
            } header: {
                Text("Tools")
            } footer: {
                if let updateResult {
                    note(updateResult)
                } else {
                    note("Installed with Homebrew. Keep yt-dlp up to date when downloads start failing.")
                }
            }

            Section {
                Picker("Log detail", selection: $model.settings.logLevel) {
                    ForEach(LogLevel.allCases) { Text($0.label).tag($0) }
                }
                LabeledContent("Download log") {
                    HStack {
                        Button("Open Log") { openWindow(id: "log") }
                        Button("Show in Finder") {
                            if !FileManager.default.fileExists(atPath: DownloadLog.file.path) { DownloadLog.info("Log created") }
                            NSWorkspace.shared.activateFileViewerSelecting([DownloadLog.file])
                        }
                    }
                }
            } header: {
                Text("Logging")
            } footer: {
                note("Each creator's result and every error. Detailed adds what each listing found and full error lines; Debug adds every command and its output.")
            }
        }
        .task { await loadVersions() }
    }

    @ViewBuilder private func tool(_ name: String, purpose: String) -> some View {
        let path = Tools.find(name)
        LabeledContent {
            if path == nil {
                Text("brew install \(name)")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            } else if name == "yt-dlp" {
                HStack(spacing: 8) {
                    if updating { ProgressView().controlSize(.small) }
                    Button("Update") { Task { await updateYtDlp() } }
                        .disabled(updating || Tools.find("brew") == nil)
                }
            }
        } label: {
            Label {
                Text(name).font(.body.monospaced())
                Text(path == nil ? "Not installed · \(purpose)"
                                 : [versions[name].map { "Version \($0)" }, purpose].compactMap { $0 }.joined(separator: " · "))
            } icon: {
                Image(systemName: path == nil ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(path == nil ? .red : .green)
                    .font(.title3)
            }
        }
    }

    private func loadVersions() async {
        for (name, arguments) in [("yt-dlp", ["--version"]), ("ffmpeg", ["-version"])] {
            guard let path = Tools.find(name), let output = await run(path, arguments) else { continue }
            // ffmpeg: "ffmpeg version 7.1 Copyright …"; yt-dlp: just the version.
            let first = output.split(separator: "\n").first.map(String.init) ?? ""
            versions[name] = name == "ffmpeg" ? first.split(separator: " ").dropFirst(2).first.map(String.init) : first
        }
    }

    private func updateYtDlp() async {
        guard let brew = Tools.find("brew") else { return }
        updating = true
        let before = versions["yt-dlp"]
        let output = await run(brew, ["upgrade", "yt-dlp"])
        await loadVersions()
        updating = false
        if output == nil {
            updateResult = "Couldn't run Homebrew. In Terminal: brew upgrade yt-dlp"
        } else if let after = versions["yt-dlp"], after != before {
            updateResult = "yt-dlp is updated to \(after)."
        } else {
            updateResult = "yt-dlp is already up to date."
        }
    }

    /// Runs a tool off the main thread and returns what it printed, or nil if it couldn't run.
    private func run(_ path: String, _ arguments: [String]) async -> String? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = Tools.environment
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}
