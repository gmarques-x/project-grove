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
    name: "GroveKeys",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GroveKeys", targets: ["GroveKeys"]),
        .library(name: "GroveKeysCore", targets: ["GroveKeysCore"]),
    ],
    dependencies: [
        .package(path: "../deps/grove-themes"),
    ],
    targets: [
        .target(
            name: "GroveKeysCore",
            dependencies: [.product(name: "GroveThemesCore", package: "grove-themes")]
        ),
        .executableTarget(name: "GroveKeys", dependencies: ["GroveKeysCore"]),
        .testTarget(
            name: "GroveKeysCoreTests",
            dependencies: ["GroveKeysCore"],
            exclude: ["Fixtures"],
            swiftSettings: testSettings
        ),
    ]
)
