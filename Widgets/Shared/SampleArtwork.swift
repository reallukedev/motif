import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Drawn covers for the sample songs in the widget gallery, so it doesn't show a column of
/// placeholders or someone else's album art. Rendered to PNG data like any other cover.
enum SampleArtwork {
    static func cover(hue: Double) -> Data? {
        let renderer = ImageRenderer(content: SampleCover(hue: hue))
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

private struct SampleCover: View {
    let hue: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.45, brightness: 0.98),
                    Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.62),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.22))
                .frame(width: 34, height: 34)
                .offset(x: 12, y: 10)
        }
        .frame(width: 56, height: 56)
    }
}
