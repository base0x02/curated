import CryptoKit
import Foundation

/// What the phone app talks to. Every route except /info and /pair needs "Authorization: Bearer <token>",
/// and a token is only handed out by /pair while the Mac is showing a pairing code.
///
///   GET  /info                  name, API version and "addresses": this Mac's IPv4 addresses, wired first, comma-separated (no auth)
///   POST /pair                  {"code", "deviceName"} → {"token", "deviceID", "macName"}
///   GET  /manifest              creators, categories and every downloaded short video
///   GET  /manifest?forms=short,long   (API 2) the forms asked for: "short", "long" or both. Long videos come with
///                               "form": "long", a title and a description; creators say if they're a playlist
///   GET  /manifest?forms=short,long&vine=1   (API 3) also the Vines, while Vine is on: short videos under made-up
///                               creators ("vine@<Vine user ID>", with "vine": true), and "vineCategories", the
///                               categories whose Automix mixes them in. Phones that don't ask never see them
///   GET  /video/<id>            the video file, short or long (supports Range)
///   GET  /poster/<id>           a long video's thumbnail (JPEG), if it has one
///   GET  /avatar/<creator id>   the creator's avatar (the id is the TikTok username, or "youtube@<handle>")
///   POST /played                {"marks": {id: {played, at}}, "watchLater"?: {id: {saved, at}}, "bookmarks"?: {id: {saved, at}}}
///                               → the merged {"marks", "watchLater", "bookmarks"} (the last two are optional for older phones)
///   POST /positions             (API 4) {"positions": {id: {seconds?, at}}} → the merged {"positions"}: where long videos
///                               were left off, newest wins. No "seconds" means it was cleared. Its own route because
///                               phones call it each time they open or leave a video, and it's small
///                               API 5 also swaps "nowPlaying"; API 8 also "playback" (`PlaybackRules`: which categories
///                               Automix leaves out or keep to 1×, the time limit), newest wins
///   POST /download              (API 6) Force Download: starts a total download, as Download All Now does → {"started", "message"}.
///                               The manifest's "lastDownloadAt" says when a download last finished
///   GET  /download/progress     (API 7) server-sent events, one a second: {"downloading", "progress"?, "done"?, "total"?, "current"?,
///                               "lastDownloadAt"?}. The Mac closes the connection after the first with "downloading": false, so
///                               with nothing downloading it's one event. Not the overnight job's runs, which are another process
///   GET  /creators/form         (API 10) the add-creator form, as data: {"version", "fields"} (`CreatorForm`). A phone draws what's there
///   POST /creators              (API 10) {"formVersion", "values": {key: string}} → {"added", "message", "creatorID"?, "fieldErrors"?, "formChanged"?}.
///                               Checked against the form: a wrong version or an unknown key adds nothing and says formChanged
///   GET  /creators/<id>/older   (API 10) server-sent events of the long videos not downloaded yet: {"videos", "done", "error"?}. Leaving stops the listing
///   POST /creators/<id>/older   (API 10) {"ids", "skip"?, "heights"?: {id: height, 0 for Best}} → {"ok", "started", "message"}
///   GET  /older-thumbnail/<id>  (API 10) a video's YouTube thumbnail, through the Mac
extension AppModel {
    /// 2: long videos (manifest `forms`, `/poster`). 3: Vines (manifest `vine`). Phones from before them ask for
    /// neither and get what they always did. 4: `/positions`. 5: its `nowPlaying`. 6: `/download`, `lastDownloadAt`.
    /// 7: `/download/progress`. 8: `/positions`' `playback`. 9: videos' `pickedAt`.
    /// 10: `/creators/form`, `/creators`, `/creators/<id>/older`, `/older-thumbnail/<id>`.
    static let syncAPIVersion = 10
    static let pairingDuration: TimeInterval = 300
    private static let maxFailedPairings = 5

    var syncServiceName: String { "Curated on \(SyncServer.computerName)" }

    /// Starts or stops the server and the Bonjour advertisement to match Settings.
    func updateSyncServer() {
        guard settings.syncEnabled else {
            syncServer?.stop()
            syncServer = nil
            syncError = nil
            endPairing()
            updateUsbSync()
            return
        }
        if syncServer == nil {
            syncError = nil
            let server = SyncServer { [weak self] request in
                await self?.handleSync(request) ?? .error(503, "Curated is closing")
            }
            server.start { [weak self] message in
                Task { @MainActor in self?.syncError = message }
            }
            syncServer = server
        }
        syncServer?.setAdvertised(settings.syncDiscoverable, name: syncServiceName)
        updateUsbSync()
    }

    // MARK: Pairing

    func startPairing(code: String? = nil) {
        guard settings.syncEnabled else { return }
        pairingCode = code ?? String(format: "%06d", Int.random(in: 0...999_999))
        pairingExpires = Date().addingTimeInterval(Self.pairingDuration)
        failedPairings = 0
        pairingTimeout?.cancel()
        pairingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pairingDuration))
            if !Task.isCancelled { self?.endPairing() }
        }
    }

    func endPairing() {
        pairingTimeout?.cancel()
        pairingTimeout = nil
        pairingCode = nil
        pairingExpires = nil
    }

    func removeSyncDevice(_ id: UUID) {
        syncDevices.removeAll { $0.id == id }
    }

    // MARK: Requests

    private struct PairRequest: Decodable {
        let code: String
        let deviceName: String
    }

    private struct PlayedPayload: Codable {
        let marks: [String: PlayedMark]
        var watchLater: [String: WatchLaterMark]?
        var bookmarks: [String: WatchLaterMark]?
    }

    private struct PositionsPayload: Codable {
        let positions: [String: PositionMark]
        var nowPlaying: NowPlayingMark?
        /// API 8: the playback rules and time limit, newest wins.
        var playback: PlaybackRules?
    }

    private struct Manifest: Encodable {
        struct CreatorInfo: Encodable {
            let username: String
            let nickname: String?
            let days: Int
            let category: UUID?
            let hasAvatar: Bool
            /// API 2: a YouTube playlist (its videos are long, in `order`).
            var playlist: Bool?
            /// API 2, playlists only: the video IDs in playlist order.
            var order: [String]?
            /// API 3: a Vine author. Their videos are short, and they have no category.
            var vine: Bool?
            /// API 10: a channel with long videos on, whose older videos can be asked for. Sent whether or not it has any.
            var longForm: Bool?
        }
        struct VideoInfo: Encodable {
            let id: String
            let creator: String
            let date: Date
            let caption: String
            let duration: Double?
            let viewCount: Int?
            let size: Int
            let fileExtension: String
            /// API 2, long videos only: "long", the title and the description (the caption is the description, or
            /// the title when there's none), and whether a poster is at /poster/<id>.
            var form: String?
            var title: String?
            var details: String?
            var hasPoster: Bool?
            /// API 9, long videos picked by hand from a creator's older videos: when. They come first until watched.
            var pickedAt: Date?
        }
        let macName: String
        let generatedAt: Date
        let timeLimitMinutes: Int
        let categories: [Category]
        let creators: [CreatorInfo]
        let videos: [VideoInfo]
        /// API 3, when Vines were asked for: the categories whose Automix also plays them.
        var vineCategories: [UUID]?
        /// API 6: when a download last finished, here or in the overnight job. Nil until the first one.
        var lastDownloadAt: Date?
    }

    private struct ForceDownloadReply: Encodable {
        let started: Bool
        let message: String
    }

    private struct DownloadProgressEvent: Encodable {
        let downloading: Bool
        /// 0 to 1, and how many of the run's creators are done, while downloading.
        var progress: Double?
        var done: Int?
        var total: Int?
        /// Who's downloading right now.
        var current: [String]?
        var lastDownloadAt: Date?
    }

    func handleSync(_ request: SyncRequest) -> SyncResponse {
        guard settings.syncEnabled else { return .error(503, "Sync is turned off on the Mac") }
        let parts = request.path.split(separator: "/").map(String.init)
        switch (request.method, parts.first ?? "") {
        case ("GET", "info"):
            return json(["name": syncServiceName, "api": "\(Self.syncAPIVersion)",
                         "addresses": SyncServer.localAddresses().joined(separator: ",")])
        case ("POST", "pair"):
            return pair(request)
        default:
            break
        }

        guard let device = authenticate(request) else { return .error(401, "This phone isn't paired") }
        switch (request.method, parts.first ?? "", parts.count) {
        case ("GET", "manifest", 1):
            if let i = syncDevices.firstIndex(where: { $0.id == device.id }) { syncDevices[i].lastSync = Date() }
            let forms = Set((request.query["forms"] ?? "short").split(separator: ",").compactMap { VideoForm(rawValue: String($0)) })
            return json(manifest(forms: forms.isEmpty ? [.short] : forms, vine: request.query["vine"] == "1"))
        case ("GET", "video", 2):
            guard let video = (libraries + longLibraries + vineLibraries).lazy.flatMap(\.videos).first(where: { $0.id == parts[1] }) else {
                return .error(404, "No such video")
            }
            return .file(video.url, contentType: video.url.pathExtension.lowercased() == "mov" ? "video/quicktime" : "video/mp4")
        case ("GET", "poster", 2):
            guard let video = longLibraries.lazy.flatMap(\.videos).first(where: { $0.id == parts[1] }),
                  FileManager.default.fileExists(atPath: video.posterURL.path) else { return .error(404, "No poster") }
            return .file(video.posterURL, contentType: "image/jpeg")
        case ("GET", "avatar", 2):
            guard let avatar = library(for: parts[1])?.avatar else { return .error(404, "No avatar") }
            return .file(avatar, contentType: "image/jpeg")
        case ("POST", "played", 1):
            guard let payload = try? Self.decoder.decode(PlayedPayload.self, from: request.body) else {
                return .error(400, "Expected {\"marks\": {...}}")
            }
            return json(PlayedPayload(marks: mergePlayed(payload.marks),
                                      watchLater: mergeWatchLater(payload.watchLater ?? [:]),
                                      bookmarks: mergeBookmarks(payload.bookmarks ?? [:])))
        case ("POST", "positions", 1):
            guard let payload = try? Self.decoder.decode(PositionsPayload.self, from: request.body) else {
                return .error(400, "Expected {\"positions\": {...}}")
            }
            let positions = mergePositions(payload.positions)
            return json(PositionsPayload(positions: positions, nowPlaying: mergeNowPlaying(payload.nowPlaying),
                                         playback: mergePlaybackRules(payload.playback)))
        case ("GET", "creators", 2) where parts[1] == "form":
            return json(creatorForm())
        case ("POST", "creators", 1):
            return addCreator(from: request, device: device)
        case ("GET", "creators", 3) where parts[2] == "older":
            return olderVideos(of: parts[1])
        case ("POST", "creators", 3) where parts[2] == "older":
            return requestOlderVideos(of: parts[1], from: request, device: device)
        case ("GET", "older-thumbnail", 2):
            return olderThumbnail(parts[1])
        case ("POST", "download", 1):
            return json(forceDownload(for: device))
        case ("GET", "download", 2) where parts[1] == "progress":
            let deviceID = device.id
            return .events { [weak self] in await self?.downloadProgressEvent(for: deviceID) ?? (Data(), true) }
        default:
            return .error(404, "Not found")
        }
    }

    /// The next event of a phone's /download/progress. Also the last, if sync was turned off or the phone removed.
    private func downloadProgressEvent(for deviceID: UUID) -> (event: Data, last: Bool) {
        let downloading = isDownloading && settings.syncEnabled && syncDevices.contains { $0.id == deviceID }
        // From the file, like the manifest's. It's written before isDownloading goes false, so the last event has it.
        var progress = DownloadProgressEvent(downloading: downloading, lastDownloadAt: RunState.load().lastRun)
        if downloading {
            progress.progress = downloadProgress
            progress.done = downloadUnitsDone
            progress.total = downloadUnits
            progress.current = statuses.filter { $0.value == .downloading }.keys.map { id in
                if id == Vine.feedID { return "Vines" }
                return library(for: id)?.displayName ?? library(for: id, form: .long)?.displayName ?? id
            }.sorted()
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = (try? encoder.encode(progress)) ?? Data("{}".utf8)
        return (Data("data: ".utf8) + body + Data("\n\n".utf8), !downloading)
    }

    /// A phone's Force Download. Starts what Download All Now does, unless something's in the way.
    private func forceDownload(for device: SyncDevice) -> ForceDownloadReply {
        if isDownloading {
            return ForceDownloadReply(started: false, message: "Your Mac is already downloading.")
        }
        // Starting a download now would throw away what's been picked there.
        if longPick != nil {
            return ForceDownloadReply(started: false, message: "The long-video picker is open on your Mac. Close it and try again.")
        }
        if config.creators.isEmpty && !settings.vineEnabled {
            return ForceDownloadReply(started: false, message: "Your Mac has no creators to download.")
        }
        downloadAll()
        // Still not downloading: the overnight job holds the lock, and downloadMessage says so.
        guard isDownloading else {
            return ForceDownloadReply(started: false, message: downloadMessage ?? "Your Mac couldn't start the download.")
        }
        DownloadLog.info("Force Download asked for by \(device.name)")
        return ForceDownloadReply(started: true, message: "Your Mac started downloading.")
    }

    private func pair(_ request: SyncRequest) -> SyncResponse {
        guard let code = pairingCode, let expires = pairingExpires, expires > Date() else {
            return .error(403, "Pairing isn't open. On the Mac, click the sync button and choose Pair a Phone.")
        }
        guard let body = try? Self.decoder.decode(PairRequest.self, from: request.body) else {
            return .error(400, "Expected {\"code\", \"deviceName\"}")
        }
        guard Self.constantTimeEqual(body.code, code) else {
            failedPairings += 1
            if failedPairings >= Self.maxFailedPairings { endPairing() }
            return .error(403, "Wrong code")
        }
        let token = Self.makeToken()
        let name = body.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = SyncDevice(name: name.isEmpty ? "Phone" : String(name.prefix(60)),
                                tokenHash: Self.hash(token), pairedAt: Date())
        syncDevices.append(device)
        endPairing()
        return json(["token": token, "deviceID": device.id.uuidString, "macName": syncServiceName])
    }

    private func authenticate(_ request: SyncRequest) -> SyncDevice? {
        guard let header = request.headers["authorization"], header.lowercased().hasPrefix("bearer ") else { return nil }
        let hash = Self.hash(String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces))
        return syncDevices.first { Self.constantTimeEqual($0.tokenHash, hash) }
    }

    /// The videos of `forms`: short ones from creators with Shorts on (`watchLibraries(.short)`), long ones from
    /// creators with long videos on, and playlists. A creator with both is listed once. Each video is sent once: one
    /// that's also in a playlist comes under its creator, and the playlist lists it in its `order`. With `vine`, the
    /// Vines come along with the short videos.
    private func manifest(forms: Set<VideoForm>, vine: Bool = false) -> Manifest {
        let vines = vine && forms.contains(.short) ? vineLibraries : []
        let short = (forms.contains(.short) ? watchLibraries(.short) : []) + vines
        // Creators before playlists, so a video in both is sent as the creator's.
        let long = forms.contains(.long) ? longLibraries.filter { !$0.creator.playlist } + playlistLibraries : []
        var creators: [Manifest.CreatorInfo] = []
        var listed: Set<String> = []
        for library in short + long where listed.insert(library.creator.id).inserted {
            let creator = library.creator
            // The avatar lives in the creator's main folder, which the short scan reads even for long-only creators.
            let avatar = self.library(for: creator.id)?.avatar ?? library.avatar
            creators.append(Manifest.CreatorInfo(
                username: creator.id, nickname: library.nickname, days: creator.days,
                category: category(creator.category)?.id, hasAvatar: avatar != nil,
                playlist: creator.playlist ? true : nil,
                order: creator.playlist ? library.videos.map(\.id) : nil,
                vine: creator.platform == .vine ? true : nil,
                longForm: creator.canPickOlderLong ? true : nil))
        }
        var sent: Set<String> = []
        let videos = (short + long).flatMap(\.videos).filter { sent.insert($0.id).inserted }.map { video in
            let isLong = video.form == .long
            return Manifest.VideoInfo(id: video.id, creator: video.creator, date: video.date, caption: video.caption,
                                      duration: duration(of: video), viewCount: video.viewCount, size: Int(video.size),
                                      fileExtension: video.url.pathExtension.lowercased(),
                                      form: isLong ? "long" : nil,
                                      title: isLong ? video.title : nil, details: isLong ? video.details : nil,
                                      hasPoster: isLong ? FileManager.default.fileExists(atPath: video.posterURL.path) : nil,
                                      pickedAt: isLong ? handPicked[video.id] : nil)
        }
        return Manifest(macName: syncServiceName, generatedAt: Date(), timeLimitMinutes: settings.timeLimitMinutes,
                        categories: categories, creators: creators, videos: videos,
                        vineCategories: vine ? categories.filter { Vine.categoryNames.contains($0.name.lowercased()) }.map(\.id) : nil,
                        // From the file, since the overnight job writes it from another process.
                        lastDownloadAt: RunState.load().lastRun)
    }

    // MARK: Helpers

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func json(_ value: some Encodable) -> SyncResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return .error(500, "Couldn't encode response") }
        return .json(data)
    }

    private static func makeToken() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let a = Array(a.utf8), b = Array(b.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
