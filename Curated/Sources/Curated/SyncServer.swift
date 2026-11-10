import Foundation
import SystemConfiguration
import dnssd

struct SyncRequest {
    let method: String
    /// Percent-decoded, without the query string.
    let path: String
    /// The query string's parameters ("?forms=short,long" → ["forms": "short,long"]), percent-decoded.
    var query: [String: String] = [:]
    /// Header names are lowercased.
    let headers: [String: String]
    let body: Data
}

enum SyncResponse {
    case json(Data)
    case file(URL, contentType: String)
    case error(Int, String)
    /// Server-sent events: `next` gives each event's bytes, about a second apart, and the connection closes after the
    /// one marked `last`, or as soon as the phone goes.
    case events(next: @Sendable () async -> (event: Data, last: Bool))
    /// What to answer takes a while to find out, off the main thread.
    case deferred(@Sendable () async -> SyncResponse)
}

/// A minimal HTTP/1.1 server for the phone app: one request per connection, plus an optional
/// Bonjour advertisement so phones on the network can find it. Auth and routing live in AppModel.
///
/// Plain sockets rather than NWListener: on a real Wi-Fi link NWConnection kept about 600 KB in flight whatever was
/// queued on it (60 Mbps at 80 ms), where a socket's send buffer grows to fit the link (350 Mbps on the same one).
final class SyncServer: @unchecked Sendable {
    /// CURATED_SYNC_PORT lets a test copy run next to the real app.
    static let port: UInt16 = ProcessInfo.processInfo.environment["CURATED_SYNC_PORT"].flatMap(UInt16.init) ?? 8765
    static let serviceType = "_curated._tcp"
    private static let maxHeader = 16 << 10
    private static let maxBody = 16 << 20
    /// Gives up on a phone that stops reading or sending for this long, in seconds.
    private static let socketTimeout = 30

    private let queue = DispatchQueue(label: "local.curated.sync")
    private let handle: @Sendable (SyncRequest) async -> SyncResponse
    private var acceptSource: DispatchSourceRead?
    private var advertisement: DNSServiceRef?

    init(handle: @escaping @Sendable (SyncRequest) async -> SyncResponse) {
        self.handle = handle
    }

    func start(onFailure: @escaping @Sendable (String) -> Void) {
        func fail(_ what: String, closing fd: Int32 = -1) {
            let reason = String(cString: strerror(errno))
            if fd >= 0 { close(fd) }
            onFailure("Couldn't listen on port \(Self.port): \(what): \(reason)")
        }
        // IPv6 with IPv6-only off takes IPv4 connections too.
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return fail("socket") }
        var on: Int32 = 1, off: Int32 = 0
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &off, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = Self.port.bigEndian
        address.sin6_addr = in6addr_any
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
        }
        guard bound == 0 else { return fail("bind", closing: fd) }
        guard listen(fd, 64) == 0 else { return fail("listen", closing: fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                if let self { self.serve(client) } else { close(client) }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        acceptSource = source
    }

    func stop() {
        setAdvertised(false)
        acceptSource?.cancel()
        acceptSource = nil
    }

    func setAdvertised(_ advertised: Bool, name: String = "") {
        if let advertisement {
            DNSServiceRefDeallocate(advertisement)
            self.advertisement = nil
        }
        guard advertised else { return }
        var ref: DNSServiceRef?
        let error = DNSServiceRegister(&ref, 0, 0, name, Self.serviceType, nil, nil, Self.port.bigEndian, 0, nil,
                                       { _, _, _, _, _, _, _ in }, nil)
        guard error == kDNSServiceErr_NoError, let ref else { return }
        DNSServiceSetDispatchQueue(ref, queue)
        advertisement = ref
    }

    deinit { stop() }

    // MARK: Connections

    /// Each connection gets a thread that blocks on its socket, which is fine for the few phones syncing at once.
    private func serve(_ client: Int32) {
        // An accepted socket can inherit non-blocking from the listening one.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var on: Int32 = 1
        var timeout = timeval(tv_sec: Self.socketTimeout, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(client, IPPROTO_TCP, TCP_NODELAY, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        Self.workers.async { [weak self] in
            guard let self, let request = self.readRequest(client) else {
                close(client)
                return
            }
            Task {
                var response = await self.handle(request)
                if case .deferred(let work) = response { response = await work() }
                if case .events(let next) = response {
                    await self.stream(client, next: next)
                    close(client)
                    return
                }
                Self.workers.async {
                    self.respond(client, to: request, with: response)
                    close(client)
                }
            }
        }
    }

    /// Not throttled like a background app's default work, and concurrent: each transfer holds a thread.
    private static let workers = DispatchQueue(label: "local.curated.sync.workers", qos: .userInitiated, attributes: .concurrent)

    /// The request on `client`, or nil once it has been answered with an error or the phone has gone.
    private func readRequest(_ client: Int32) -> SyncRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            switch Self.parse(buffer) {
            case .complete(let request):
                return request
            case .invalid:
                send(client, status: 400, body: Self.errorBody("Bad request"))
                return nil
            case .incomplete:
                let count = recv(client, &chunk, chunk.count, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return nil }
                buffer.append(contentsOf: chunk[0..<count])
            }
        }
    }

    private enum ParseResult {
        case incomplete, invalid, complete(SyncRequest)
    }

    private static func parse(_ buffer: Data) -> ParseResult {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > maxHeader ? .invalid : .incomplete
        }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int(headers["content-length"] ?? "0"), (0...maxBody).contains(length) else { return .invalid }
        guard buffer.distance(from: end.upperBound, to: buffer.endIndex) >= length else { return .incomplete }
        let parts = requestLine[1].split(separator: "?", maxSplits: 1).map(String.init)
        let target = parts.first ?? "/"
        var query: [String: String] = [:]
        for pair in (parts.count > 1 ? parts[1] : "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if let key = kv.first { query[key] = kv.count > 1 ? kv[1] : "" }
        }
        let body = buffer[end.upperBound..<buffer.index(end.upperBound, offsetBy: length)]
        return .complete(SyncRequest(method: String(requestLine[0]), path: target.removingPercentEncoding ?? target,
                                     query: query, headers: headers, body: Data(body)))
    }

    // MARK: Responses

    private func respond(_ client: Int32, to request: SyncRequest, with response: SyncResponse) {
        switch response {
        case .json(let data):
            send(client, status: 200, body: data)
        case .error(let status, let message):
            send(client, status: status, body: Self.errorBody(message))
        case .file(let url, let contentType):
            sendFile(client, url: url, contentType: contentType, range: request.headers["range"])
        case .events, .deferred:
            break  // Streamed or worked out by `serve`, without holding a worker thread in between.
        }
    }

    /// Returns when the last event is sent or a send fails, which is how a phone that left is noticed.
    private func stream(_ client: Int32, next: @Sendable () async -> (event: Data, last: Bool)) async {
        func write(_ data: Data) async -> Bool {
            await withCheckedContinuation { continuation in
                Self.workers.async { continuation.resume(returning: self.sendAll(client, data)) }
            }
        }
        let head = Self.head(status: 200, headers: ["Content-Type": "text/event-stream", "Cache-Control": "no-cache"])
        guard await write(head) else { return }
        while true {
            let (event, last) = await next()
            guard await write(event), !last else { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func send(_ client: Int32, status: Int, body: Data) {
        let head = Self.head(status: status, headers: ["Content-Type": "application/json",
                                                       "Content-Length": "\(body.count)"])
        _ = sendAll(client, head + body)
    }

    private func sendAll(_ client: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.send(client, bytes.baseAddress! + sent, bytes.count - sent, 0)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { return false }
                sent += count
            }
            return true
        }
    }

    /// Sends the file with sendfile, honoring a single "Range: bytes=" request so the phone can resume.
    private func sendFile(_ client: Int32, url: URL, contentType: String, range: String?) {
        let file = open(url.path, O_RDONLY)
        var info = stat()
        guard file >= 0, fstat(file, &info) == 0 else {
            if file >= 0 { close(file) }
            send(client, status: 404, body: Self.errorBody("File not found"))
            return
        }
        defer { close(file) }
        let size = Int(info.st_size)
        var bounds = 0...max(0, size - 1)
        var status = 200
        if let range {
            guard let requested = Self.parseRange(range, size: size) else {
                send(client, status: 416, body: Self.errorBody("Range not satisfiable"))
                return
            }
            bounds = requested
            status = 206
        }
        var headers = ["Content-Type": contentType, "Content-Length": "\(size == 0 ? 0 : bounds.count)",
                       "Accept-Ranges": "bytes"]
        if status == 206 { headers["Content-Range"] = "bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(size)" }
        guard sendAll(client, Self.head(status: status, headers: headers)), size > 0 else { return }
        var offset = off_t(bounds.lowerBound)
        var remaining = off_t(bounds.count)
        while remaining > 0 {
            var length = remaining
            let result = sendfile(file, client, offset, &length, nil, 0)
            offset += length
            remaining -= length
            // Blocked past the timeout, or a partial send to carry on from.
            if result != 0 && !(errno == EINTR || (errno == EAGAIN && length > 0)) { return }
            if result == 0 && length == 0 { return }  // The file got shorter.
        }
    }

    /// "bytes=START-END", "bytes=START-" or "bytes=-SUFFIX".
    private static func parseRange(_ header: String, size: Int) -> ClosedRange<Int>? {
        guard header.hasPrefix("bytes="), size > 0 else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let start: Int, end: Int
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { return nil }
            start = max(0, size - suffix)
            end = size - 1
        } else {
            guard let s = Int(parts[0]) else { return nil }
            start = s
            end = parts[1].isEmpty ? size - 1 : min(Int(parts[1]) ?? -1, size - 1)
        }
        guard start >= 0, start <= end, start < size else { return nil }
        return start...end
    }

    private static func head(status: Int, headers: [String: String]) -> Data {
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var lines = ["HTTP/1.1 \(status) \(reason)", "Connection: close"]
        lines += headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private static func errorBody(_ message: String) -> Data {
        (try? JSONEncoder().encode(["error": message])) ?? Data()
    }

    // MARK: Addresses

    /// What the Mac is called on the network, e.g. "Jane's MacBook Pro".
    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    /// IPv4 addresses on Wi-Fi/Ethernet, wired first. Shown for pairing when the Mac isn't discoverable, and in /info
    /// so phones can choose the wired one (600 Mbps against 320 over Wi-Fi to the same phone, measured 2026-11-04).
    static func localAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        let wifi = Set(interfaces.filter { SCNetworkInterfaceGetInterfaceType($0) == kSCNetworkInterfaceTypeIEEE80211 }
            .compactMap { SCNetworkInterfaceGetBSDName($0) as String? })
        var wired: [String] = []
        var wireless: [String] = []
        var cursor = list
        while let entry = cursor?.pointee {
            defer { cursor = entry.ifa_next }
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  String(cString: entry.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if text.hasPrefix("169.254.") { continue }  // No DHCP answer, or a Thunderbolt bridge: phones can't reach it.
            if wifi.contains(String(cString: entry.ifa_name)) {
                wireless.append(text)
            } else {
                wired.append(text)
            }
        }
        return wired + wireless
    }
}
