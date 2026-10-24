// swift-tools-version: 6.0
import PackageDescription

// SwiftPM builds ScreentimeCore for `swift test`. The app itself is built
// from project.yml with XcodeGen; both compile the same Core sources.
let package = Package(
    name: "Screentime",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ScreentimeCore", targets: ["ScreentimeCore"])
    ],
    targets: [
        .target(
            name: "ScreentimeCore",
            path: "Sources/ScreentimeCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "ScreentimeCoreTests",
            dependencies: ["ScreentimeCore"],
            path: "Tests/ScreentimeCoreTests"
        ),
    ]
)

for target in package.targets {
    target.swiftSettings = [.swiftLanguageMode(.v5)]
}
