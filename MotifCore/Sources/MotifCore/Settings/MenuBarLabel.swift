import Foundation

/// What the menu bar shows for the song that's playing.
public enum MenuBarLabelStyle: String, CaseIterable, Sendable, Codable, Identifiable {
    case radio
    case note
    case artwork
    case title
    case artist
    case artworkAndTitle
    case custom

    public var id: String { rawValue }

    /// What the menu bar shows until someone picks something else.
    public static let `default` = MenuBarLabelStyle.note

    /// The style for a stored value, or ``default`` when nothing valid is stored.
    public init(stored: String?) {
        // "icon" was the radio style's name before the symbol became a choice of two.
        if stored == "icon" {
            self = .radio
            return
        }
        self = stored.flatMap(Self.init(rawValue:)) ?? .default
    }

    public var name: String {
        switch self {
        case .radio: "Radio"
        case .note: "Note"
        case .artwork: "Album cover"
        case .title: "Song title"
        case .artist: "Artist"
        case .artworkAndTitle: "Cover and title"
        case .custom: "Custom"
        }
    }

    /// Whether this style draws the album cover.
    public var showsArtwork: Bool { self == .artwork || self == .artworkAndTitle }

    /// The symbol this style draws. Only the two symbol styles have one.
    public var symbol: String? {
        switch self {
        case .radio: "radio"
        case .note: "music.note"
        case .artwork, .artworkAndTitle, .title, .artist, .custom: nil
        }
    }

    /// The filled variant, used while capture is running, where the symbol has one.
    public func symbol(isCapturing: Bool) -> String? {
        guard let symbol else { return nil }
        return isCapturing && self == .radio ? "radio.fill" : symbol
    }

    /// Drawn when a text style has no text yet, so the status item never ends up empty and
    /// unclickable.
    public static let fallbackSymbol = "music.note"
}

/// Fills in a user-written format string, like `{title} · {artist}`, from the song that's
/// playing. Plain token substitution, so the result is predictable.
public enum MenuBarLabelFormat {
    public static let `default` = "{title} · {artist}"

    /// Every token. The settings screen lists these.
    public static let tokens = ["{title}", "{artist}", "{album}", "{station}"]

    /// Longest label before it's cut.
    ///
    /// At 40 characters ("Burn The Hard Drive (feat. Mura Masa)") macOS hid Motif behind the
    /// menu bar's overflow chevron. 24 fits most song titles.
    public static let characterLimit = 24

    public static func render(
        _ format: String,
        title: String,
        artist: String,
        album: String? = nil,
        station: String? = nil,
        limit: Int = characterLimit
    ) -> String {
        var text = format
        for (token, value) in [
            ("{title}", title),
            ("{artist}", artist),
            ("{album}", album ?? ""),
            ("{station}", station ?? ""),
        ] {
            text = text.replacingOccurrences(of: token, with: value, options: .caseInsensitive)
        }
        return truncate(tidy(text), to: limit)
    }

    /// Cleans up after empty tokens: collapses runs of spaces and drops separators at either
    /// end, so `{title} · {artist}` with no artist renders "Song", not "Song ·".
    static func tidy(_ text: String) -> String {
        var result = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let separators: Set<Character> = ["-", "\u{2014}", "\u{2013}", "|", "·", "•", ",", ":"]
        while let first = result.first, separators.contains(first) || first.isWhitespace {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        while let last = result.last, separators.contains(last) || last.isWhitespace {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// Cuts on a word boundary where there is one.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let clipped = String(text.prefix(limit - 1))
        let onWord = clipped.lastIndex(of: " ").map { String(clipped[clipped.startIndex..<$0]) }
        return (onWord?.isEmpty == false ? onWord! : clipped) + "…"
    }
}
