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

// The app's resources are the Grove Icons font and map, copied in from
// grove-dotfiles by make-resources.sh (the folder is git-ignored). Without
// them the build stops here and says so, rather than at "resource not found".
let resources = Context.packageDirectory + "/Sources/GroveExplorer/Resources"
for file in ["seti.woff", "grove-icon-theme.json"] where !FileManager.default.fileExists(atPath: resources + "/" + file) {
    fatalError("Grove Explorer's resources are missing (\(file)): run grove-explorer/app/make-resources.sh, then build again")
}

let package = Package(
    name: "GroveExplorer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GroveExplorer", targets: ["GroveExplorer"]),
        .library(name: "GroveExplorerCore", targets: ["GroveExplorerCore"]),
    ],
    dependencies: [
        .package(path: "../deps/grove-themes"),
    ],
    targets: [
        .target(
            name: "GroveExplorerCore",
            dependencies: [.product(name: "GroveThemesCore", package: "grove-themes")]
        ),
        .executableTarget(
            name: "GroveExplorer",
            dependencies: [
                "GroveExplorerCore",
                .product(name: "GroveUI", package: "grove-themes"),
                .product(name: "GroveThemesCore", package: "grove-themes"),
            ],
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "GroveExplorerCoreTests",
            dependencies: ["GroveExplorerCore"],
            exclude: ["Fixtures"],
            swiftSettings: testSettings
        ),
    ]
)
