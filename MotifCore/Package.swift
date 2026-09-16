// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MotifCore",
    // PackageDescription has no `.v27` case yet, so these use the string form. The apps
    // themselves target iOS 27 / macOS 27 via Config/Motif.xcconfig.
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "MotifCore", targets: ["MotifCore"]),
        .library(name: "MotifMusic", targets: ["MotifMusic"]),
    ],
    targets: [
        // Pure logic and models. No MusicKit, so it builds and tests without an
        // Apple Music subscription or a device. Library code is `nonisolated`;
        // callers decide where it runs.
        .target(
            name: "MotifCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Everything that touches MusicKit lives here, behind the protocols
        // declared in MotifCore.
        .target(
            name: "MotifMusic",
            dependencies: ["MotifCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MotifCoreTests",
            dependencies: ["MotifCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "MotifMusicTests",
            dependencies: ["MotifMusic"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
