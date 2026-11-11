import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct LayersTests {
    func shipped() throws -> KeysFile { try KeysFile(text: fixture("keys.toml")) }

    @Test func shippedFileLayers() throws {
        let layers = Layers.build(from: try shipped()) { _ in "App" }
        #expect(layers.map(\.title) == ["Hyper", "Option", "Option+Shift", "Service"])
        #expect(layers.map(\.id) == ["hyper", "alt", "alt-shift", "mode:service"])
        // No launchers ship; the Hyper layer holds the two links into the app.
        #expect(layers[0].bindings.keys.sorted() == ["k", "space"])
        #expect(layers[0].bindings["space"]?.source == .aerospace(mode: "main", key: "hyper-space"))
        #expect(layers[0].bindings["k"]?.conflict == false)
        let option = layers[1].bindings
        #expect(option["1"]?.label == "ws 1")
        #expect(option["1"]?.kind == .workspace)
        #expect(option["h"]?.label == "← focus")
        #expect(option["h"]?.kind == .focusMove)
        #expect(option["slash"]?.label == "tiles")
        #expect(layers[2].bindings["semicolon"]?.label == "service")
        #expect(layers[2].bindings["semicolon"]?.kind == .mode)
        #expect(layers[3].bindings["r"]?.label == "reset layout")
        #expect(layers[3].bindings["esc"]?.label == "reload")
        // modified keys in a mode are keyed by the full shortcut
        #expect(layers[3].bindings["alt-shift-h"]?.label == "join ←")
        #expect(layers[3].bindings["h"] == nil)
    }

    @Test func launcherConflict() throws {
        var keys = try shipped()
        keys.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        keys.setBinding(mode: "main", key: "hyper-t", value: .string("workspace 3"))
        let layers = Layers.build(from: keys) { _ in "Ghostty" }
        let t = layers[0].bindings["t"]
        #expect(t?.conflict == true)
        #expect(t?.kind == .launcher)
        #expect(t?.label == "Ghostty")
        #expect(t?.source == .launcher(bundleID: "com.mitchellh.ghostty"))
    }

    @Test func missingApp() throws {
        var keys = try shipped()
        keys.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        let layers = Layers.build(from: keys) { _ in nil }
        #expect(layers[0].bindings["t"]?.missingApp == true)
        #expect(layers[0].bindings["t"]?.label == "ghostty")
        #expect(layers[0].bindings["t"]?.conflict == false)
    }

    @Test func otherModifierSetsAndHyperBindings() throws {
        var keys = try shipped()
        keys.setBinding(mode: "main", key: "ctrl-alt-x", value: .string("close"))
        keys.setBinding(mode: "main", key: "hyper-w", value: .string("workspace 2"))
        let layers = Layers.build(from: keys) { _ in nil }
        #expect(layers.map(\.id) == ["hyper", "alt", "alt-shift", "ctrl-alt", "mode:service"])
        #expect(layers[3].title == "⌃⌥")
        #expect(layers[3].bindings["x"]?.label == "close")
        #expect(layers[3].bindings["x"]?.kind == .other)
        #expect(layers[0].bindings["w"]?.label == "ws 2")
        #expect(layers[0].bindings["w"]?.conflict == false)
    }

    @Test func labels() {
        func l(_ s: String) -> String { CommandLabel.label(.string(s)).0 }
        #expect(l("move-node-to-workspace 4") == "→ ws 4")
        #expect(l("workspace-back-and-forth") == "back & forth")
        #expect(l("move-workspace-to-monitor --wrap-around next") == "→ monitor")
        #expect(l("move up") == "↑ move")
        #expect(l("resize smart -50") == "resize −")
        #expect(l("resize smart +50") == "resize +")
        #expect(l("layout accordion horizontal vertical") == "accordion")
        #expect(l("layout floating tiling") == "float/tile")
        #expect(l("mode service") == "service")
        #expect(l("close --quit-if-last-window") == "close")
        #expect(CommandLabel.label(.array(["mode main"])).0 == "main")
        #expect(CommandLabel.label(.array(["close-all-windows-but-current", "mode main"])) == ("close others", .mode))
        #expect(CommandLabel.label(.array(["layout floating tiling", "mode main"])) == ("float/tile", .layout))
    }

    @Test func tintsArePaletteKeys() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() } // up to project-grove
        let file = url.appendingPathComponent("grove-dotfiles/theme/everforest-dark-medium")
        let text = try String(contentsOf: file, encoding: .utf8)
        var names: Set<String> = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[1].hasPrefix("#") { names.insert(parts[0]) }
        }
        #expect(names.contains("green"))
        for kind in [BindingKind.workspace, .focusMove, .launcher, .layout, .mode, .other] {
            #expect(names.contains(kind.tint), "\(kind) tint \(kind.tint)")
        }
    }
}
