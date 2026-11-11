import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct BindingsEditTests {
    func shipped() throws -> KeysFile { try KeysFile(text: fixture("keys.toml")) }

    // NSEvent.ModifierFlags raw values.
    let shift: UInt = 1 << 17, ctrl: UInt = 1 << 18, alt: UInt = 1 << 19, cmd: UInt = 1 << 20

    @Test func conflictMarksTheAeroSpaceSide() throws {
        var f = try shipped()
        #expect(Layers.conflictingAerospaceKeys(f).isEmpty)
        f.setBinding(mode: "main", key: "hyper-t", value: .string("workspace 3"))
        f.setBinding(mode: "main", key: "cmd-ctrl-alt-shift-b", value: .string("workspace 4"))
        f.setBinding(mode: "main", key: "hyper-q", value: .string("workspace 5"))
        f.setBinding(mode: "service", key: "hyper-t", value: .string("workspace 6"))
        f.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        f.setLaunch(key: "b", bundleID: "com.google.Chrome")
        #expect(Layers.conflictingAerospaceKeys(f) == ["hyper-t", "cmd-ctrl-alt-shift-b"])
        #expect(Layers.conflictingLaunchKeys(f) == ["t", "b"])
    }

    @Test func recorderBuildsAShortcut() {
        #expect(Shortcut(keyCode: 18, flags: alt) == Shortcut(aerospace: "alt-1"))
        #expect(Shortcut(keyCode: 18, flags: alt | shift)?.aerospace == "alt-shift-1")
        #expect(Shortcut(keyCode: 17, flags: cmd | ctrl | alt | shift)?.aerospace == "hyper-t")
        // Caps Lock, Fn and device bits are ignored.
        #expect(Shortcut(keyCode: 53, flags: 1 << 16 | 1 << 23 | 0x100)?.aerospace == "esc")
        #expect(Shortcut(keyCode: 122, flags: alt) == nil)  // F1 has no AeroSpace name here
    }

    @Test func clashesInTheSameLayer() throws {
        var f = try shipped()
        let alt2 = BindingSlot.binding(mode: "main", key: "alt-2")
        #expect(f.clashes(.binding(mode: "main", key: "alt-1"), except: alt2) == [.binding(mode: "main", key: "alt-1")])
        #expect(f.clashes(.binding(mode: "main", key: "alt-1"), except: .binding(mode: "main", key: "alt-1")).isEmpty)
        #expect(f.clashes(.binding(mode: "main", key: "alt-q"), except: nil).isEmpty)
        // Another mode is another layer.
        #expect(f.clashes(.binding(mode: "service", key: "alt-1"), except: nil).isEmpty)
        // Hyper: launchers and hyper- bindings share a layer; spelled-out modifiers match.
        f.setBinding(mode: "main", key: "cmd-ctrl-alt-shift-t", value: .string("workspace 3"))
        f.setLaunch(key: "b", bundleID: "com.google.Chrome")
        #expect(f.clashes(.launcher(key: "t"), except: nil) == [.binding(mode: "main", key: "cmd-ctrl-alt-shift-t")])
        #expect(f.clashes(.binding(mode: "main", key: "hyper-t"), except: nil) == [.binding(mode: "main", key: "cmd-ctrl-alt-shift-t")])
        #expect(f.clashes(.binding(mode: "main", key: "hyper-b"), except: nil) == [.launcher(key: "b")])
        #expect(f.clashes(.launcher(key: "b"), except: .launcher(key: "b")).isEmpty)
        #expect(f.clashes(.launcher(key: "b"), except: .launcher(key: "x")) == [.launcher(key: "b")])
    }

    @Test func slotForARecording() {
        let t = Shortcut(aerospace: "hyper-t")!
        #expect(BindingSlot.recorded(t, launcher: true, mode: "main") == .launcher(key: "t"))
        #expect(BindingSlot.recorded(Shortcut(aerospace: "alt-t")!, launcher: true, mode: "main") == .launcher(key: "t"))
        #expect(BindingSlot.recorded(t, launcher: false, mode: "main") == .binding(mode: "main", key: "hyper-t"))
        #expect(BindingSlot.recorded(Shortcut(aerospace: "r")!, launcher: false, mode: "service") == .binding(mode: "service", key: "r"))
    }

    @Test func moveKeepsTheValueAndPlace() throws {
        var f = try shipped()
        f.move(.binding(mode: "main", key: "alt-h"), to: .binding(mode: "main", key: "alt-y"), replacing: [])
        let main = f.modes[0].bindings
        #expect(main[2].key == "alt-y" && main[2].value == .string("focus left"))
        #expect(!main.contains { $0.key == "alt-h" })
        // Replace: the clashing binding goes.
        f.move(.binding(mode: "main", key: "alt-y"), to: .binding(mode: "main", key: "alt-1"),
               replacing: [.binding(mode: "main", key: "alt-1")])
        let after = f.modes[0].bindings
        #expect(after.filter { $0.key == "alt-1" }.map(\.value) == [.string("focus left")])
        #expect(after.count == 34)
    }

    @Test func moveALauncher() throws {
        var f = try shipped()
        f.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        f.setBinding(mode: "main", key: "hyper-g", value: .string("workspace 3"))
        f.move(.launcher(key: "t"), to: .launcher(key: "g"), replacing: f.clashes(.launcher(key: "g"), except: .launcher(key: "t")))
        #expect(f.launch.map(\.key) == ["g"])
        #expect(f.launch.first?.bundleID == "com.mitchellh.ghostty")
        #expect(!f.modes[0].bindings.contains { $0.key == "hyper-g" })
    }

    @Test func addAndRemove() throws {
        var f = try shipped()
        f.add(.binding(mode: "main", key: "alt-q"), command: "close", replacing: [])
        #expect(f.modes[0].bindings.last?.key == "alt-q")
        #expect(f.modes[0].bindings.last?.value == .string("close"))
        f.add(.binding(mode: "service", key: "q"), command: " close ,  mode main ", replacing: [])
        #expect(f.modes[1].bindings.last?.value == .array(["close", "mode main"]))
        f.add(.binding(mode: "main", key: "alt-w"), command: "  ", replacing: [])
        #expect(!f.modes[0].bindings.contains { $0.key == "alt-w" })
        f.add(.launcher(key: "t"), bundleID: "com.mitchellh.ghostty", replacing: [])
        #expect(f.launch.map(\.key) == ["t"])

        // A folded row stands for nine keys: removing it removes all nine.
        let ws = BindingRows.rows(mode: f.modes[0].bindings, folded: true).first { $0.count == 9 }!
        f.remove(ws.keys.map { .binding(mode: "main", key: $0) })
        #expect(!f.modes[0].bindings.contains { $0.key.hasPrefix("alt-") && $0.value == .string("workspace 1") })
        #expect(f.modes[0].bindings.count == 36 - 9)
        f.remove([.launcher(key: "t")])
        #expect(f.launch.isEmpty)
    }

    @Test func editTheCommand() throws {
        var f = try shipped()
        f.setCommand(.binding(mode: "service", key: "r"), "flatten-workspace-tree, mode main")
        #expect(f.modes[1].bindings[1].value == .array(["flatten-workspace-tree", "mode main"]))
        f.setCommand(.binding(mode: "main", key: "alt-h"), "focus --boundaries all-monitors-outer-frame left")
        #expect(f.modes[0].bindings[2].value == .string("focus --boundaries all-monitors-outer-frame left"))
        let before = f
        f.setCommand(.binding(mode: "main", key: "alt-h"), "")
        #expect(f == before)
        #expect(BindingRows.value(fromText: "a, b") == .array(["a", "b"]))
        #expect(BindingRows.value(fromText: " workspace 1 ") == .string("workspace 1"))
        #expect(BindingRows.value(fromText: " , ") == nil)
    }

    /// A bare or shift-only key in main would be taken from every app.
    @Test func mainNeedsCtrlAltOrCmd() throws {
        #expect(Shortcut(aerospace: "alt-1")!.isSafeForMain)
        #expect(Shortcut(aerospace: "ctrl-q")!.isSafeForMain)
        #expect(Shortcut(aerospace: "cmd-shift-q")!.isSafeForMain)
        #expect(Shortcut(aerospace: "hyper-t")!.isSafeForMain)
        #expect(!Shortcut(aerospace: "q")!.isSafeForMain)
        #expect(!Shortcut(aerospace: "shift-q")!.isSafeForMain)
        #expect(BindingSlot.binding(mode: "main", key: "alt-q").isSafe)
        #expect(!BindingSlot.binding(mode: "main", key: "shift-q").isSafe)
        #expect(BindingSlot.binding(mode: "service", key: "q").isSafe)
        #expect(BindingSlot.launcher(key: "q").isSafe)

        // Core refuses them too.
        var f = try shipped()
        let before = f
        f.add(.binding(mode: "main", key: "q"), command: "close", replacing: [])
        f.move(.binding(mode: "main", key: "alt-h"), to: .binding(mode: "main", key: "shift-h"), replacing: [])
        #expect(f == before)
        f.add(.binding(mode: "service", key: "q"), command: "close", replacing: [])
        #expect(f.modes[1].bindings.last?.key == "q")
    }

    /// The launcher Replace path (the app picker's `assign`) removes the
    /// clashing Hyper binding, spelled out or not, and overwrites a launcher.
    @Test func launcherReplaceRemovesTheHyperBinding() throws {
        var f = try shipped()
        f.setBinding(mode: "main", key: "cmd-ctrl-alt-shift-g", value: .string("workspace 3"))
        #expect(f.clashes(.launcher(key: "g"), except: nil) == [.binding(mode: "main", key: "cmd-ctrl-alt-shift-g")])
        f.assign(.launcher(bundleID: "com.mitchellh.ghostty"), layerID: "hyper", shortcut: "hyper-g")
        #expect(f.clashes(.launcher(key: "g"), except: nil) == [.launcher(key: "g")])
        #expect(!f.modes[0].bindings.contains { $0.key == "cmd-ctrl-alt-shift-g" })
        f.assign(.launcher(bundleID: "com.google.Chrome"), layerID: "hyper", shortcut: "hyper-g")
        #expect(f.launch.map(\.bundleID) == ["com.google.Chrome"])
    }

    @Test func millisecondFields() {
        #expect(HyperSettings.milliseconds("200") == 200)
        #expect(HyperSettings.milliseconds(" 0 ") == 0)
        #expect(HyperSettings.milliseconds("350 ms") == 350)
        #expect(HyperSettings.milliseconds("-5") == nil)
        #expect(HyperSettings.milliseconds("") == nil)
        #expect(HyperSettings.milliseconds("2.5") == nil)
        #expect(HyperSettings.milliseconds("abc") == nil)
    }

    @Test func monitorChoices() {
        #expect(Monitors.choices(displays: ["Built-in Retina Display"], current: []) ==
            ["main", "secondary", "built-in", "Built-in Retina Display"])
        // A saved target that isn't connected now stays choosable; no duplicates.
        #expect(Monitors.choices(displays: ["LG UltraFine", "LG UltraFine"], current: ["main", "Studio Display"]) ==
            ["main", "secondary", "built-in", "LG UltraFine", "Studio Display"])
    }
}
