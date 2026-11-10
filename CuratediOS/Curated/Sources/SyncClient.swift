import Foundation
import Network

struct SyncError: LocalizedError {
    let message: String
    var status = 0
    var errorDescription: String? { message }
}

/// Talks to Curated's sync server on the Mac.
struct SyncClient {
    static let defaultPort = 8765

    let host: String
    let port: Int
    var token: String?

    private var base: URL {
        let h = host.contains(":") ? "[\(host)]" : host
        return URL(string: "http://\(h):\(port)")!
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Name and API version; answers without a token, so it's a quick "is the Mac there?" check.
    func info(timeout: TimeInterval = 2) async throws -> [String: String] {
        let data = try await request("GET", "/info", timeout: timeout)
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    struct PairResponse: Decodable {
        let token: String
        let macName: String?
    }

    func pair(code: String, deviceName: String) async throws -> PairResponse {
        let body = try JSONEncoder().encode(["code": code, "deviceName": deviceName])
        return try JSONDecoder().decode(PairResponse.self, from: try await request("POST", "/pair", body: body))
    }

    /// Short videos only unless `forms` asks for long ones too, and the Vines with `vine` (a Mac from before long
    /// videos or Vines ignores what it doesn't know).
    func manifest(forms: SyncForms = .short, vine: Bool = false) async throws -> Data {
        let query = [forms == .short ? nil : "forms=\(forms.query)", vine ? "vine=1" : nil].compactMap { $0 }
        return try await request("GET", "/manifest" + (query.isEmpty ? "" : "?" + query.joined(separator: "&")))
    }

    private struct PlayedPayload: Codable {
        let marks: [String: PlayedMark]
        /// Missing from Macs older than 1.5.
        let watchLater: [String: WatchLaterMark]?
        /// Missing from Macs without bookmarks.
        let bookmarks: [String: WatchLaterMark]?
    }

    /// Sends this phone's watched history, Watch Later list and bookmarks; returns the Mac's merged ones.
    func played(_ marks: [String: PlayedMark], watchLater: [String: WatchLaterMark], bookmarks: [String: WatchLaterMark]) async throws
        -> (marks: [String: PlayedMark], watchLater: [String: WatchLaterMark], bookmarks: [String: WatchLaterMark]) {
        let body = try JSONEncoder.curated.encode(PlayedPayload(marks: marks, watchLater: watchLater, bookmarks: bookmarks))
        let data = try await request("POST", "/played", body: body)
        let merged = try JSONDecoder.curated.decode(PlayedPayload.self, from: data)
        // An older Mac doesn't know bookmarks yet; keep ours.
        return (merged.marks, merged.watchLater ?? [:], merged.bookmarks ?? bookmarks)
    }

    private struct PositionsPayload: Codable {
        let positions: [String: PositionMark]
        var nowPlaying: NowPlayingMark?
        var playback: PlaybackRules?
    }

    typealias PositionsReply = (positions: [String: PositionMark], nowPlaying: NowPlayingMark?, playback: PlaybackRules?)

    /// Sends where this phone left off in long videos; returns the Mac's merged positions. Macs older than API 4 answer
    /// with an error.
    func positions(_ marks: [String: PositionMark], nowPlaying: NowPlayingMark, playback: PlaybackRules) async throws -> PositionsReply {
        let body = try JSONEncoder.curated.encode(PositionsPayload(positions: marks, nowPlaying: nowPlaying, playback: playback))
        let data = try await request("POST", "/positions", body: body)
        let reply = try JSONDecoder.curated.decode(PositionsPayload.self, from: data)
        return (reply.positions, reply.nowPlaying, reply.playback)
    }

    struct ForceDownloadReply: Decodable {
        let started: Bool
        let message: String
    }

    /// Asks the Mac to start a total download. Macs older than API 6 answer 404.
    func forceDownload() async throws -> ForceDownloadReply {
        try JSONDecoder().decode(ForceDownloadReply.self, from: try await request("POST", "/download", body: Data("{}".utf8)))
    }

    /// The add-creator form. A Mac older than API 10 answers 404.
    func creatorForm() async throws -> CreatorForm {
        try JSONDecoder().decode(CreatorForm.self, from: try await request("GET", "/creators/form"))
    }

    func addCreator(formVersion: Int, values: [String: String]) async throws -> AddCreatorReply {
        struct Body: Encodable {
            let formVersion: Int
            let values: [String: String]
        }
        let body = try JSONEncoder().encode(Body(formVersion: formVersion, values: values))
        return try JSONDecoder().decode(AddCreatorReply.self, from: try await request("POST", "/creators", body: body))
    }

    /// Follows the Mac's listing of a creator's older videos. Returns when it's done; cancelling the task stops it.
    func followOlderVideos(of creator: String, _ onEvent: @MainActor (OlderVideosEvent) -> Void) async throws {
        let (bytes, response) = try await Self.session.bytes(for: urlRequest("GET", "/creators/\(creator)/older", timeout: 30))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.error(from: body, status: status)
        }
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            if let event = try? JSONDecoder.curated.decode(OlderVideosEvent.self, from: Data(line.dropFirst(6).utf8)) {
                await onEvent(event)
            }
        }
    }

    func requestOlderVideos(of creator: String, ids: [String], skip: [String], heights: [String: Int]) async throws -> OlderVideosReply {
        struct Body: Encodable {
            let ids: [String]
            let skip: [String]
            let heights: [String: Int]
        }
        let body = try JSONEncoder().encode(Body(ids: ids, skip: skip, heights: heights))
        return try JSONDecoder().decode(OlderVideosReply.self, from: try await request("POST", "/creators/\(creator)/older", body: body))
    }

    func olderThumbnail(_ id: String) async throws -> Data {
        try await request("GET", "/older-thumbnail/\(id)", timeout: 30)
    }

    /// Follows the Mac's download, calling `onEvent` about once a second. Returns when the Mac closes the connection,
    /// which it does when nothing's downloading; cancelling the task closes it from this end.
    func followDownload(_ onEvent: @MainActor (MacDownloadProgress) -> Void) async throws {
        let (bytes, response) = try await Self.session.bytes(for: urlRequest("GET", "/download/progress", timeout: 15))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw SyncError(message: "The Mac answered with error \(status)", status: status)
        }
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            if let event = try? JSONDecoder.curated.decode(MacDownloadProgress.self, from: Data(line.dropFirst(6).utf8)) {
                await onEvent(event)
            }
        }
    }

    /// Downloads to `partial`, resuming where a previous attempt stopped, then moves it to `dest`.
    /// `progress` gets the number of new bytes as they arrive (negative if the server restarted the file).
    func download(_ path: String, partial: URL, to dest: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        let resumeFrom = (try? partial.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        var request = urlRequest("GET", path, timeout: 30)
        if resumeFrom > 0 { request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range") }
        try await FileDownload(partial: partial, resumeFrom: resumeFrom, progress: progress).run(request)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: partial, to: dest)
    }

    private func urlRequest(_ method: String, _ path: String, timeout: TimeInterval) -> URLRequest {
        // The query (e.g. "?forms=long") goes on separately: appendingPathComponent would escape its "?".
        let parts = path.split(separator: "?", maxSplits: 1).map(String.init)
        var url = base.appendingPathComponent(String(parts[0].dropFirst()))
        if parts.count > 1, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = parts[1]
            url = components.url ?? url
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func request(_ method: String, _ path: String, body: Data? = nil, timeout: TimeInterval = 15) async throws -> Data {
        var request = urlRequest(method, path, timeout: timeout)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.error(from: data, status: status) }
        return data
    }

    private static func error(from data: Data, status: Int) -> SyncError {
        let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
        return SyncError(message: message ?? "The Mac answered with error \(status)", status: status)
    }
}

/// Streams a response body into a file as it arrives, appending when the server honors a Range request.
private final class FileDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let partial: URL
    private let resumeFrom: Int
    private let progress: @Sendable (Int) -> Void
    private var handle: FileHandle?
    private var status = 0
    private var errorBody = Data()
    private var continuation: CheckedContinuation<Void, Error>?

    init(partial: URL, resumeFrom: Int, progress: @escaping @Sendable (Int) -> Void) {
        self.partial = partial
        self.resumeFrom = resumeFrom
        self.progress = progress
    }

    func run(_ request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.dataTask(with: request).resume()
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 206, let handle = try? FileHandle(forWritingTo: partial) {
            _ = try? handle.seekToEnd()
            self.handle = handle
        } else if status == 200 {
            if resumeFrom > 0 { progress(-resumeFrom) }
            FileManager.default.createFile(atPath: partial.path, contents: nil)
            handle = try? FileHandle(forWritingTo: partial)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let handle {
            try? handle.write(contentsOf: data)
            progress(data.count)
        } else {
            errorBody.append(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close()
        if let error {
            continuation?.resume(throwing: error)
        } else if !(200..<300).contains(status) {
            let message = (try? JSONDecoder().decode([String: String].self, from: errorBody))?["error"]
            continuation?.resume(throwing: SyncError(message: message ?? "The Mac answered with error \(status)", status: status))
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}

struct FoundMac: Identifiable, Hashable {
    let name: String
    let host: String
    let port: Int
    var id: String { "\(name)|\(host):\(port)" }
}

/// Finds Macs advertising Curated's sync service on this network.
enum Discovery {
    /// With `name`, stops as soon as that Mac appears and only looks that one up, rather than waiting out `seconds`.
    static func find(for seconds: Double = 3, name: String? = nil) async -> [FoundMac] {
        let browser = NWBrowser(for: .bonjour(type: "_curated._tcp", domain: nil), using: .tcp)
        let queue = DispatchQueue(label: "curated.discovery")
        let results = LockedBox<Set<NWBrowser.Result>>([])
        browser.browseResultsChangedHandler = { found, _ in results.set(found) }
        browser.start(queue: queue)
        func isWanted(_ result: NWBrowser.Result) -> Bool {
            if case .service(name, _, _, _) = result.endpoint { return true }
            return false
        }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, name == nil || !results.get().contains(where: isWanted) {
            try? await Task.sleep(for: .milliseconds(name == nil ? 250 : 25))
        }
        browser.cancel()

        var macs: [FoundMac] = []
        for result in results.get() where name == nil || isWanted(result) {
            guard case .service(let found, _, _, _) = result.endpoint,
                  let (host, port) = await resolve(result.endpoint, queue: queue) else { continue }
            macs.append(FoundMac(name: found, host: host, port: port))
        }
        return macs.sorted { $0.name < $1.name }
    }

    /// Connects briefly to learn the service's address, since HTTP needs a host and port.
    private static func resolve(_ endpoint: NWEndpoint, queue: DispatchQueue) async -> (String, Int)? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        return await withCheckedContinuation { continuation in
            let done = LockedBox(false)
            @Sendable func finish(_ value: (String, Int)?) {
                guard !done.get() else { return }
                done.set(true)
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }
                        finish((text, Int(port.rawValue)))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}

/// A tiny thread-safe box for values shared with Network framework callbacks.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
    func update(_ body: (inout Value) -> Void) { lock.withLock { body(&value) } }
}
