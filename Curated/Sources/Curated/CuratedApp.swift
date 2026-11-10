import AppKit
import SwiftUI

struct CuratedApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var model: AppModel
    @State private var playback: Playback

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _playback = State(initialValue: Playback(model: model))
    }

    var body: some Scene {
        WindowGroup("Curated") {
            ContentView()
                .environment(model)
                .environment(playback)
                .frame(minHeight: 620)  // each screen sets its own minimum width
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Pick up anything the overnight job downloaded.
                    if !model.isDownloading { model.reloadLibrary() }
                }
        }
        .commands {
            AboutCommand()
            DownloadCommands(model: model, playback: playback)
            QueueCommands(model: model)
            PlaybackCommands(model: model, playback: playback)
        }

        Settings {
            SettingsView()
                .environment(model)
                .environment(playback)
        }

        Window("Download Log", id: "log") {
            DownloadLogView()
                .environment(model)
        }
        .defaultSize(width: 720, height: 360)

        Window("About Curated", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built as a plain SwiftPM executable, so make sure we come up as a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Replaces the stock About panel with our own window.
struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Curated") { openWindow(id: "about") }
        }
    }
}

/// View menu: shows or hides the queue beside a short video, or a long video's Up Next panel.
struct QueueCommands: Commands {
    let model: AppModel
    @AppStorage("queueHidden") private var queueHidden = false
    @FocusedValue(\.toggleUpNextFromMenu) private var toggleUpNext
    @FocusedValue(\.upNextShown) private var upNextShown

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            if model.form == .long {
                Button(upNextShown == true ? "Hide Queue" : "Show Queue") { toggleUpNext?() }
                    .disabled(toggleUpNext == nil)
            } else {
                Button(queueHidden ? "Show Queue" : "Hide Queue") {
                    withAnimation(.snappy(duration: 0.3)) { queueHidden.toggle() }
                }
            }
        }
    }
}

/// The Playback menu: what the player's buttons do, for the video that's loaded.
struct PlaybackCommands: Commands {
    let model: AppModel
    let playback: Playback
    @FocusedValue(\.toggleTimeLimitFromMenu) private var toggleTimeLimit

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Next Video") { playback.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(playback.current == nil)
            Button("Previous Video") { playback.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!playback.hasPrevious)
            Divider()
            Picker("Playback Speed", selection: Binding(get: { playback.speed }, set: { playback.setSpeed($0) })) {
                ForEach(Playback.speeds, id: \.self) { speed in
                    Text(speed == 1 ? "1×" : speed == 2 ? "2×" : "1.5×").tag(speed)
                }
            }
            .disabled(playback.speedLocked)
            // Whichever kind is loaded, or else showing: short and long videos each keep their own.
            if (playback.current?.form ?? model.form) == .long {
                Toggle("Autoplay", isOn: Binding(get: { playback.autoplayLong }, set: { playback.autoplayLong = $0 }))
            } else {
                Toggle("Autoplay", isOn: Binding(get: { playback.autoplayShort }, set: { playback.autoplayShort = $0 }))
            }
            let timeLimited = playback.timeLimitMinutes != nil
            Button(timeLimited ? "End Time Limit" : "Time Limit") { toggleTimeLimit?() }
                .disabled(toggleTimeLimit == nil
                          || (!timeLimited && (model.libraries + model.vineLibraries).allSatisfy { model.unplayedCount($0) == 0 }))
            Divider()
            Button(playback.current.map(model.isSavedForLater) == true ? "Remove from Watch Later" : "Watch Later") {
                playback.toggleWatchLater()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(playback.current == nil || (playback.finished && playback.current.map(model.isSavedForLater) != true))
            Button(playback.current.map(model.isBookmarked) == true ? "Remove Bookmark" : "Bookmark") {
                playback.toggleBookmark()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(playback.current == nil)
            Button(playback.current.map(model.isPlayed) == true ? "Mark as Unwatched" : "Mark as Watched") {
                if let video = playback.current { model.setPlayed(video, !model.isPlayed(video)) }
            }
            .disabled(playback.current == nil)
            Divider()
            Button("Close Video") { playback.closeVideo() }
                .disabled(playback.current == nil)
        }
    }
}

/// File menu: Download All Now, the download log's window, and sharing the loaded video.
struct DownloadCommands: Commands {
    let model: AppModel
    let playback: Playback
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Download All Now") { model.downloadAll() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.isDownloading || model.config.creators.isEmpty)
            Button("Trim Creators Kept by Count…") {
                confirmTrim(model, creators: model.config.creators, vine: model.settings.vineEnabled)
            }
            .disabled(model.isDownloading || !(model.settings.vineEnabled || model.config.creators.contains(where: \.keepsByCount)))
            Button("Show Download Log") { openWindow(id: "log") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            if let video = playback.current {
                ShareLink("Share", item: video.url)
            } else {
                Button("Share") {}.disabled(true)
            }
        }
    }
}

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            LogoView(height: 30)
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Watch the creators you chose, not the ones an algorithm chose for you.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(spacing: 4) {
                Text("Downloads powered by [yt-dlp](https://github.com/yt-dlp/yt-dlp) and ffmpeg.")
                Text("Not affiliated with TikTok or YouTube.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 340)
    }
}
