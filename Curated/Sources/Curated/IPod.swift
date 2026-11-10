import AppKit
import AVFoundation
import SwiftUI

// Settings > iPod: re-encodes videos into single MP4 files an iPod nano (7th generation) or iPod classic plays.
// A Video Mix stitches short videos from the chosen categories into one file of about the chosen length; Long Videos
// re-encodes each picked long video to its own file. Everything goes to the export folder, and the videos exported are
// listed in the sidebar's iPod list (`AppModel.ipodExports`).

/// Which iPod exports are made for.
enum IPodModel: String, Codable, CaseIterable, Identifiable {
    case nano7, classic

    var id: Self { self }

    var name: String {
        switch self {
        case .nano7: "iPod nano"
        case .classic: "iPod classic"
        }
    }

    var generation: String {
        switch self {
        case .nano7: "7th generation"
        case .classic: "6th generation"
        }
    }

    /// The frame a mix of (portrait) short videos is filled and cropped to, and whether it's then turned 270° clockwise (top to the left, as HandBrake's 270°) so it
    /// fills the nano's screen held sideways.
    var mixFrame: (width: Int, height: Int, rotate: Bool) {
        switch self {
        case .nano7: (240, 432, true)
        case .classic: (320, 560, false)
        }
    }

    /// The frame a long (wide) video is filled and cropped to, never turned.
    var longFrame: (width: Int, height: Int) {
        switch self {
        case .nano7: (432, 240)
        case .classic: (560, 320)
        }
    }

    var mixSizeLabel: String {
        let f = mixFrame
        return f.rotate ? "\(f.height)×\(f.width), turned on its side" : "\(f.width)×\(f.height)"
    }
}

/// Runs the exports with ffmpeg, one at a time. Lives on past the Settings window, so an export carries on if it's
/// closed.
@MainActor @Observable
final class IPodExporter {
    static let shared = IPodExporter()

    private(set) var isRunning = false
    private(set) var title = ""
    private(set) var detail = ""
    private(set) var progress: Double = 0
    /// Which export is running, so its card shows the progress.
    enum Kind { case mix, long }
    private(set) var kind: Kind?
    /// When encoding started (after picking the mix), for the time left.
    private(set) var encodingStarted: Date?
    /// How the last export went, and what it made, until the next one starts.
    private(set) var message: String?
    private(set) var lastOutputs: [URL] = []
    private var runner: ProcessRunner?

    /// The x264 settings every export uses: Baseline-compatible level 3.0, no B-frames or CABAC, a single reference
    /// frame, 768 kb/s peaks.
    static let x264Options = "level=30:bframes=0:weightp=0:cabac=0:ref=1:vbv-maxrate=768:vbv-bufsize=2000:analyse=all"
        + ":me=umh:no-fast-pskip=1:subq=6:8x8dct=0:trellis=0"

    func cancel() {
        runner?.cancel()
    }

    /// Picks short videos from `libraries` (unwatched first, round-robin across creators as Automix does, then
    /// watched ones) until they add up to about `minutes`.
    static func mixVideos(_ libraries: [CreatorLibrary], played: Set<String>, minutes: Int) async -> [(Video, TimeInterval)] {
        let unwatched = Library.automixQueue(libraries, excluding: played)
        let seen = Set(unwatched.map(\.id))
        let watched = Library.automixQueue(libraries, excluding: []).filter { !seen.contains($0.id) }
        let target = TimeInterval(minutes * 60)
        var picked: [(Video, TimeInterval)] = []
        var total: TimeInterval = 0
        for video in unwatched + watched {
            guard total < target else { break }
            let length = await Library.duration(of: video)
            guard length > 0 else { continue }
            // Leave out a video that would overshoot by more than it undershoots without it.
            if total + length - target > target - total, !picked.isEmpty { continue }
            picked.append((video, length))
            total += length
        }
        return picked
    }

    func exportMix(libraries: [CreatorLibrary], minutes: Int, ipod: IPodModel, to folder: URL, model: AppModel) {
        guard !isRunning else { return }
        start("Making a \(minutes)-minute mix…", kind: .mix)
        detail = "Choosing videos…"
        let played = model.played
        Task {
            defer { finish() }
            let clips = await Self.mixVideos(libraries, played: played, minutes: minutes)
            guard !clips.isEmpty else { return fail("There are no videos in those categories.") }
            encodingStarted = Date()
            guard let ffmpeg = Tools.find("ffmpeg") else { return fail("ffmpeg isn't installed (brew install ffmpeg).") }
            guard let work = makeWorkFolder() else { return fail("Couldn't make a temporary folder.") }
            defer { try? FileManager.default.removeItem(at: work) }

            let total = clips.reduce(0) { $0 + $1.1 }
            var done: TimeInterval = 0
            var segments: [URL] = []
            var exported: [Video] = []
            let frame = ipod.mixFrame
            for (i, (video, length)) in clips.enumerated() {
                guard !(runner?.isCancelled ?? true) else { break }
                detail = "Video \(i + 1) of \(clips.count) · " + (model.library(for: video.creator)?.displayName ?? "")
                let segment = work.appendingPathComponent(String(format: "%04d.mp4", i))
                let start = done
                let ok = await encode(ffmpeg, video.url, to: segment, width: frame.width, height: frame.height,
                                      rotate: frame.rotate, length: length) { seconds in
                    self.progress = min(1, (start + seconds) / total) * 0.98
                }
                done += length
                if ok {
                    segments.append(segment)
                    exported.append(video)
                } else {
                    DownloadLog.error("iPod: couldn't convert \(video.url.lastPathComponent); left out of the mix")
                }
            }
            if runner?.isCancelled ?? true { return fail("Stopped.") }
            guard !segments.isEmpty else { return fail("None of the videos could be converted.") }

            detail = "Joining \(segments.count) videos…"
            let list = work.appendingPathComponent("list.txt")
            let lines = segments.map { "file '\($0.path.replacingOccurrences(of: "'", with: "'\\''"))'" }
            try? lines.joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)
            let joined = work.appendingPathComponent("mix.mp4")
            let status = await runner?.run(ffmpeg, ["-nostdin", "-v", "error", "-y", "-f", "concat", "-safe", "0",
                                                     "-i", list.path, "-c", "copy", "-movflags", "+faststart", "-f", "ipod",
                                                     joined.path]) { _ in true } ?? -1
            guard status == 0 else { return fail("Couldn't join the videos.") }

            let stamp = Date().formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits)",
                                                   timeZone: .current, calendar: .current))
            let length = Int((exported.isEmpty ? 0 : clips.filter { c in exported.contains { $0.id == c.0.id } }
                .reduce(0) { $0 + $1.1 }) / 60 + 0.5)
            guard let out = moveOut(joined, to: folder, name: "Curated Mix \(stamp) (\(length) min)") else {
                return fail("Couldn't save the mix in \(folder.lastPathComponent).")
            }
            lastOutputs = [out]
            model.addToIPodList(exported)
            message = "Saved \(out.lastPathComponent): \(exported.count) videos, about \(length) minutes."
        }
    }

    func exportLong(_ videos: [Video], ipod: IPodModel, to folder: URL, model: AppModel) {
        guard !isRunning, !videos.isEmpty else { return }
        start(videos.count == 1 ? "Converting 1 long video…" : "Converting \(videos.count) long videos…", kind: .long)
        Task {
            defer { finish() }
            encodingStarted = Date()
            guard let ffmpeg = Tools.find("ffmpeg") else { return fail("ffmpeg isn't installed (brew install ffmpeg).") }
            guard let work = makeWorkFolder() else { return fail("Couldn't make a temporary folder.") }
            defer { try? FileManager.default.removeItem(at: work) }

            var lengths: [TimeInterval] = []
            for video in videos { lengths.append(max(1, await Library.duration(of: video))) }
            let total = lengths.reduce(0, +)
            var done: TimeInterval = 0
            var outputs: [URL] = []
            var exported: [Video] = []
            let frame = ipod.longFrame
            for (i, video) in videos.enumerated() {
                guard !(runner?.isCancelled ?? true) else { break }
                detail = "\(i + 1) of \(videos.count) · \(video.displayTitle)"
                let temp = work.appendingPathComponent("\(i).mp4")
                let start = done
                let ok = await encode(ffmpeg, video.url, to: temp, width: frame.width, height: frame.height,
                                      rotate: false, length: lengths[i]) { seconds in
                    self.progress = min(1, (start + seconds) / total)
                }
                done += lengths[i]
                let creator = model.library(for: video.creator, form: .long)?.displayName ?? ""
                let name = creator.isEmpty ? video.displayTitle : "\(creator) - \(video.displayTitle)"
                if ok, let out = moveOut(temp, to: folder, name: name) {
                    outputs.append(out)
                    exported.append(video)
                } else if !(runner?.isCancelled ?? true) {
                    DownloadLog.error("iPod: couldn't convert \(video.url.lastPathComponent)")
                }
            }
            lastOutputs = outputs
            model.addToIPodList(exported)
            let failed = videos.count - outputs.count
            if runner?.isCancelled ?? true {
                message = "Stopped." + (outputs.isEmpty ? "" : " \(outputs.count) saved before that.")
            } else if failed > 0 {
                message = "Saved \(outputs.count) of \(videos.count) videos; \(failed) couldn't be converted."
            } else {
                message = outputs.count == 1 ? "Saved \(outputs[0].lastPathComponent)." : "Saved \(outputs.count) videos."
            }
        }
    }

    // MARK: Pieces

    /// About how long is left, once there's enough done to tell.
    func timeLeft(at now: Date) -> TimeInterval? {
        guard let encodingStarted, progress > 0.02, progress < 1 else { return nil }
        let elapsed = now.timeIntervalSince(encodingStarted)
        guard elapsed > 3 else { return nil }
        return elapsed / progress * (1 - progress)
    }

    private func start(_ title: String, kind: Kind) {
        isRunning = true
        self.kind = kind
        encodingStarted = nil
        self.title = title
        detail = "Starting…"
        progress = 0
        message = nil
        lastOutputs = []
        runner = ProcessRunner()
    }

    private func finish() {
        isRunning = false
        kind = nil
        encodingStarted = nil
        runner = nil
    }

    private func fail(_ text: String) {
        message = text
    }

    private func makeWorkFolder() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Curated iPod \(UUID().uuidString)")
        return (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) == nil ? nil : url
    }

    /// Moves a finished file into the export folder as `name`.mp4, numbering it if that name's taken.
    private func moveOut(_ file: URL, to folder: URL, name: String) -> URL? {
        let clean = String(name.map { "/:\\".contains($0) ? "-" : $0 }.prefix(150)).trimmingCharacters(in: .whitespaces)
        var out = folder.appendingPathComponent(clean).appendingPathExtension("mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: out.path) {
            out = folder.appendingPathComponent("\(clean) \(n)").appendingPathExtension("mp4")
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: file, to: out)
            return out
        } catch {
            DownloadLog.error("iPod: couldn't save \(out.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Re-encodes one video for the iPod: filled and cropped to `width`×`height` (then turned 270° clockwise if `rotate`), H.264
    /// at 700 kb/s on average with `x264Options`, the source's own (variable) frame rate, AAC stereo audio (silence if
    /// it has none). `onProgress` gets the seconds done so far.
    private func encode(_ ffmpeg: String, _ input: URL, to output: URL, width: Int, height: Int, rotate: Bool,
                        length: TimeInterval, onProgress: @escaping @MainActor (TimeInterval) -> Void) async -> Bool {
        guard let runner else { return false }
        let hasAudio = !((try? await AVURLAsset(url: input).loadTracks(withMediaType: .audio))?.isEmpty ?? true)
        var filter = "scale=\(width):\(height):force_original_aspect_ratio=increase,crop=\(width):\(height),setsar=1"
        if rotate { filter += ",transpose=2" }  // 270° clockwise (90° counterclockwise), as HandBrake's Rotate 270° does
        var args = ["-nostdin", "-v", "error", "-y", "-i", input.path]
        if hasAudio {
            args += ["-map", "0:v:0", "-map", "0:a:0"]
        } else {
            args += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-map", "0:v:0", "-map", "1:a", "-shortest"]
        }
        args += ["-vf", filter, "-fps_mode", "passthrough",
                 "-c:v", "libx264", "-profile:v", "baseline", "-pix_fmt", "yuv420p", "-b:v", "700k",
                 "-x264opts", Self.x264Options,
                 "-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2",
                 // One timescale for every segment, so a mix joins without re-encoding.
                 "-video_track_timescale", "90000", "-movflags", "+faststart",
                 // The iPod muxer adds the iPod compatibility atom, as HandBrake does.
                 "-f", "ipod",
                 "-progress", "pipe:1", "-nostats", output.path]
        let status = await runner.run(ffmpeg, args) { line in
            if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst("out_time_us=".count)) {
                DispatchQueue.main.async { onProgress(us / 1_000_000) }
            }
            return true
        }
        return status == 0 && FileManager.default.fileExists(atPath: output.path)
    }
}

// MARK: - Settings

/// Settings > iPod, in the Downloads section's cards: the export's status up top, which iPod, the export folder,
/// then a Video Mix and Long Videos card, each with its own Export button.
struct IPodSettings: View {
    @Environment(AppModel.self) private var model
    @State private var exporter = IPodExporter.shared
    /// Whether the export folder is there, checked each time the section opens and when it's changed.
    @State private var folderOK = false
    @State private var choosingLong = false
    @State private var pickedLong: [String] = []

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                CardGroup("iPod") {
                    HStack(spacing: 12) {
                        ForEach(IPodModel.allCases) { ipod in
                            IPodTile(ipod: ipod, isOn: model.settings.ipodModel == ipod) {
                                model.settings.ipodModel = ipod
                            }
                        }
                    }
                }

                CardGroup("Export Folder", note: folderOK ? nil : folderProblem) {
                    folderCard
                }

                CardGroup("Video Mix", note: "Short videos from the categories you pick, unwatched ones first, joined into one video of about this length.") {
                    mixCard
                }

                CardGroup("Long Videos", note: "Each video becomes its own file, \(model.settings.ipodModel.longFrame.width)×\(model.settings.ipodModel.longFrame.height), filled and cropped.") {
                    longCard
                }
            }
            .padding(24)
        }
        .testScrollAnchor()
        .onAppear {
            checkFolder()
            #if DEBUG
            // CURATED_TEST_IPOD_EXPORT=mix exports a mix on opening; =long exports every long video.
            guard let folder = exportFolder, folderOK, !exporter.isRunning else { return }
            switch ProcessInfo.processInfo.environment["CURATED_TEST_IPOD_EXPORT"] {
            case "mix"?:
                exporter.exportMix(libraries: mixLibraries, minutes: model.settings.ipodMixMinutes,
                                   ipod: model.settings.ipodModel, to: folder, model: model)
            case "long"?:
                exporter.exportLong(model.longLibraries.flatMap(\.videos), ipod: model.settings.ipodModel, to: folder, model: model)
            default: break
            }
            #endif
        }
        .onChange(of: model.settings.ipodExportPath) { checkFolder() }
        .sheet(isPresented: $choosingLong) {
            LongVideoChooser(picked: $pickedLong)
        }
    }

    // MARK: Cards

    private var hero: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.65), Color(red: 0.7, green: 0.25, blue: 0.9)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .pink.opacity(0.4), radius: 10, y: 4)
                IPodGlyph(model: model.settings.ipodModel, height: 60)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(exporter.isRunning ? exporter.title : "Videos for your \(model.settings.ipodModel.name)")
                    .font(.title3.weight(.semibold))
                Text(exporter.isRunning ? exporter.detail : exporter.message
                     ?? "One MP4 file per export, ready to add to the Music app or Finder and sync.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if exporter.isRunning {
                    IPodProgressBar().padding(.top, 4)
                }
            }
            Spacer(minLength: 12)
            if exporter.isRunning {
                Button("Stop") { exporter.cancel() }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            } else if !exporter.lastOutputs.isEmpty {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(exporter.lastOutputs) }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.pink.opacity(0.28), Color.purple.opacity(0.1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.pink.opacity(0.35))
                }
        }
    }

    private var folderCard: some View {
        let path = model.settings.ipodExportPath
        return HStack(spacing: 14) {
            Group {
                if folderOK, let path {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                } else {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No folder chosen")
                    .font(.body.weight(.medium))
                Text(path.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "Exports are saved here")
                    .font(.caption).foregroundStyle(folderOK ? Color.secondary : Color.red)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 12)
            Button(folderOK ? "Change…" : "Choose…", action: chooseFolder)
            if folderOK, let path {
                Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }
        }
        .card()
        .overlay {
            if !folderOK {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.red, lineWidth: 2)
            }
        }
    }

    private var mixCard: some View {
        @Bindable var model = model
        let options = mixOptions
        let chosen = Set(model.settings.ipodCategories)
        let libraries = mixLibraries
        let unwatched = libraries.reduce(0) { $0 + $1.videos.count { !model.isPlayed($0) } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SettingsIcon(symbol: "timer", tint: .orange, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Length").font(.body.weight(.medium))
                    Text("About \(model.settings.ipodMixMinutes) minute\(model.settings.ipodMixMinutes == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                Slider(value: Binding(get: { Double(model.settings.ipodMixMinutes) },
                                      set: { model.settings.ipodMixMinutes = Int($0) }),
                       in: 5...180, step: 5)
                    .frame(width: 200)
                Stepper("Minutes", value: $model.settings.ipodMixMinutes, in: 5...180, step: 5)
                    .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Categories").font(.callout.weight(.medium))
                if options.isEmpty {
                    Text("No short videos yet.").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(options, id: \.key) { option in
                        CategoryChip(name: option.name, symbol: option.symbol, count: option.count,
                                     isOn: chosen.contains(option.key)) {
                            if chosen.contains(option.key) {
                                model.settings.ipodCategories.removeAll { $0 == option.key }
                            } else {
                                model.settings.ipodCategories.append(option.key)
                            }
                        }
                    }
                }
            }

            Divider()

            if exporter.kind == .mix {
                IPodProgressRow()
            } else {
            HStack {
                Text(chosen.isEmpty ? "Pick at least one category" : "\(unwatched) unwatched videos to pick from")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Export Mix", systemImage: "square.and.arrow.up") {
                    guard let folder = exportFolder else { return }
                    exporter.exportMix(libraries: libraries, minutes: model.settings.ipodMixMinutes,
                                       ipod: model.settings.ipodModel, to: folder, model: model)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!folderOK || exporter.isRunning || libraries.allSatisfy(\.videos.isEmpty))
                .grayscale(folderOK ? 0 : 1)
            }
            }
        }
        .card()
    }

    private var longCard: some View {
        let videos = pickedVideos
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SettingsIcon(symbol: "play.rectangle.fill", tint: .logoRed, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(videos.isEmpty ? "No videos picked" : videos.count == 1 ? "1 video picked" : "\(videos.count) videos picked")
                        .font(.body.weight(.medium))
                    Text(videos.isEmpty ? "Pick from your long videos, by creator"
                         : videos.prefix(3).map(\.displayTitle).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button("Select…") { choosingLong = true }
                    .disabled(model.longLibraries.allSatisfy(\.videos.isEmpty))
                Button("Export", systemImage: "square.and.arrow.up") {
                    guard let folder = exportFolder else { return }
                    exporter.exportLong(videos, ipod: model.settings.ipodModel, to: folder, model: model)
                    pickedLong = []
                }
                .buttonStyle(.borderedProminent)
                .disabled(!folderOK || exporter.isRunning || videos.isEmpty)
                .grayscale(folderOK ? 0 : 1)
            }
            if exporter.kind == .long {
                Divider()
                IPodProgressRow()
            }
        }
        .card()
    }

    // MARK: Data

    private struct MixOption {
        let key: String
        let name: String
        let symbol: String
        let count: Int
    }

    /// The categories with short videos, and Other Creators for those in none.
    private var mixOptions: [MixOption] {
        var options = model.categories.compactMap { category -> MixOption? in
            let libs = model.mixLibraries(.short, in: category.id)
            guard !libs.isEmpty else { return nil }
            return MixOption(key: category.id.uuidString, name: category.name, symbol: category.symbol,
                             count: libs.reduce(0) { $0 + $1.videos.count { !model.isPlayed($0) } })
        }
        let other = model.uncategorizedWatchLibraries(.short)
        if !other.isEmpty {
            options.append(MixOption(key: otherCard, name: "Other Creators", symbol: "person.2.fill",
                                     count: other.reduce(0) { $0 + $1.videos.count { !model.isPlayed($0) } }))
        }
        return options
    }

    private var mixLibraries: [CreatorLibrary] {
        model.mixLibraries(.short, picked: Set(model.settings.ipodCategories))
    }

    private var pickedVideos: [Video] {
        let all = Dictionary(model.longLibraries.flatMap(\.videos).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return pickedLong.compactMap { all[$0] }
    }

    private var exportFolder: URL? {
        model.settings.ipodExportPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private var folderProblem: String {
        model.settings.ipodExportPath == nil ? "Choose a folder to export to."
            : "That folder isn't there anymore (or can't be written to). Choose another, or plug its drive back in."
    }

    private func checkFolder() {
        var isDirectory: ObjCBool = false
        guard let path = model.settings.ipodExportPath,
              FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: path) else {
            folderOK = false
            return
        }
        folderOK = true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where iPod videos are saved"
        if let path = model.settings.ipodExportPath { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.ipodExportPath = url.path
        }
        checkFolder()
    }
}

/// Which iPod: its picture, name and what an export looks like, the whole card a choice, lit while chosen.
private struct IPodTile: View {
    let ipod: IPodModel
    let isOn: Bool
    let choose: () -> Void

    var body: some View {
        Button { withAnimation(.snappy(duration: 0.2), choose) } label: {
            HStack(spacing: 12) {
                IPodGlyph(model: ipod, height: 40)
                    .frame(width: 40, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ipod.name).font(.body.weight(.medium))
                    Text(ipod.generation).font(.caption).foregroundStyle(.secondary)
                    Text("Mix: \(ipod.mixSizeLabel)").font(.caption2).foregroundStyle(.tertiary)
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

/// A category to put in the mix: its symbol, name and unwatched count, as a capsule toggle.
private struct CategoryChip: View {
    let name: String
    let symbol: String
    let count: Int
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : symbol)
                    .foregroundStyle(isOn ? Color.white : Color.accentColor)
                    .contentTransition(.symbolEffect(.replace))
                Text(name).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(isOn ? Color.white.opacity(0.8) : Color.secondary)
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Progress

/// The running export's bar with a spinner, how far along it is and about how long is left. Spins on its own while
/// there's no telling yet (picking the mix's videos).
struct IPodProgressBar: View {
    @State private var exporter = IPodExporter.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if exporter.encodingStarted == nil {
                    ProgressView().progressViewStyle(.linear)
                } else {
                    ProgressView(value: exporter.progress)
                        .animation(.easeOut(duration: 0.4), value: exporter.progress)
                }
                Text(status(at: context.date))
                    .font(.caption.weight(.medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iPod export progress")
    }

    private func status(at now: Date) -> String {
        guard exporter.encodingStarted != nil else { return "" }
        let percent = "\(Int(exporter.progress * 100))%"
        guard let left = exporter.timeLeft(at: now) else { return percent }
        let minutes = Int((left / 60).rounded(.up))
        return percent + (left < 60 ? " · under a minute left" : " · about \(minutes) min left")
    }
}

/// Progress inside the card that started the export: the bar, what it's on, and Stop.
private struct IPodProgressRow: View {
    @State private var exporter = IPodExporter.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                IPodProgressBar()
                Text(exporter.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Button("Stop") { exporter.cancel() }
        }
    }
}

/// The sidebar's bar while an iPod export runs, like the download bar, so it can be followed with Settings closed.
struct SidebarIPodBar: View {
    @State private var exporter = IPodExporter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "ipod").foregroundStyle(.pink)
                IPodProgressBar()
                Button { exporter.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                .help("Stop the iPod export")
                .accessibilityLabel("Stop")
            }
            Text(exporter.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

// MARK: - Long video chooser

/// Every long video, grouped by creator, to pick one or more to export. Clicking a row picks it or drops it.
private struct LongVideoChooser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var picked: [String]
    @State private var search = ""

    var body: some View {
        let chosen = Set(picked)
        VStack(spacing: 0) {
            HStack {
                Text("Choose Long Videos").font(.headline)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(16)
            Divider()
            List {
                ForEach(groups, id: \.0.id) { library, videos in
                    Section {
                        ForEach(videos) { video in
                            row(video, isOn: chosen.contains(video.id))
                        }
                    } header: {
                        HStack(spacing: 8) {
                            AvatarView(library: library, size: 20)
                            Text(library.displayName)
                            Spacer()
                            let ids = videos.map(\.id)
                            Button(ids.allSatisfy(chosen.contains) ? "None" : "All") {
                                if ids.allSatisfy(chosen.contains) {
                                    picked.removeAll { ids.contains($0) }
                                } else {
                                    picked += ids.filter { !chosen.contains($0) }
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                }
            }
            .listStyle(.inset)
            Divider()
            HStack {
                Text(picked.isEmpty ? "Nothing picked" : picked.count == 1 ? "1 video picked" : "\(picked.count) videos picked")
                    .foregroundStyle(.secondary)
                Spacer()
                if !picked.isEmpty {
                    Button("Clear") { picked = [] }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 600)
    }

    private var groups: [(CreatorLibrary, [Video])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return model.longLibraries.compactMap { library in
            let videos = query.isEmpty ? library.videos
                : library.videos.filter { $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || library.displayName.localizedCaseInsensitiveContains(query) }
            return videos.isEmpty ? nil : (library, videos)
        }
    }

    private func row(_ video: Video, isOn: Bool) -> some View {
        Button {
            if isOn { picked.removeAll { $0 == video.id } } else { picked.append(video.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
                LongThumbnail(video: video, cornerRadius: 6)
                    .frame(width: 112)
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.displayTitle).lineLimit(2)
                    Text(video.date.formatted(date: .abbreviated, time: .omitted)
                         + (model.isPlayed(video) ? " · Watched" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glyphs

/// The chosen iPod, drawn.
struct IPodGlyph: View {
    let model: IPodModel
    var height: CGFloat

    var body: some View {
        switch model {
        case .nano7: IPodNanoGlyph(height: height)
        case .classic: IPodClassicGlyph(height: height)
        }
    }
}

/// An iPod classic (6th generation): a silver aluminum front, the screen in its top half showing a menu with one row
/// lit, and the click wheel with MENU and the play marks around a center button.
struct IPodClassicGlyph: View {
    var height: CGFloat = 44

    var body: some View {
        let w = height * 0.6
        let u = height / 100
        ZStack(alignment: .top) {
            // Body: brushed silver with a chrome-ish edge.
            RoundedRectangle(cornerRadius: 9 * u, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: 9 * u, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.55)], startPoint: .top, endPoint: .bottom),
                                      lineWidth: max(0.6, 1.4 * u))
                }
            VStack(spacing: 7 * u) {
                // Screen: a black bezel and a lit menu.
                ZStack {
                    RoundedRectangle(cornerRadius: 2.5 * u).fill(Color(white: 0.1))
                    VStack(spacing: 2.6 * u) {
                        Capsule().fill(Color(white: 0.85)).frame(height: 2.6 * u).padding(.horizontal, 4 * u)
                        Rectangle().fill(LinearGradient(colors: [Color(red: 0.4, green: 0.7, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.9)],
                                                        startPoint: .top, endPoint: .bottom))
                            .frame(height: 5 * u)
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(Color(white: 0.85).opacity(0.75)).frame(height: 2.2 * u).padding(.horizontal, 4 * u)
                        }
                    }
                    .padding(.horizontal, 2 * u)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 3 * u)
                    .background(LinearGradient(colors: [.white, Color(white: 0.85)], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 1.2 * u))
                    .padding(1.6 * u)
                }
                .frame(width: w * 0.78, height: 36 * u)
                // Click wheel.
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                        .overlay { Circle().strokeBorder(Color(white: 0.6), lineWidth: max(0.5, 0.8 * u)) }
                    if height >= 50 {
                        Text("MENU").font(.system(size: 4.6 * u, weight: .bold)).foregroundStyle(Color(white: 0.55))
                            .offset(y: -13.5 * u)
                        Image(systemName: "playpause.fill").font(.system(size: 4.6 * u)).foregroundStyle(Color(white: 0.55))
                            .offset(y: 13.5 * u)
                        Image(systemName: "backward.end.alt.fill").font(.system(size: 4.6 * u)).foregroundStyle(Color(white: 0.55))
                            .offset(x: -13.5 * u)
                        Image(systemName: "forward.end.alt.fill").font(.system(size: 4.6 * u)).foregroundStyle(Color(white: 0.55))
                            .offset(x: 13.5 * u)
                    }
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
                        .overlay { Circle().strokeBorder(Color(white: 0.6), lineWidth: max(0.5, 0.7 * u)) }
                        .frame(width: 13 * u, height: 13 * u)
                }
                .frame(width: 40 * u, height: 40 * u)
            }
            .padding(.top, 7 * u)
        }
        .frame(width: w, height: height)
        .accessibilityHidden(true)
    }
}

/// An iPod nano (7th generation): tall and thin, a pink aluminum edge around a white face, a big screen of round app
/// icons and the small home button under it.
struct IPodNanoGlyph: View {
    var height: CGFloat = 44

    private static let icons: [Color] = [
        Color(red: 1, green: 0.3, blue: 0.35), Color(red: 0.25, green: 0.6, blue: 1),
        Color(red: 0.25, green: 0.8, blue: 0.4), Color(red: 1, green: 0.65, blue: 0.1),
        Color(red: 0.7, green: 0.35, blue: 1), Color(red: 0.15, green: 0.8, blue: 0.85),
    ]

    var body: some View {
        let w = height * 0.52
        let u = height / 100
        ZStack {
            // The colored aluminum edge.
            RoundedRectangle(cornerRadius: 7 * u, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.5, blue: 0.7), Color(red: 0.85, green: 0.25, blue: 0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // The white glass face.
            RoundedRectangle(cornerRadius: 6 * u, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.93)], startPoint: .top, endPoint: .bottom))
                .padding(1.6 * u)
            VStack(spacing: 4.5 * u) {
                // Screen with a 2×3 grid of round icons, as on the nano's home screen.
                ZStack {
                    RoundedRectangle(cornerRadius: 1.5 * u)
                        .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.05, green: 0.05, blue: 0.1)],
                                             startPoint: .top, endPoint: .bottom))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 3 * u), GridItem(.flexible(), spacing: 3 * u)],
                              spacing: 4 * u) {
                        ForEach(Self.icons.indices, id: \.self) { i in
                            Circle().fill(Self.icons[i].gradient).frame(width: 13 * u, height: 13 * u)
                        }
                    }
                    .padding(.horizontal, 6 * u)
                }
                .frame(width: w * 0.8, height: 66 * u)
                // Home button: a ring with a rounded square in it.
                Circle()
                    .strokeBorder(Color(white: 0.7), lineWidth: max(0.5, 0.9 * u))
                    .frame(width: 11 * u, height: 11 * u)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1 * u).strokeBorder(Color(white: 0.7), lineWidth: max(0.4, 0.6 * u))
                            .frame(width: 4 * u, height: 4 * u)
                    }
            }
            .padding(.top, 2 * u)
        }
        .frame(width: w, height: height)
        .accessibilityHidden(true)
    }
}
