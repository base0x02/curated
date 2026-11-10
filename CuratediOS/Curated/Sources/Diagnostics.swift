import AVFoundation
import Foundation
import os

/// A small log of playback trouble (picture in picture refused, the audio session failing or interrupted, the sound
/// route changing), kept in the app's Documents as diagnostics.log so it can be copied off the phone over USB:
/// `xcrun devicectl device copy from --device <udid> --domain-type appDataContainer --domain-identifier local.curated.ios
/// --source Documents/diagnostics.log --destination <file>`. Also goes to the system log under "Diagnostics".
enum Diagnostics {
    private static let logger = Logger(subsystem: "local.curated.ios", category: "Diagnostics")
    private static let queue = DispatchQueue(label: "local.curated.diagnostics")
    /// Past this the older half is dropped.
    private static let maxBytes = 256 * 1024

    static let fileURL = URL.documentsDirectory.appending(path: "diagnostics.log")

    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        queue.async {
            let url = fileURL
            var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            text += line
            if text.utf8.count > maxBytes { text = String(text.suffix(text.count / 2)) }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// The audio session's state, for lines about the sound.
    static var audioState: String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)" }.joined(separator: "+")
        return "category \(session.category.rawValue), route \(outputs.isEmpty ? "none" : outputs), "
            + "other audio \(session.isOtherAudioPlaying), volume \(String(format: "%.2f", session.outputVolume))"
    }

    /// Logs the audio session being interrupted (a call, another app taking the sound) and the route changing.
    static func watchAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let reason = (info[AVAudioSessionInterruptionReasonKey] as? UInt).map { " reason \($0)" } ?? ""
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { " options \($0)" } ?? ""
            log("Audio interruption \(type == .began ? "began" : type == .ended ? "ended" : "?")\(reason)\(options); \(audioState)")
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            log("Audio route changed (reason \(reason)); \(audioState)")
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            log("Audio media services were reset")
        }
    }
}
