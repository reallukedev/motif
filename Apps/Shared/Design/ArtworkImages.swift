import Foundation
import ImageIO

/// Album covers, fetched once, decoded off the main actor at the size they're drawn, and
/// kept in memory.
///
/// `AsyncImage` keeps nothing in memory. In a long list every cover that scrolled back into
/// view was fetched again from the URL cache and a 300-pixel JPEG decoded again, and the
/// generated cover showed underneath in the meantime. Here a cover already seen is ready in
/// the same frame, and a new one arrives decoded, so scrolling only has to draw it.
nonisolated final class ArtworkImages: Sendable {
    static let shared = ArtworkImages()

    struct Key: Hashable, Sendable {
        let url: URL
        /// The longest side in pixels. A cover is decoded for the size it's drawn at.
        let pixels: Int
    }

    /// Thread-safe, and emptied by the system under memory pressure.
    private nonisolated(unsafe) let images: NSCache<KeyBox, ImageBox> = {
        let cache = NSCache<KeyBox, ImageBox>()
        // Enough for several screens of rows at any size, measured in decoded pixels.
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    private let loads = InFlight()

    /// A cover already decoded at this size, without waiting.
    func cached(_ key: Key) -> CGImage? {
        images.object(forKey: KeyBox(key))?.image
    }

    /// The cover at this size. Rows asking for the same cover at once share one fetch.
    func image(for key: Key) async -> CGImage? {
        if let cached = cached(key) { return cached }
        let image = await loads.load(key) { await Self.fetch(key) }
        if let image {
            images.setObject(ImageBox(image), forKey: KeyBox(key), cost: image.bytesPerRow * image.height)
        }
        return image
    }

    @concurrent
    private static func fetch(_ key: Key) async -> CGImage? {
        // The shared session's URL cache keeps the downloaded file, so a cover isn't
        // downloaded again after it falls out of memory.
        guard let (data, response) = try? await URLSession.shared.data(from: key.url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: key.pixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, here, rather than when the image is first drawn on the main thread.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Loads in progress, so a cover on screen in ten rows is fetched once.
    private actor InFlight {
        private var tasks: [Key: Task<CGImage?, Never>] = [:]

        func load(_ key: Key, _ work: @escaping @Sendable () async -> CGImage?) async -> CGImage? {
            if let task = tasks[key] { return await task.value }
            let task = Task { await work() }
            tasks[key] = task
            let image = await task.value
            tasks[key] = nil
            return image
        }
    }

    private final class KeyBox: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private final class ImageBox {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
}
