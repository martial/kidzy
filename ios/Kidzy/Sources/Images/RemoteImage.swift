import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Loads a thumbnail from the server, downsampled to the tile size, cached in memory.
@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, UIImage>()
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    init() {
        cache.totalCostLimit = 40 * 1024 * 1024
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = inflight[url] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return Self.downsample(data, maxPixel: maxPixel)
        }
        inflight[url] = task
        let img = await task.value
        inflight[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height * 4)) }
        return img
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct RemoteImage: View {
    let url: URL?
    var maxPixel: CGFloat = 600
    var placeholder: Color = Theme.sky
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { return }
            image = await ImageStore.shared.image(for: url, maxPixel: maxPixel * 2)
        }
    }
}
