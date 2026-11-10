#if DEBUG
import MediaPlayer
import UIKit

/// Simulator test helpers, compiled into debug builds only.
///   -resetCurated                       start with no pairing, videos or watched history
///   CURATED_TEST_PAIR=host:port:code    pair with a (test) Mac and sync on launch
///   -muteCurated                        play videos without sound
///   -curatedLong                        start on the long-video Home
///   -curatedSwitchLong                  switch to long videos 3 seconds after launch, as the top bar's mark does
///   -curatedPicker automix|top|...      open that mix's category picker (CuratedApp)
///   -curatedHome                        start on Home instead of in Automix (CuratedApp)
///   -curatedSettings                    start in Settings (CuratedApp)
///   -curatedSettingsPlayback            open Settings on its Playback page (SettingsView, with -curatedSettings)
///   -curatedTestSpeed                   after the first sync, play Automix at 2× and log what each video really plays at (Documents/diagnostics.log)
///   CURATED_TEST_OLDER=<creator key>    open that creator's older videos 2 seconds after launch ("1": youtube@jawed) (CuratedApp)
///   -curatedAppearanceFirst             open Settings on its Appearance page (SettingsView, with -curatedSettings)
///   -curatedLandscape                   turn the window sideways once it's up (the headless simulator can't be turned)
///   -curatedTestReopen                  (already paired) after a sync, play the first long video, pause it past the limit for a fresh
///                                       item, resume, and log where it ended up (Documents/diagnostics.log)
///   -curatedTestArtwork                 log the lock screen's picture for what's playing, and the frame the first video would give (Documents/diagnostics.log)
@MainActor
enum TestHooks {
    static func apply(_ app: AppState, _ playback: Playback) {
        let info = ProcessInfo.processInfo
        if info.arguments.contains("-muteCurated") {
            playback.player.isMuted = true
        }
        if info.arguments.contains("-curatedLong") {
            app.form = .long
        }
        if info.arguments.contains("-curatedSwitchLong") {
            Task {
                try? await Task.sleep(for: .seconds(3))
                app.form = .long
            }
        }
        if info.arguments.contains("-curatedLandscape") {
            Task {
                try? await Task.sleep(for: .seconds(1))
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
        }
        if info.arguments.contains("-resetCurated") {
            app.resetForTesting()
        }
        if let spec = info.environment["CURATED_TEST_PAIR"] {
            let parts = spec.split(separator: ":").map(String.init)
            guard parts.count == 3, let port = Int(parts[1]) else { return }
            Task {
                if app.pairing == nil { _ = await app.pair(host: parts[0], port: port, code: parts[2]) }
                await app.sync()
            }
        }
        if info.arguments.contains("-curatedTestSpeed") {
            Task {
                try? await Task.sleep(for: .seconds(6))  // The pairing and sync above.
                playback.start(Queues.build(.automix(nil), app), mode: .automix(nil))
                playback.cycleSpeed()
                playback.cycleSpeed()
                for _ in 0..<25 {
                    try? await Task.sleep(for: .seconds(1))
                    Diagnostics.log("Speed test: \(playback.current?.id ?? "-") locked \(playback.speedLocked) chosen \(playback.speed) playing at \(playback.player.rate)")
                }
            }
        }
        if info.arguments.contains("-curatedTestArtwork") {
            Task {
                try? await Task.sleep(for: .seconds(4))
                let shown = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork
                Diagnostics.log("Artwork test: \(playback.current?.id ?? "-") shows \(shown.map { "\($0.bounds.size)" } ?? "nothing")")
                guard let video = app.allVideos.first else { return }
                let none = URL(fileURLWithPath: "/nonexistent")
                let frame = await Playback.artworkImage(poster: nil, video: app.store.videoFile(video), avatar: none)
                Diagnostics.log("Artwork test: frame from \(video.id) is \(frame.map { "\($0.size)" } ?? "nothing")")
            }
        }
        if info.arguments.contains("-curatedTestReopen") {
            Task {
                Diagnostics.log("Reopen test: syncing: \(await app.sync(.all))")
                await testReopen(app, playback)
            }
        }
    }
}

@MainActor private func testReopen(_ app: AppState, _ playback: Playback) async {
    guard let video = app.videos(.long).first else { return Diagnostics.log("Reopen test: no long video") }
    func state(_ label: String) {
        Diagnostics.log("Reopen test \(label): \(String(format: "%.1f", playback.player.currentTime().seconds)) s, "
            + "rate \(playback.player.rate), status \(playback.player.timeControlStatus.rawValue), speed \(playback.player.defaultRate)")
    }
    playback.start([video], mode: .longCreator(video.creator))
    try? await Task.sleep(for: .seconds(4))
    playback.cycleSpeed()
    playback.pause()
    try? await Task.sleep(for: .milliseconds(500))
    state("paused")
    try? await Task.sleep(for: .seconds(61))
    playback.togglePlayPause()
    state("just resumed")
    try? await Task.sleep(for: .seconds(3))
    state("3 s later")
    playback.pause()
}

extension AppState {
    func resetForTesting() {
        unpair()
    }
}
#endif
