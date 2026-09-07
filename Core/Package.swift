// swift-tools-version: 6.0
import PackageDescription

// Every piece of logic that is not a pixel lives here, and the package builds for macOS as
// well as the two shipping platforms. That is not tidiness: AVFoundation is the same
// framework on macOS, so the genuinely novel mechanics — the Plex handshake, joining a
// programme already in progress, cutting an item at a schedule boundary rather than at
// end-of-file — are exercised by `swift test` in seconds, with no simulator involved.
let package = Package(
    name: "Tub3Core",
    platforms: [.tvOS(.v18), .iOS(.v18), .macOS(.v14)],
    products: [.library(name: "Tub3Core", targets: ["Tub3Core"])],
    targets: [
        .target(name: "Tub3Core"),
        .testTarget(name: "Tub3CoreTests", dependencies: ["Tub3Core"],
                    resources: [.copy("Fixtures")]),
    ]
)
