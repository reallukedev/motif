import SwiftUI
import CoreGraphics

/// A colour taken from a cover, deep enough that white type on it always reads.
///
/// The hero wears the colour of the music in it, the way Music's cards do. The average of the
/// cover is darkened until its luminance is at most 0.1, which puts white at 7:1 and 85% white
/// above 4.5:1.
enum CoverTint {
    static let maximumLuminance = 0.1

    /// Nil when there's no cover or it won't load.
    static func color(for url: String?) async -> Color? {
        guard let url, let address = URL(string: url) else { return nil }
        guard let image = await ArtworkImages.shared.image(for: ArtworkImages.Key(url: address, pixels: 64)) else { return nil }
        guard let average = average(of: image) else { return nil }
        let deep = deepened(average)
        return Color(red: deep.red, green: deep.green, blue: deep.blue)
    }

    /// The colour of the stand-in cover ``GeneratedCover`` draws for this seed, for songs with
    /// no artwork: the same hue, so the field matches the cover on it.
    static func color(forSeed seed: String) -> Color {
        let hue = Double(GeneratedCover.hash(seed) % 360) / 360
        let deep = deepened(rgb(hue: hue, saturation: 0.7, brightness: 0.75))
        return Color(red: deep.red, green: deep.green, blue: deep.blue)
    }

    /// A cover's colour, from its image when it has one and its seed otherwise.
    static func color(for url: String?, seed: String) async -> Color {
        if let found = await color(for: url) { return found }
        return color(forSeed: seed)
    }

    /// A cover's colour as it looks, not deepened for type: for light behind a page, where
    /// nothing is read on it. A little more saturated than the plain average, which comes out
    /// greyer than the cover looks.
    static func glow(for cover: CoverArt) async -> Color? {
        let rgb: RGB?
        switch cover {
        case .artwork(let artwork):
            rgb = artwork.backgroundColor.flatMap(components(of:))
        case .url(let url, let seed):
            if let url, let address = URL(string: url),
               let image = await ArtworkImages.shared.image(for: ArtworkImages.Key(url: address, pixels: 64)) {
                rgb = average(of: image)
            } else {
                rgb = self.rgb(hue: Double(GeneratedCover.hash(seed) % 360) / 360, saturation: 0.7, brightness: 0.75)
            }
        }
        guard let rgb else { return nil }
        let vivid = saturated(rgb, by: 1.5)
        return Color(red: vivid.red, green: vivid.green, blue: vivid.blue)
    }

    /// The field for any cover: Apple Music's own colour for its artwork, the picture's
    /// average for an address, and the stand-in's hue for a song with no cover.
    static func color(for cover: CoverArt) async -> Color? {
        switch cover {
        case .artwork(let artwork):
            artwork.backgroundColor.flatMap(color(from:))
        case .url(let url, let seed):
            await color(for: url, seed: seed)
        }
    }

    /// The deepened version of a CoreGraphics colour, for Apple Music's own artwork colours.
    static func color(from cgColor: CGColor) -> Color? {
        guard let rgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3
        else { return nil }
        let deep = deepened((components[0], components[1], components[2]))
        return Color(red: deep.red, green: deep.green, blue: deep.blue)
    }

    typealias RGB = (red: Double, green: Double, blue: Double)

    /// Four colours from a cover, each deep enough for white type, for a field that moves:
    /// Apple Music's own palette for its artwork, the picture's quarters for an address, and
    /// shades of the stand-in's hue for a song with no cover.
    static func palette(for cover: CoverArt) async -> [Color] {
        var colors: [RGB] = []
        // The picture's own colours first: Apple Music's text colours are picked to read on
        // the cover, so they come out greys, not the cover's colours.
        if let image = await smallImage(for: cover, pixels: 64) {
            colors = quarters(of: image)
        } else if case .artwork(let artwork) = cover {
            colors = [artwork.backgroundColor, artwork.primaryTextColor, artwork.secondaryTextColor, artwork.tertiaryTextColor]
                .compactMap { $0.flatMap(components(of:)) }
        } else if case .url(_, let seed) = cover {
            let hue = Double(GeneratedCover.hash(seed) % 360) / 360
            colors = [0, 0.05, -0.06, 0.1].map { rgb(hue: hue + $0, saturation: 0.7, brightness: 0.8) }
        }
        guard !colors.isEmpty else { return [] }
        while colors.count < 4 { colors.append(colors[colors.count % max(colors.count, 1)]) }
        return colors.map { color in
            let deep = deepened(saturated(color, by: 1.6), maximum: 0.2)
            return Color(red: deep.red, green: deep.green, blue: deep.blue)
        }
    }

    /// The cover at a few dozen pixels, where it can be fetched as a picture: enough for its
    /// colours, or to stretch soft across a whole screen. Nil for a library cover only
    /// MusicKit can draw, and for no cover.
    static func smallImage(for cover: CoverArt, pixels: Int) async -> CGImage? {
        let url: URL? = switch cover {
        case .artwork(let artwork): CoverImage.loadableURL(of: artwork, pixels: pixels)
        case .url(let address, _): address.flatMap(URL.init(string:))
        }
        guard let url else { return nil }
        return await ArtworkImages.shared.image(for: ArtworkImages.Key(url: url, pixels: pixels))
    }

    /// The cover drawn into four pixels, one for each quarter.
    private static func quarters(of image: CGImage) -> [RGB] {
        var pixels = [UInt8](repeating: 0, count: 16)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
            return true
        }
        guard drawn else { return [] }
        return (0..<4).map { index in
            (Double(pixels[index * 4]) / 255, Double(pixels[index * 4 + 1]) / 255, Double(pixels[index * 4 + 2]) / 255)
        }
    }

    private static func components(of cgColor: CGColor) -> RGB? {
        guard let rgb = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = rgb.components, components.count >= 3
        else { return nil }
        return (components[0], components[1], components[2])
    }

    /// Pushes each channel away from the grey of the colour's mean.
    static func saturated(_ color: RGB, by boost: Double) -> RGB {
        let mean = (color.red + color.green + color.blue) / 3
        return (
            min(1, max(0, mean + (color.red - mean) * boost)),
            min(1, max(0, mean + (color.green - mean) * boost)),
            min(1, max(0, mean + (color.blue - mean) * boost))
        )
    }

    /// Scales the colour down until it's dark enough, keeping its hue. A little saturation is
    /// added first, since an average of a whole cover comes out greyer than the cover looks.
    static func deepened(_ color: RGB, maximum: Double = maximumLuminance) -> RGB {
        let mean = (color.red + color.green + color.blue) / 3
        let boost = 1.3
        let (r, g, b) = (
            min(1, max(0, mean + (color.red - mean) * boost)),
            min(1, max(0, mean + (color.green - mean) * boost)),
            min(1, max(0, mean + (color.blue - mean) * boost))
        )
        // Luminance isn't linear in the channels, so step down until it fits.
        var scale = 1.0
        while relativeLuminance(r * scale, g * scale, b * scale) > maximum, scale > 0.02 {
            scale -= 0.02
        }
        return (r * scale, g * scale, b * scale)
    }

    /// HSB to RGB, as `UIColor(hue:saturation:brightness:alpha:)` converts it, without a
    /// platform colour type.
    static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGB {
        let sector = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let low = brightness - chroma
        let (r, g, b): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return (r + low, g + low, b + low)
    }

    static func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// The cover drawn into a single pixel.
    private static func average(of image: CGImage) -> RGB? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { bytes -> Bool in
            // The context writes into the buffer only while it's lent here.
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}
