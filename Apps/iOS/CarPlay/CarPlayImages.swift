import UIKit
import SwiftUI
import MusicKit
import MotifCore

/// Pictures for CarPlay's templates, which take finished `UIImage`s rather than views: covers
/// fetched and drawn at the car screen's scale, and mixes as four covers to a square.
@MainActor
enum CarPlayImages {
    /// Finished images by what they show, so rebuilding a tab after each song doesn't draw
    /// every cover again. A couple of hundred at most, then it starts over.
    private static var cache: [String: UIImage] = [:]

    private static func cached(_ key: String, _ make: () async -> UIImage) async -> UIImage {
        if let image = cache[key] { return image }
        let image = await make()
        if cache.count > 300 { cache.removeAll() }
        cache[key] = image
        return image
    }

    /// A cover from the history, or its generated stand-in when it has none or won't load.
    static func cover(url: String?, seed: String, side: CGFloat, scale: CGFloat) async -> UIImage {
        await cached("\(url ?? seed)|\(side)|\(scale)") {
            if let url, let address = URL(string: url),
               let image = await ArtworkImages.shared.image(for: ArtworkImages.Key(url: address, pixels: Int(side * scale))) {
                return UIImage(cgImage: image, scale: scale, orientation: .up)
            }
            return generated(seed: seed, side: side, scale: scale)
        }
    }

    /// A cover from Apple Music. Library covers use an address only MusicKit can load, so
    /// those fall back to a generated cover.
    static func cover(_ art: CoverArt, side: CGFloat, scale: CGFloat) async -> UIImage {
        switch art {
        case .artwork(let artwork):
            let pixels = Int(side * scale)
            let url = artwork.url(width: pixels, height: pixels)
            let loadable = url.flatMap { $0.scheme?.hasPrefix("http") == true ? $0.absoluteString : nil }
            return await cover(url: loadable, seed: artwork.alternateText ?? "\(pixels)", side: side, scale: scale)
        case .url(let url, let seed):
            return await cover(url: url, seed: seed, side: side, scale: scale)
        }
    }

    /// Four covers in a square, as on the phone's mix tiles.
    static func mosaic(_ covers: [MixCoverArt], side: CGFloat, scale: CGFloat) async -> UIImage {
        let key = covers.prefix(4).map { $0.url ?? $0.seed }.joined(separator: "+") + "|\(side)|\(scale)"
        return await cached(key) { await drawMosaic(covers, side: side, scale: scale) }
    }

    private static func drawMosaic(_ covers: [MixCoverArt], side: CGFloat, scale: CGFloat) async -> UIImage {
        guard covers.count >= 4 else {
            return await cover(url: covers.first?.url, seed: covers.first?.seed ?? "mix", side: side, scale: scale)
        }
        var tiles: [UIImage] = []
        for cover in covers.prefix(4) {
            tiles.append(await self.cover(url: cover.url, seed: cover.seed, side: side / 2, scale: scale))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            for (index, tile) in tiles.enumerated() {
                let origin = CGPoint(x: CGFloat(index % 2) * side / 2, y: CGFloat(index / 2) * side / 2)
                tile.draw(in: CGRect(origin: origin, size: CGSize(width: side / 2, height: side / 2)))
            }
        }
    }

    static func generated(seed: String, side: CGFloat, scale: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: GeneratedCover(seed: seed).frame(width: side, height: side))
        renderer.scale = scale
        return renderer.uiImage ?? UIImage()
    }

    /// A symbol in the accent colour, for rows that stand for a fact rather than a cover.
    static func symbol(_ name: String, tint: UIColor = .systemPink) -> UIImage? {
        UIImage(systemName: name)?.withTintColor(tint, renderingMode: .alwaysOriginal)
    }
}
