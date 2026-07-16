// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexIsland",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CodexIsland", targets: ["CodexIsland"])
    ],
    targets: [
        .executableTarget(
            name: "CodexIsland"
        )
    ],
    swiftLanguageModes: [.v5]
)
