// swift-tools-version:6.0
import Foundation
import PackageDescription

// Command Line Tools Swift 6.4 (swiftbuild) sometimes leaves the Testing macro
// plugin out of the test target's compile ("plugin for module 'TestingMacros'
// not found"), so roughly every other `swift test` fails. Naming its folder
// makes it reliable; skipped when the folder isn't there (e.g. under Xcode).
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

let package = Package(
    name: "GroveThemes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GroveThemes", targets: ["GroveThemes"]),
        .library(name: "GroveThemesCore", targets: ["GroveThemesCore"]),
        // What the Grove apps' views share: Grove Keys builds on it too.
        .library(name: "GroveUI", targets: ["GroveUI"]),
    ],
    targets: [
        .target(name: "GroveThemesCore"),
        .target(name: "GroveUI", dependencies: ["GroveThemesCore"]),
        .executableTarget(name: "GroveThemes", dependencies: ["GroveThemesCore", "GroveUI"]),
        .testTarget(
            name: "GroveThemesCoreTests",
            dependencies: ["GroveThemesCore"],
            exclude: ["Fixtures"],
            swiftSettings: testSettings
        ),
        .testTarget(name: "GroveUITests", dependencies: ["GroveUI", "GroveThemesCore"], swiftSettings: testSettings),
    ]
)
