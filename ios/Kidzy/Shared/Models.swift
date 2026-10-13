import Foundation

/// A collection groups items: a show with its episodes, songs, films.
public struct Collection: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: String
    public var color: String
    public var itemCount: Int
    public var posterUrl: String

    public init(id: String, title: String, kind: String, color: String, itemCount: Int, posterUrl: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.color = color
        self.itemCount = itemCount
        self.posterUrl = posterUrl
    }
}

/// One playable video.
public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var collectionId: String
    public var title: String
    public var duration: Double
    public var color: String
    public var thumbUrl: String
    public var videoUrl: String

    public init(id: String, collectionId: String, title: String, duration: Double, color: String, thumbUrl: String, videoUrl: String) {
        self.id = id
        self.collectionId = collectionId
        self.title = title
        self.duration = duration
        self.color = color
        self.thumbUrl = thumbUrl
        self.videoUrl = videoUrl
    }
}

public struct Identity: Codable, Sendable {
    public var name: String
    public var id: String
    public var version: String
    public var libraryVersion: Int
    public var serverTime: String
    public var pinSet: Bool
}

public struct PairResponse: Codable, Sendable {
    public var deviceId: String
    public var token: String
    public var name: String
}

public struct CollectionsResponse: Codable, Sendable {
    public var collections: [Collection]
    public var libraryVersion: Int
}

public struct CollectionDetail: Codable, Sendable {
    public var collection: Collection
    public var items: [Item]
}

public struct Bedtime: Codable, Hashable, Sendable {
    public var start: String
    public var end: String
    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

public struct Rules: Codable, Hashable, Sendable {
    public var dailySeconds: Int
    public var bedtime: Bedtime?
    public init(dailySeconds: Int = 0, bedtime: Bedtime? = nil) {
        self.dailySeconds = dailySeconds
        self.bedtime = bedtime
    }
}

/// The server's answer to "may the kids watch right now?".
public struct Verdict: Codable, Hashable, Sendable {
    public var allowed: Bool
    public var unlimited: Bool
    public var remainingSeconds: Int
    public var watchedSeconds: Int
    public var reason: String
    public var serverTime: String
    public var rules: Rules

    public init(allowed: Bool, unlimited: Bool, remainingSeconds: Int, watchedSeconds: Int, reason: String, serverTime: String, rules: Rules) {
        self.allowed = allowed
        self.unlimited = unlimited
        self.remainingSeconds = remainingSeconds
        self.watchedSeconds = watchedSeconds
        self.reason = reason
        self.serverTime = serverTime
        self.rules = rules
    }
}

public struct ParentSession: Codable, Sendable {
    public var token: String
    public var expires: String
}

public struct SettingsCollection: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var color: String
    public var visible: Bool
    public var itemCount: Int
}

public struct Settings: Codable, Sendable {
    public var limits: Rules
    public var serverName: String
    public var finishedImageSet: Bool
    public var pinSet: Bool
    public var watchedToday: Int
    public var collections: [SettingsCollection]
}

public struct APIError: Codable, Error, Sendable {
    public var error: String
}
