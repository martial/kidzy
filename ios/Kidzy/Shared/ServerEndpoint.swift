import Foundation

/// Where the server is: found by Bonjour or typed by the parent, then kept.
public struct ServerEndpoint: Codable, Hashable, Sendable {
    public var host: String
    public var port: Int
    public var name: String

    public init(host: String, port: Int = 8800, name: String = "Kidzy") {
        self.host = host
        self.port = port
        self.name = name
    }

    /// False for an address a URL cannot carry (an IPv6 link-local with its zone, for example).
    public var isUsable: Bool {
        !host.isEmpty && !host.contains("%") && !host.hasPrefix("[") && baseURL != nil
    }

    public var baseURL: URL? {
        var c = URLComponents()
        c.scheme = "http"
        c.host = host
        c.port = port
        return c.url
    }

    /// Parses "host", "host:port" or "http://host:port".
    public static func parse(_ text: String) -> ServerEndpoint? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let u = URL(string: s), let host = u.host, !host.isEmpty else { return nil }
        return ServerEndpoint(host: host, port: u.port ?? 8800)
    }

    /// A media URL for AVPlayer and image loading, with the device token as query.
    public func mediaURL(path: String, token: String) -> URL? {
        guard let base = baseURL, var c = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { return nil }
        c.queryItems = [URLQueryItem(name: "token", value: token)]
        return c.url
    }
}
