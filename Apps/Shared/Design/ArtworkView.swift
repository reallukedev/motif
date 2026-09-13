import SwiftUI

/// Album art, with a generated cover underneath for songs that don't have one (yet).
///
/// The generated cover is seeded from the album or song name, so the same album always gets
/// the same colours and a list of uncovered songs doesn't look like a column of grey boxes.
struct ArtworkView: View {
    let url: String?
    /// Usually the album name, falling back to title and artist.
    let seed: String
    var size: CGFloat
    var isCircle = false

    var body: some View {
        ZStack {
            GeneratedCover(seed: seed)
            if let url, let resolved = URL(string: url) {
                AsyncImage(url: resolved, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { shape.stroke(.primary.opacity(0.08), lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private var shape: AnyShape {
        isCircle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: max(4, size * 0.12), style: .continuous))
    }
}

/// A simple abstract cover: a two-tone gradient and one soft shape, all derived from a hash.
struct GeneratedCover: View {
    let seed: String

    var body: some View {
        let hash = Self.hash(seed)
        let hue = Double(hash % 360) / 360
        let shift = 0.06 + Double((hash >> 9) % 18) / 100
        let motif = (hash >> 17) % 4

        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let top = Color(hue: hue, saturation: 0.55, brightness: 0.95)
            let bottom = Color(hue: (hue + shift).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.55)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [top, bottom]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: size.height)
            ))

            let light = GraphicsContext.Shading.color(.white.opacity(0.22))
            let w = size.width
            switch motif {
            case 0:
                context.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: w * 0.32, width: w * 0.8, height: w * 0.8)), with: light)
            case 1:
                for index in 0..<4 {
                    let inset = w * (0.18 + Double(index) * 0.14)
                    let ring = Path(ellipseIn: rect.insetBy(dx: inset, dy: inset).offsetBy(dx: w * 0.28, dy: w * 0.28))
                    context.stroke(ring, with: light, lineWidth: max(1, w * 0.035))
                }
            case 2:
                var stripes = Path()
                for index in stride(from: -1.0, through: 2.0, by: 0.22) {
                    stripes.move(to: CGPoint(x: w * index, y: w))
                    stripes.addLine(to: CGPoint(x: w * (index + 1), y: 0))
                }
                context.stroke(stripes, with: .color(.white.opacity(0.14)), lineWidth: max(1, w * 0.06))
            default:
                var wave = Path()
                wave.move(to: CGPoint(x: 0, y: w * 0.62))
                wave.addCurve(
                    to: CGPoint(x: w, y: w * 0.5),
                    control1: CGPoint(x: w * 0.35, y: w * 0.35),
                    control2: CGPoint(x: w * 0.6, y: w * 0.85)
                )
                wave.addLine(to: CGPoint(x: w, y: w))
                wave.addLine(to: CGPoint(x: 0, y: w))
                wave.closeSubpath()
                context.fill(wave, with: light)
            }
        }
    }

    /// FNV-1a. `hashValue` changes between launches, which would reshuffle every colour.
    static func hash(_ string: String) -> Int {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        return Int(value & 0x7FFF_FFFF)
    }
}

#Preview {
    HStack {
        ForEach(["Tides", "Glasshouse", "Northbound", "Soft Focus"], id: \.self) {
            ArtworkView(url: nil, seed: $0, size: 80)
        }
        ArtworkView(url: nil, seed: "Mara Solis", size: 80, isCircle: true)
    }
    .padding()
}
