// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TeXMessages",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "TeXMessages",
            path: "Sources/TeXMessages",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
