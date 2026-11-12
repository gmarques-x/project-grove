import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct KeyEditTests {
    func shipped() throws -> KeysFile { try KeysFile(text: fixture("keys.toml")) }

    @Test func readsWhatAKeyDoes() throws {
        var f = try shipped()
        #expect(f.action(layerID: "alt", shortcut: "alt-1") == .aerospace(command: "workspace 1"))
        #expect(f.action(layerID: "alt", shortcut: "alt-q") == KeyAction.none)
        #expect(f.action(layerID: "mode:service", shortcut: "r") == .aerospace(command: "flatten-workspace-tree"))
        f.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        #expect(f.action(layerID: "hyper", shortcut: "hyper-t") == .launcher(bundleID: "com.mitchellh.ghostty"))
        #expect(f.savedLine(layerID: "alt", shortcut: "alt-1") == "alt-1 = \"workspace 1\"")
        #expect(f.savedLine(layerID: "hyper", shortcut: "hyper-t") == "t = \"com.mitchellh.ghostty\"")
        #expect(f.savedLine(layerID: "alt", shortcut: "alt-q") == nil)
    }

    /// A key written with spelled-out modifiers is found and rewritten in place.
    @Test func matchesSpelledOutHyper() throws {
        var f = try shipped()
        f.setBinding(mode: "main", key: "cmd-ctrl-alt-shift-f", value: .string("fullscreen"))
        #expect(f.action(layerID: "hyper", shortcut: "hyper-f") == .aerospace(command: "fullscreen"))
        f.assign(.aerospace(command: "close"), layerID: "hyper", shortcut: "hyper-f")
        let main = f.modes.first { $0.name == "main" }!.bindings
        #expect(main.contains { $0.key == "cmd-ctrl-alt-shift-f" && $0.value == .string("close") })
        #expect(!main.contains { $0.key == "hyper-f" })
    }

    @Test func launcherReplacesAHyperBindingAndBack() throws {
        var f = try shipped()
        f.assign(.aerospace(command: "workspace 3"), layerID: "hyper", shortcut: "hyper-t")
        f.assign(.launcher(bundleID: "com.mitchellh.ghostty"), layerID: "hyper", shortcut: "hyper-t")
        #expect(f.launch.map(\.key) == ["t"])
        #expect(!f.modes[0].bindings.contains { $0.key == "hyper-t" })
        f.assign(.aerospace(command: "workspace 3"), layerID: "hyper", shortcut: "hyper-t")
        #expect(f.launch.isEmpty)
        #expect(f.modes[0].bindings.contains { $0.key == "hyper-t" && $0.value == .string("workspace 3") })
        f.assign(.none, layerID: "hyper", shortcut: "hyper-t")
        #expect(f.action(layerID: "hyper", shortcut: "hyper-t") == KeyAction.none)
    }

    @Test func launcherOnlyOnHyper() throws {
        var f = try shipped()
        f.assign(.launcher(bundleID: "com.mitchellh.ghostty"), layerID: "alt", shortcut: "alt-t")
        #expect(f == (try shipped()))
    }

    @Test func noneRemoves() throws {
        var f = try shipped()
        f.assign(.none, layerID: "alt", shortcut: "alt-1")
        #expect(!f.modes[0].bindings.contains { $0.key == "alt-1" })
        f.assign(.none, layerID: "mode:service", shortcut: "alt-shift-h")
        #expect(!f.modes[1].bindings.contains { $0.key == "alt-shift-h" })
    }

    @Test func blankCommandChangesNothing() throws {
        var f = try shipped()
        f.assign(.aerospace(command: "  "), layerID: "alt", shortcut: "alt-1")
        #expect(f == (try shipped()))
    }

    /// In a non-main mode a command goes back to main afterwards, as the shipped
    /// service bindings do, unless it is itself a mode switch or the key was a
    /// plain string before.
    @Test func serviceCommandsReturnToMain() throws {
        var f = try shipped()
        f.assign(.aerospace(command: "close"), layerID: "mode:service", shortcut: "c")
        f.assign(.aerospace(command: "fullscreen"), layerID: "mode:service", shortcut: "r")
        f.assign(.aerospace(command: "mode main"), layerID: "mode:service", shortcut: "q")
        f.setBinding(mode: "service", key: "x", value: .string("focus left"))
        f.assign(.aerospace(command: "focus right"), layerID: "mode:service", shortcut: "x")
        let service = Dictionary(uniqueKeysWithValues: f.modes[1].bindings.map { ($0.key, $0.value) })
        #expect(service["c"] == .array(["close", "mode main"]))
        #expect(service["r"] == .array(["fullscreen", "mode main"]))
        #expect(service["q"] == .string("mode main"))
        #expect(service["x"] == .string("focus right"))
        f.assign(.aerospace(command: "workspace 2"), layerID: "alt", shortcut: "alt-1")
        #expect(f.modes[0].bindings.first { $0.key == "alt-1" }?.value == .string("workspace 2"))
    }

    /// What choosing the other kind on a Hyper key would remove, for the
    /// editor's "Replaces …" line.
    @Test func whatAssigningReplaces() throws {
        var f = try shipped()
        #expect(f.replaced(byLauncher: true, layerID: "hyper", shortcut: "hyper-t") == nil)
        f.setBinding(mode: "main", key: "hyper-t", value: .string("workspace 1"))
        #expect(f.replaced(byLauncher: true, layerID: "hyper", shortcut: "hyper-t") == .aerospace(command: "workspace 1"))
        #expect(f.replaced(byLauncher: false, layerID: "hyper", shortcut: "hyper-t") == nil)
        f.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")  // both: a hand-made conflict
        #expect(f.replaced(byLauncher: false, layerID: "hyper", shortcut: "hyper-t") == .launcher(bundleID: "com.mitchellh.ghostty"))
        #expect(f.replaced(byLauncher: true, layerID: "hyper", shortcut: "hyper-t") == .aerospace(command: "workspace 1"))
        // Outside Hyper nothing is replaced.
        #expect(f.replaced(byLauncher: false, layerID: "alt", shortcut: "alt-1") == nil)
    }

    /// A main-mode AeroSpace binding without ⌃, ⌥ or ⌘ would take the key
    /// from typing everywhere: the Keyboard tab refuses it, as Bindings does.
    @Test func refusesUnsafeMainModeCommands() throws {
        var f = try shipped()
        let before = f
        #expect(!KeysFile.canAssignCommand(layerID: "none", shortcut: "q"))
        #expect(!KeysFile.canAssignCommand(layerID: "shift", shortcut: "shift-q"))
        #expect(KeysFile.canAssignCommand(layerID: "alt", shortcut: "alt-q"))
        #expect(KeysFile.canAssignCommand(layerID: "hyper", shortcut: "hyper-q"))
        #expect(KeysFile.canAssignCommand(layerID: "mode:service", shortcut: "q"))
        f.assign(.aerospace(command: "workspace 1"), layerID: "none", shortcut: "q")
        f.assign(.aerospace(command: "workspace 1"), layerID: "shift", shortcut: "shift-q")
        #expect(f == before)
        f.assign(.aerospace(command: "workspace 1"), layerID: "alt", shortcut: "alt-q")
        #expect(f.action(layerID: "alt", shortcut: "alt-q") == .aerospace(command: "workspace 1"))
    }

    /// An unsafe binding written by hand can still be cleared.
    @Test func unsafeMainModeBindingCanBeRemoved() throws {
        var f = try shipped()
        f.setBinding(mode: "main", key: "q", value: .string("close"))
        f.assign(.none, layerID: "none", shortcut: "q")
        #expect(f.action(layerID: "none", shortcut: "q") == KeyAction.none)
    }

    @Test func theCommandListsRowsAndTheRowATextBelongsTo() {
        let rows = CommandCatalog.rows(key: "3")
        #expect(rows.count == CommandCatalog.entries.count + 1)
        #expect(rows[0] == CommandCatalog.Row(id: "workspace N", title: "workspace", command: "workspace 3", number: "3"))
        #expect(rows.last == CommandCatalog.Row(id: "custom", title: "Custom command…", command: nil, number: ""))
        #expect(CommandCatalog.rowID(for: "workspace 3", in: rows) == "workspace N")
        #expect(CommandCatalog.rowID(for: " focus left ", in: rows) == "focus left")
        #expect(CommandCatalog.rowID(for: "workspace 4", in: rows) == "custom")
        #expect(CommandCatalog.rowID(for: "", in: rows) == "custom")
        #expect(CommandCatalog.rows(key: "h")[1].command == "move-node-to-workspace 1")
    }
}
