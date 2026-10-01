// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "FolioCore"),
        .executableTarget(
            name: "FolioApp",
            dependencies: ["FolioCore"],
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "FolioCoreTests", dependencies: ["FolioCore"]),
    ]
)
