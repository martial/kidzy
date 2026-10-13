import Foundation

/// The HTTP client for the server's API (docs/api.md). Foundation only, so it
/// is tested on the Mac.
public struct KidzyClient: Sendable {
    public var endpoint: ServerEndpoint
    public var token: String?
    public var session: URLSession

    public enum Failure: Error, Equatable, Sendable {
        case badURL
        case http(Int, String)
        case decoding
    }

    public init(endpoint: ServerEndpoint, token: String? = nil, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.token = token
        self.session = session
    }

    public func identity() async throws -> Identity { try await get("/api/identity") }

    public func pair(pin: String, deviceName: String) async throws -> PairResponse {
        try await post("/api/pair", body: ["pin": pin, "deviceName": deviceName])
    }

    public func collections() async throws -> CollectionsResponse { try await get("/api/collections") }

    public func collection(id: String) async throws -> CollectionDetail { try await get("/api/collections/\(id)") }

    public func limits() async throws -> Verdict { try await get("/api/limits") }

    public func timeline(_ event: TimelineReporter.Event) async throws -> Verdict {
        try await post("/api/timeline", body: event)
    }

    public func unlock(pin: String) async throws -> ParentSession {
        try await post("/api/parent/unlock", body: ["pin": pin])
    }

    public func settings(parentToken: String) async throws -> Settings {
        try await get("/api/settings", headers: ["X-Parent-Token": parentToken])
    }

    public func updateSettings(parentToken: String, limits: Rules?, collections: [(id: String, visible: Bool)]) async throws -> Settings {
        struct Body: Encodable {
            struct Col: Encodable {
                var id: String
                var visible: Bool
            }
            var limits: Rules?
            var collections: [Col]
        }
        return try await send("PUT", "/api/settings", body: Body(limits: limits, collections: collections.map { .init(id: $0.id, visible: $0.visible) }), headers: ["X-Parent-Token": parentToken])
    }

    public func mediaURL(_ path: String) -> URL? {
        endpoint.mediaURL(path: path, token: token ?? "")
    }

    // MARK: - plumbing

    func get<T: Decodable>(_ path: String, headers: [String: String] = [:]) async throws -> T {
        try await send("GET", path, body: Optional<Int>.none, headers: headers)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B, headers: [String: String] = [:]) async throws -> T {
        try await send("POST", path, body: body, headers: headers)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, headers: [String: String]) async throws -> T {
        guard let base = endpoint.baseURL, let url = URL(string: path, relativeTo: base) else { throw Failure.badURL }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error ?? "HTTP \(status)"
            throw Failure.http(status, message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Failure.decoding
        }
    }
}
