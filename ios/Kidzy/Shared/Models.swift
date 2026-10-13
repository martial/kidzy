import Foundation

/// A collection groups items: a show with its episodes, songs, films.
public struct Collection: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: String
    public var itemCount: Int
    public var posterURL: String?

    public init(id: String, title: String, kind: String, itemCount: Int, posterURL: String? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.itemCount = itemCount
        self.posterURL = posterURL
    }
}

/// One playable video.
public struct Item: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var collectionID: String?
    public var title: String
    public var duration: Double
    public var thumbURL: String
    public var videoURL: String

    public init(id: String, collectionID: String?, title: String, duration: Double, thumbURL: String, videoURL: String) {
        self.id = id
        self.collectionID = collectionID
        self.title = title
        self.duration = duration
        self.thumbURL = thumbURL
        self.videoURL = videoURL
    }
}
