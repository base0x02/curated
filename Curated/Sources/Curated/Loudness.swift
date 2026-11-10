import Foundation

/// Evens out the volume of short videos, so a quiet one isn't drowned out by the loud one before it in a mix.
/// Each file's audio is measured, then rewritten at the same loudness (EBU R128, like ffmpeg's two-pass loudnorm);
/// the video stream is copied untouched. Long videos are left alone: they're watched one at a time, and rewriting
/// them would mean copying gigabytes.
enum Loudness {
    /// Integrated loudness to aim for (LUFS), the peak ceiling (dBTP) and loudness range, as loudnorm takes them.
    static let target = -16.0
    static let truePeak = -1.5
    static let range = 11.0
    /// Files already within this many dB of the target are left as they are.
    static let tolerance = 1.0

    /// Lists, per folder, the IDs of videos already measured (and evened out if they needed it).
    private static let doneFile = "loudness.txt"

    /// Evens out every video in `folder` that hasn't been done yet: new downloads, and, the first time, the ones from
    /// before this existed. Returns how many files were rewritten.
    @discardableResult
    static func normalize(folder: URL, runner: ProcessRunner, log: @escaping (String) -> Void,
                          label: String) async -> Int {
        guard let ffmpeg = Tools.find("ffmpeg") else { return 0 }
        let doneURL = folder.appendingPathComponent(doneFile)
        var done = Set(((try? String(contentsOf: doneURL, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { Library.videoExtensions.contains($0.pathExtension.lowercased()) && !done.contains(id(of: $0)) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard !files.isEmpty else { return 0 }
        if files.count > 1 { log("\(label): evening out the volume of \(files.count) videos…") }

        var rewritten = 0
        for file in files where !runner.isCancelled {
            guard let outcome = await normalize(file, ffmpeg: ffmpeg, runner: runner) else { continue }
            if outcome { rewritten += 1 }
            done.insert(id(of: file))
            appendLine(id(of: file), to: doneURL)
        }
        return rewritten
    }

    /// The video ID from "<timestamp>_<id>.<ext>", or the whole name for files named otherwise.
    private static func id(of file: URL) -> String {
        Library.parseFilename(file)?.1 ?? file.deletingPathExtension().lastPathComponent
    }

    private static func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private struct Measurement: Decodable {
        let input_i: String
        let input_tp: String
        let input_lra: String
        let input_thresh: String
        let target_offset: String
    }

    /// True if the file was rewritten, false if it didn't need to be (no audio, silent, or already about right),
    /// nil if it couldn't be done (it's tried again next time).
    private static func normalize(_ file: URL, ffmpeg: String, runner: ProcessRunner) async -> Bool? {
        let filter = "loudnorm=I=\(target):TP=\(truePeak):LRA=\(range)"

        // Pass 1: measure. loudnorm prints its findings as a JSON object at the end.
        var output: [String] = []
        var hasAudio = true
        let status = await runner.run(ffmpeg, ["-hide_banner", "-nostats", "-nostdin", "-i", file.path, "-map", "0:a:0?",
                                               "-vn", "-af", filter + ":print_format=json", "-f", "null", "-"]) { line in
            if line.contains("Output file does not contain any stream") || line.contains("does not contain any stream") {
                hasAudio = false
            }
            output.append(line)
            return true
        }
        if runner.isCancelled { return nil }
        guard hasAudio, status == 0 else { return hasAudio ? nil : false }
        guard let start = output.lastIndex(of: "{"), let end = output[start...].firstIndex(of: "}"),
              let json = output[start...end].joined(separator: "\n").data(using: .utf8),
              let m = try? JSONDecoder().decode(Measurement.self, from: json) else { return false }
        // Silence reads as -inf. Near-silent audio is left alone too: boosting it that far would only bring up hiss.
        guard let loudness = Double(m.input_i), loudness.isFinite, loudness > -50 else { return false }
        if abs(loudness - target) < tolerance, (Double(m.input_tp) ?? 0) <= truePeak + 0.5 { return false }

        // Pass 2: rewrite the audio with one steady gain (linear), keeping the video and metadata as they are.
        // Written beside the original under a name the library ignores, then swapped in, so the file is never half there.
        let temp = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).loudness")
        defer { try? FileManager.default.removeItem(at: temp) }
        let measured = ":measured_I=\(m.input_i):measured_TP=\(m.input_tp):measured_LRA=\(m.input_lra)"
            + ":measured_thresh=\(m.input_thresh):offset=\(m.target_offset):linear=true"
        let rewrite = await runner.run(ffmpeg, ["-hide_banner", "-nostats", "-nostdin", "-y", "-i", file.path,
                                                "-map", "0:v?", "-map", "0:a:0", "-map_metadata", "0",
                                                "-c:v", "copy", "-af", filter + measured,
                                                "-c:a", "aac", "-b:a", "128k", "-ar", "48000",
                                                "-movflags", "+faststart", "-f", "mp4", temp.path]) { _ in true }
        guard rewrite == 0, !runner.isCancelled,
              let size = (try? FileManager.default.attributesOfItem(atPath: temp.path))?[.size] as? Int, size > 0
        else { return nil }
        // Keep the original's dates; renaming over it is atomic, and a player that has it open keeps reading the old one.
        let dates = (try? FileManager.default.attributesOfItem(atPath: file.path))
            .map { $0.filter { [.modificationDate, .creationDate].contains($0.key) } } ?? [:]
        try? FileManager.default.setAttributes(dates, ofItemAtPath: temp.path)
        guard rename(temp.path, file.path) == 0 else { return nil }
        return true
    }
}
