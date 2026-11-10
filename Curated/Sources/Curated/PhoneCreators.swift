import Foundation

// What a phone can ask the Mac to do with creators: add one, and see and download a creator's older long videos. The
// form is described here and drawn by the phone, so a phone only ever offers what this Mac understands, and the same
// description checks what comes back.

/// The add-creator form as the phone draws it. Every value is a string on the wire: "true"/"false", a number's digits, a
/// choice's `value`.
struct CreatorForm: Encodable {
    struct Choice: Encodable {
        let value: String
        let label: String
    }

    /// Part of a field's `showIf`.
    struct Condition: Encodable {
        let field: String
        /// True when the field's value is one of these.
        var equals: [String]? = nil
        /// True when the field's value matches this regular expression, ignoring case.
        var matches: String? = nil
        /// The opposite of the above.
        var negate: Bool? = nil
    }

    struct Field: Encodable {
        let key: String
        /// "text", "choice", "toggle" or "number". A phone skips a type it doesn't know, unless it's `required`.
        let type: String
        let label: String
        var detail: String? = nil
        var placeholder: String? = nil
        var required: Bool? = nil
        var choices: [Choice]? = nil
        var min: Int? = nil
        var max: Int? = nil
        var defaultValue: String? = nil
        /// Shown when every condition of any one group holds; always shown without it. Hidden fields aren't sent.
        var showIf: [[Condition]]? = nil

        enum CodingKeys: String, CodingKey {
            case key, type, label, detail, placeholder, required, choices, min, max, showIf
            case defaultValue = "default"
        }
    }

    /// Change this when a field's meaning changes: a phone holding an older copy is told to fetch the form again.
    static let currentVersion = 1

    let version: Int
    let fields: [Field]
}

/// One `GET /creators/<id>/older` event.
private struct OlderVideosEvent: Encodable {
    struct Entry: Encodable {
        let id: String
        var title: String?
        var date: Date?
        var duration: Int?
    }

    var videos: [Entry] = []
    var done = false
    var error: String?
}

/// The videos listed for a phone that it hasn't been sent yet. When the phone goes, this is released, which stops yt-dlp.
private final class OlderVideosListing: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [PendingVideo] = []
    private var finished = false
    private var error: String?
    private let runner: ProcessRunner

    init(runner: ProcessRunner) { self.runner = runner }
    deinit { runner.cancel() }

    func add(_ videos: [PendingVideo]) { lock.withLock { waiting += videos } }

    func finish(error: String?) {
        lock.withLock {
            finished = true
            self.error = error
        }
    }

    func take() -> (videos: [PendingVideo], finished: Bool, error: String?) {
        lock.withLock {
            defer { waiting = [] }
            return (waiting, finished, error)
        }
    }
}

extension AppModel {
    // MARK: Adding a creator

    /// YouTube and TikTok links pick their own platform, as in Creators & Downloads.
    private static let linkPattern = #"(youtube\.com|youtu\.be|tiktok\.com)/"#
    private static let youTubeLinkPattern = #"(youtube\.com|youtu\.be)/"#
    /// As `Creator.playlistID` reads one.
    private static let playlistPattern = #"(youtube\.com|youtu\.be)/.*[?&]list=[A-Za-z0-9_-]{10,}"#

    /// What Creators & Downloads offers when adding a creator, and the minimum views and resolution on its row.
    func creatorForm() -> CreatorForm {
        typealias Condition = CreatorForm.Condition
        typealias Choice = CreatorForm.Choice
        let notPlaylist = Condition(field: "input", matches: Self.playlistPattern, negate: true)
        let playlist = Condition(field: "input", matches: Self.playlistPattern)
        // A channel, not a playlist: picked below, or by its link.
        let youTubeChannel = [[Condition(field: "platform", equals: ["youtube"]), Condition(field: "input", matches: Self.linkPattern, negate: true), notPlaylist],
                              [Condition(field: "input", matches: Self.youTubeLinkPattern), notPlaylist]]
        let byCount = Condition(field: "keepMode", equals: ["videos"])
        let keepVideos = UserDefaults.standard.integer(forKey: "newCreatorKeepVideos")
        let historical = UserDefaults.standard.bool(forKey: "newCreatorKeepHistorical")
        var fields: [CreatorForm.Field] = [
            .init(key: "input", type: "text", label: "Creator",
                  detail: "A username, or a TikTok, YouTube channel or YouTube playlist link.",
                  placeholder: "@username or a link", required: true),
            .init(key: "platform", type: "choice", label: "Platform",
                  choices: [Choice(value: "tiktok", label: "TikTok"), Choice(value: "youtube", label: "YouTube")],
                  defaultValue: "tiktok", showIf: [[Condition(field: "input", matches: Self.linkPattern, negate: true)]]),
            .init(key: "shorts", type: "toggle", label: "Shorts", defaultValue: "true", showIf: youTubeChannel),
            .init(key: "longForm", type: "toggle", label: "Long Videos", defaultValue: "false", showIf: youTubeChannel),
            .init(key: "keepMode", type: "choice", label: "Keep",
                  detail: "Long videos always use the days, and stay until you watch or delete them.",
                  choices: [Choice(value: "days", label: "Last Few Days"), Choice(value: "videos", label: "Newest Unwatched")],
                  defaultValue: keepVideos > 0 ? "videos" : "days",
                  showIf: [[notPlaylist]]),
            .init(key: "days", type: "number", label: "Days to Look Back", min: 1, max: 365,
                  defaultValue: "\(max(1, settings.defaultDays))", showIf: [[notPlaylist]]),
            .init(key: "keepVideos", type: "number", label: "Unwatched Videos to Keep", min: 1, max: 100,
                  defaultValue: "\(keepVideos > 0 ? keepVideos : 5)", showIf: [[byCount, notPlaylist]]),
            .init(key: "keepHistorical", type: "toggle", label: "Historical",
                  detail: "When there aren't enough new videos, also download older ones not yet downloaded.",
                  defaultValue: historical ? "true" : "false", showIf: [[byCount, notPlaylist]]),
        ]
        if !categories.isEmpty {
            fields.append(.init(key: "category", type: "choice", label: "Category",
                                choices: [Choice(value: "", label: "None")] + categories.map { Choice(value: $0.id.uuidString, label: $0.name) },
                                defaultValue: "", showIf: [[notPlaylist]]))
        }
        fields += [
            .init(key: "minViews", type: "choice", label: "Minimum Views",
                  choices: [Choice(value: "", label: "All Videos")] + MinViewsPicker.presets.map { Choice(value: "\($0)", label: "\(compactViews($0))+ views") },
                  defaultValue: "", showIf: [[notPlaylist]]),
            .init(key: "longFormHeight", type: "choice", label: "Long Video Resolution",
                  choices: [Choice(value: "", label: "Best")] + Creator.longFormHeights.map { Choice(value: "\($0)", label: "Up to \($0)p") },
                  defaultValue: "", showIf: youTubeChannel.map { $0 + [Condition(field: "longForm", equals: ["true"])] } + [[playlist]]),
            .init(key: "playlistLimit", type: "choice", label: "Playlist Videos",
                  choices: [Choice(value: "", label: "All Videos")] + Creator.playlistLimits.map { Choice(value: "\($0)", label: "Newest \($0)") },
                  defaultValue: "", showIf: [[playlist]]),
        ]
        return CreatorForm(version: CreatorForm.currentVersion, fields: fields)
    }

    private struct AddCreatorRequest: Decodable {
        let formVersion: Int
        let values: [String: String]
    }

    struct AddCreatorReply: Encodable {
        var added = false
        var message: String
        var creatorID: String?
        /// What's wrong with each field, by its key.
        var fieldErrors: [String: String]?
        /// The form this came from isn't this Mac's any more: fetch it again.
        var formChanged: Bool?
    }

    /// `POST /creators`: checks the values against the form, then adds the creator as Creators & Downloads would.
    func addCreator(from request: SyncRequest, device: SyncDevice) -> SyncResponse {
        guard let body = try? JSONDecoder().decode(AddCreatorRequest.self, from: request.body) else {
            return .error(400, "Expected {\"formVersion\", \"values\"}")
        }
        func reply(_ reply: AddCreatorReply) -> SyncResponse {
            .json((try? JSONEncoder().encode(reply)) ?? Data("{}".utf8))
        }
        guard body.formVersion == CreatorForm.currentVersion else {
            return reply(AddCreatorReply(message: "The form on your Mac has changed. Check it and try again.", formChanged: true))
        }
        let form = creatorForm()
        let values = body.values
        var errors = Self.problems(with: values, in: form)
        // Nothing to look at on the phone for these, so they're not fields' errors.
        let unknown = values.keys.filter { key in !form.fields.contains { $0.key == key } }.sorted()
        if !unknown.isEmpty {
            return reply(AddCreatorReply(message: "Your Mac doesn't know \(unknown.joined(separator: ", ")). Nothing was added.", formChanged: true))
        }
        let input = (values["input"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaylist = Creator.playlistID(in: input) != nil
        let platform: Platform = input.range(of: Self.youTubeLinkPattern, options: [.regularExpression, .caseInsensitive]) != nil ? .youtube
            : input.range(of: "tiktok\\.com/", options: [.regularExpression, .caseInsensitive]) != nil ? .tiktok
            : values["platform"] == "youtube" ? .youtube : .tiktok
        let shorts = values["shorts"] != "false", longForm = values["longForm"] == "true"
        if platform == .youtube, !isPlaylist, !shorts, !longForm, errors["shorts"] == nil {
            errors["shorts"] = "Turn on Shorts, long videos or both."
        }
        guard errors.isEmpty else {
            return reply(AddCreatorReply(message: "Check the fields marked below. Nothing was added.", fieldErrors: errors))
        }
        var keep = KeepRule(days: values["days"].flatMap(Int.init) ?? settings.defaultDays)
        if values["keepMode"] == "videos" {
            keep.videos = values["keepVideos"].flatMap(Int.init)
            keep.historical = values["keepHistorical"] == "true"
        }
        let before = Set(config.creators.map(\.id))
        if let problem = addCreator(input, platform: platform, keep: keep,
                                    category: values["category"].flatMap(UUID.init(uuidString:)),
                                    shorts: shorts, longForm: longForm,
                                    playlistLimit: values["playlistLimit"].flatMap(Int.init)) {
            return reply(AddCreatorReply(message: problem, fieldErrors: ["input": problem]))
        }
        guard let i = config.creators.firstIndex(where: { !before.contains($0.id) }) else {
            return reply(AddCreatorReply(message: "Your Mac couldn't add that creator."))
        }
        if !isPlaylist { config.creators[i].minViews = values["minViews"].flatMap(Int.init) }
        if config.creators[i].downloadsLongForm { config.creators[i].longFormHeight = values["longFormHeight"].flatMap(Int.init) }
        reloadLibrary()
        let creator = config.creators[i]
        DownloadLog.info("\(device.name) added \(creator.id)")
        let name = creator.playlist ? "The playlist" : creator.platform == .youtube ? "@\(creator.username) on YouTube" : "@\(creator.username) on TikTok"
        return reply(AddCreatorReply(added: true, message: "\(name) is on your Mac. Its videos come with the next download.", creatorID: creator.id))
    }

    /// What's wrong with each value, by the form's own description of its field.
    private static func problems(with values: [String: String], in form: CreatorForm) -> [String: String] {
        var errors: [String: String] = [:]
        for field in form.fields {
            guard let value = values[field.key] else {
                if field.required == true { errors[field.key] = "\(field.label) is required." }
                continue
            }
            switch field.type {
            case "text":
                if field.required == true && value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors[field.key] = "\(field.label) is required."
                } else if value.count > 500 {
                    errors[field.key] = "That's too long."
                }
            case "toggle":
                if value != "true" && value != "false" { errors[field.key] = "Expected on or off." }
            case "number":
                let low = field.min ?? .min, high = field.max ?? .max
                guard let number = Int(value), (low...high).contains(number) else {
                    errors[field.key] = "Enter a number from \(low) to \(high)."
                    continue
                }
            case "choice":
                if !(field.choices ?? []).contains(where: { $0.value == value }) {
                    errors[field.key] = "That's not one of the choices on your Mac any more."
                }
            default:
                break
            }
        }
        return errors
    }

    // MARK: Older long videos

    /// A real video id goes straight into a URL for yt-dlp, so only what one can look like.
    private static func isVideoID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{6,20}$", options: .regularExpression) != nil
    }

    private func creatorForOlderVideos(_ id: String) -> Creator? {
        config.creators.first { $0.id == id && $0.canPickOlderLong }
    }

    /// `GET /creators/<id>/older`: the creator's long videos not downloaded yet as they're listed, as `pickOlderLong`.
    func olderVideos(of id: String) -> SyncResponse {
        guard let creator = creatorForOlderVideos(id) else { return .error(404, "That creator doesn't have long videos turned on.") }
        let runner = ProcessRunner()
        let listing = OlderVideosListing(runner: runner)
        let settings = config.settings
        let excluding = played.union((libraries + longLibraries).flatMap(\.videos).map(\.id))
        Task { [weak listing] in
            let error = await DownloadEngine.olderLong(creator, excluding: excluding, settings: settings, runner: runner, log: { _ in }) { @MainActor found in
                listing?.add(found)
            }
            listing?.finish(error: error)
        }
        return .events {
            try? await Task.sleep(for: .milliseconds(400))
            let (videos, finished, error) = listing.take()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let event = OlderVideosEvent(videos: videos.map { .init(id: $0.id, title: $0.title, date: $0.date, duration: $0.duration) },
                                         done: finished, error: error)
            let body = (try? encoder.encode(event)) ?? Data("{}".utf8)
            return (Data("data: ".utf8) + body + Data("\n\n".utf8), finished)
        }
    }

    private struct OlderVideosRequest: Decodable {
        var ids: [String] = []
        var skip: [String]?
        /// Resolutions other than the creator's, by video id. 0 is Best.
        var heights: [String: Int]?
    }

    struct OlderVideosReply: Encodable {
        var ok = false
        var started = false
        var message: String
    }

    /// `POST /creators/<id>/older`: downloads the picked videos and marks the skipped ones, as the picker's button does.
    func requestOlderVideos(of id: String, from request: SyncRequest, device: SyncDevice) -> SyncResponse {
        guard let body = try? JSONDecoder().decode(OlderVideosRequest.self, from: request.body) else {
            return .error(400, "Expected {\"ids\", \"skip\"?, \"heights\"?}")
        }
        func reply(_ reply: OlderVideosReply) -> SyncResponse {
            .json((try? JSONEncoder().encode(reply)) ?? Data("{}".utf8))
        }
        guard let creator = creatorForOlderVideos(id) else {
            return reply(OlderVideosReply(message: "That creator doesn't have long videos turned on on your Mac."))
        }
        let skip = body.skip ?? []
        let ids = Array(Set(body.ids).subtracting(skip))
        let heights = body.heights ?? [:]
        guard !ids.isEmpty || !skip.isEmpty else { return reply(OlderVideosReply(message: "No videos were picked.")) }
        guard (ids + skip + Array(heights.keys)).allSatisfy(Self.isVideoID), ids.count + skip.count <= 500 else {
            return reply(OlderVideosReply(message: "Your Mac couldn't read that list of videos. Nothing was downloaded."))
        }
        guard heights.values.allSatisfy({ $0 == 0 || Creator.longFormHeights.contains($0) }) else {
            return reply(OlderVideosReply(message: "Your Mac doesn't offer that resolution. Nothing was downloaded."))
        }
        if !ids.isEmpty {
            if isDownloading { return reply(OlderVideosReply(message: "Your Mac is already downloading. Try again when it finishes.")) }
            if longPick != nil { return reply(OlderVideosReply(message: "The long-video picker is open on your Mac. Close it and try again.")) }
        }
        guard !ids.isEmpty else {
            applySkipped(skip, for: creator)
            return reply(OlderVideosReply(ok: true, message: "Skipped \(skip.count) video\(skip.count == 1 ? "" : "s")."))
        }
        download([creator], forms: [.long], only: [creator.id: Set(ids)],
                 heights: heights.mapValues { $0 == 0 ? nil : Optional($0) })
        guard isDownloading else {
            return reply(OlderVideosReply(message: downloadMessage ?? "Your Mac couldn't start the download."))
        }
        applySkipped(skip, for: creator)
        markHandPicked(ids)
        DownloadLog.info("\(device.name) asked for \(ids.count) older video(s) from \(creator.id)")
        return reply(OlderVideosReply(ok: true, started: true,
                                      message: "Your Mac is downloading \(ids.count) video\(ids.count == 1 ? "" : "s"). Sync long videos once it's done to get them here."))
    }

    /// `GET /older-thumbnail/<id>`: a video's YouTube thumbnail, fetched here so the phone never talks to YouTube.
    func olderThumbnail(_ id: String) -> SyncResponse {
        guard Self.isVideoID(id), let source = URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") else {
            return .error(400, "That's not a video id")
        }
        return .deferred {
            // In the temporary folder, which macOS clears out by itself.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("curated-older-thumbnails", isDirectory: true)
            let file = folder.appendingPathComponent("\(id).jpg")
            if FileManager.default.fileExists(atPath: file.path) { return .file(file, contentType: "image/jpeg") }
            guard let (data, response) = try? await URLSession.shared.data(from: source),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return .error(404, "No thumbnail") }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? data.write(to: file, options: .atomic)) != nil else { return .error(500, "Couldn't save the thumbnail") }
            return .file(file, contentType: "image/jpeg")
        }
    }
}
