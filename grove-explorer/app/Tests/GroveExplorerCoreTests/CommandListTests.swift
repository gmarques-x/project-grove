import Foundation
@testable import GroveExplorerCore
import Testing

/// The one table of the app's commands (spec §7).
@Suite struct CommandListTests {
    private func command(_ id: String) -> CommandInfo? {
        CommandList.all.first { $0.id == id }
    }

    @Test func everyCommandHasItsOwnID() {
        let ids = CommandList.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func noKeyIsGivenToTwoCommands() {
        var seen: [String: String] = [:]
        for command in CommandList.all {
            guard let key = command.key else { continue }
            let stroke = key + "+" + command.modifiers.map(\.rawValue).sorted().joined(separator: "+")
            #expect(seen[stroke] == nil, "\(command.id) and \(seen[stroke] ?? "") share \(stroke)")
            seen[stroke] = command.id
        }
    }

    @Test func everyCommandSitsInOneOfTheFourMenusAndHasATitle() {
        for command in CommandList.all {
            #expect(CommandList.menus.contains(command.menu), "\(command.id) is in \(command.menu)")
            #expect(!command.title.isEmpty)
        }
        #expect(CommandList.menus == ["File", "Edit", "View", "Go"])
        // A menu's commands stand together in the table, the menus in their order.
        var order: [String] = []
        for command in CommandList.all where order.last != command.menu { order.append(command.menu) }
        #expect(order == CommandList.menus)
    }

    /// Spec §7, "Finder's, unchanged": each row that is a command, with its key.
    @Test(arguments: [
        ("open", "O", [Modifier.command], "File"),
        ("openWithArrow", "↓", [.command], "File"),
        ("enclosingFolder", "↑", [.command], "Go"),
        ("back", "[", [.command], "Go"),
        ("forward", "]", [.command], "Go"),
        ("rename", "Return", [], "File"),
        ("quickLook", "Space", [], "File"),
        ("copy", "C", [.command], "Edit"),
        ("paste", "V", [.command], "Edit"),
        ("pasteMove", "V", [.option, .command], "Edit"),
        ("duplicate", "D", [.command], "File"),
        ("moveToTrash", "⌫", [.command], "File"),
        ("newFolder", "N", [.command, .shift], "File"),
        ("toggleHidden", ".", [.command, .shift], "View"),
        ("undo", "Z", [.command], "Edit"),
        ("redo", "Z", [.command, .shift], "Edit"),
        ("selectAll", "A", [.command], "Edit"),
        ("goToFolder", "G", [.command, .shift], "Go"),
        ("goToPath", "L", [.command], "Go"),
        ("goHome", "H", [.command, .shift], "Go"),
        ("goDesktop", "D", [.command, .shift], "Go"),
        ("goDocuments", "O", [.command, .shift], "Go"),
        ("goDownloads", "L", [.command, .option], "Go"),
        ("goApplications", "A", [.command, .shift], "Go"),
        ("getInfo", "I", [.command], "File"),
        // Finder's View › Sort By: the column headers, by key.
        ("sortByName", "1", [.control, .option, .command], "View"),
        ("sortByKind", "2", [.control, .option, .command], "View"),
        ("sortByDate", "5", [.control, .option, .command], "View"),
        ("sortBySize", "6", [.control, .option, .command], "View"),
    ] as [(String, String, [Modifier], String)])
    func findersKeys(id: String, key: String, modifiers: [Modifier], menu: String) {
        let found = command(id)
        #expect(found?.key == key)
        #expect(found?.modifiers == Set(modifiers))
        #expect(found?.menu == menu)
    }

    /// Spec §7, "Grove's".
    @Test(arguments: [
        ("switchPane", "Tab", [], "View"),
        ("togglePanes", "\\", [Modifier.command], "View"),
        ("newTab", "T", [.command], "File"),
        ("closeTab", "W", [.command], "File"),
        ("nextTab", "Tab", [.control], "View"),
        ("previousTab", "Tab", [.control, .shift], "View"),
        ("tab1", "1", [.command], "View"),
        ("tab9", "9", [.command], "View"),
        ("copyToOtherPane", "F5", [], "File"),
        ("moveToOtherPane", "F6", [], "File"),
        ("filter", "F", [.command], "View"),
        ("toggleSidebar", "S", [.command, .option], "View"),
        ("focusSidebar", "←", [.option, .command], "View"),
        ("openInGhostty", "T", [.command, .option], "File"),
        ("copyPaths", "C", [.command, .option], "Edit"),
        // The whole window by keyboard (Task 15).
        ("contextMenu", "Return", [.control], "File"),
        ("contextMenuF10", "F10", [.shift], "File"),
        ("eject", "E", [.command], "File"),
        ("cancelOperation", ".", [.command], "File"),
        ("showFailures", "F", [.command, .shift], "View"),
    ] as [(String, String, [Modifier], String)])
    func grovesKeys(id: String, key: String, modifiers: [Modifier], menu: String) {
        let found = command(id)
        #expect(found?.key == key)
        #expect(found?.modifiers == Set(modifiers))
        #expect(found?.menu == menu)
    }

    @Test func thereIsATabCommandForEachOfTheFirstNine() {
        #expect((1...9).allSatisfy { command("tab\($0)")?.key == String($0) })
        #expect(CommandList.tabIndex(of: "tab3") == 2)
        #expect(CommandList.tabIndex(of: "newTab") == nil)
    }

    @Test func aKeyStrokeFindsItsCommand() {
        #expect(CommandList.command(key: "T", modifiers: [.command])?.id == "newTab")
        #expect(CommandList.command(key: "t", modifiers: [.command])?.id == "newTab")
        #expect(CommandList.command(key: "T", modifiers: [.command, .option])?.id == "openInGhostty")
        #expect(CommandList.command(key: "Tab", modifiers: [])?.id == "switchPane")
        #expect(CommandList.command(key: "Tab", modifiers: [.control, .shift])?.id == "previousTab")
        #expect(CommandList.command(key: "↓", modifiers: [.command])?.id == "openWithArrow")
        // A letter alone is typed into the list, and a stroke nothing has is nobody's.
        #expect(CommandList.command(key: "T", modifiers: []) == nil)
        #expect(CommandList.command(key: "T", modifiers: [.command, .control]) == nil)
    }

    /// A command reached by a second key (⌘↓ beside ⌘O, ⌘L beside ⌘⇧G) and
    /// the nine tab keys are keys only: a menu lists a command once.
    @Test func aSecondKeyForACommandIsNotAMenuRow() {
        #expect(CommandList.keysOnly.contains("openWithArrow"))
        #expect(CommandList.keysOnly.contains("goToPath"))
        #expect(CommandList.keysOnly.contains("tab5"))
        #expect(CommandList.keysOnly.contains("contextMenuF10"))
        #expect(!CommandList.keysOnly.contains("contextMenu"))
        #expect(!CommandList.keysOnly.contains("open"))
        #expect(CommandList.keysOnly.allSatisfy { command($0) != nil })
    }

    /// Return is Rename's. Where the folder can't be read there is nothing
    /// to rename and the list takes it for Open Privacy Settings, which is
    /// a command with a menu row and no key of its own.
    @Test func openPrivacySettingsHasNoKeyOfItsOwn() {
        let found = command("openPrivacySettings")
        #expect(found?.title == "Open Privacy Settings…")
        #expect(found?.key == nil)
        #expect(found?.menu == "Go")
        #expect(CommandList.command(key: "Return", modifiers: [])?.id == "rename")
    }

    /// The keys that reach what only the pointer reached, each its own.
    @Test func theKeysOfTheWholeKeyboardPass() {
        #expect(CommandList.command(key: "Return", modifiers: [.control])?.id == "contextMenu")
        #expect(CommandList.command(key: "F10", modifiers: [.shift])?.id == "contextMenuF10")
        #expect(CommandList.command(key: "e", modifiers: [.command])?.id == "eject")
        #expect(CommandList.command(key: ".", modifiers: [.command])?.id == "cancelOperation")
        #expect(CommandList.command(key: ".", modifiers: [.command, .shift])?.id == "toggleHidden")
        #expect(CommandList.command(key: "F", modifiers: [.command, .shift])?.id == "showFailures")
        #expect(CommandList.command(key: "F", modifiers: [.command])?.id == "filter")
        // ⌘1 is a tab's; with ⌃ and ⌥ too it is a column's.
        #expect(CommandList.command(key: "1", modifiers: [.command])?.id == "tab1")
        #expect(CommandList.command(key: "1", modifiers: [.control, .option, .command])?.id == "sortByName")
        // F10 alone is the system's (the menu bar), and is nobody's here.
        #expect(CommandList.command(key: "F10", modifiers: []) == nil)
        #expect(command("contextMenu")?.title == command("contextMenuF10")?.title)
    }

    // MARK: The list's own keys, and the whole of spec §7

    @Test func theListsOwnKeysAreTheRowsThatAreNotCommands() {
        #expect(CommandList.listKeys.map(\.key) == ["↑", "↓", "↑", "↓", "Home", "End", "Page Up", "Page Down", "Letters"])
        #expect(CommandList.listKeys[2].modifiers == [.shift])
        #expect(CommandList.listKeys.allSatisfy { !$0.does.isEmpty })
        // None of them is also a command's key.
        for key in CommandList.listKeys {
            #expect(CommandList.command(key: key.key, modifiers: key.modifiers) == nil)
        }
    }

    /// Every key in the two tables of the spec's §7 is a command's
    /// (`CommandList.all`) or the list's own (`CommandList.listKeys`).
    @Test func everyKeyOfTheSpecsTablesIsACommandsOrTheLists() throws {
        // …/grove-explorer/app/Tests/GroveExplorerCoreTests/<this file>
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let spec = try String(
            contentsOf: repo.appendingPathComponent("grove-dotfiles/docs/specs/2026-11-12-grove-explorer-design.md"),
            encoding: .utf8)
        let section = try #require(spec.components(separatedBy: "\n## 7. Keys\n").last?.components(separatedBy: "\n## 8.").first)
        let cells = section.split(separator: "\n").filter { $0.hasPrefix("| ") }
            .compactMap { $0.split(separator: "|").first.map { $0.trimmingCharacters(in: .whitespaces) } }
            .filter { $0 != "Key" && !$0.hasPrefix("---") }
        // 19 rows of Finder's keys and 16 of Grove's. (The fix round after
        // Task 15's review reworded two of Grove's rows, ⌘E and ⌘., and
        // added or took away none: the counts stand.)
        #expect(cells.count == 35)

        var strokes: [String] = []
        for cell in cells {
            for part in cell.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if part == "Page Up/Down" {
                    strokes += ["Page Up", "Page Down"]
                } else if part == "⌘1…⌘9" {
                    strokes += (1...9).map { "⌘\($0)" }
                } else if part.contains(" "), part.split(separator: " ").allSatisfy({ $0.count <= 2 }) {
                    // "↑ ↓", "⇧↑ ⇧↓": two keys in one breath.
                    strokes += part.split(separator: " ").map(String.init)
                } else {
                    strokes.append(part)
                }
            }
        }
        // 38 keys in Finder's rows and 28 in Grove's.
        #expect(strokes.count == 66)
        let marks: [Character: GroveExplorerCore.Modifier] = ["⌘": .command, "⌥": .option, "⇧": .shift, "⌃": .control]
        for stroke in strokes {
            var modifiers: Set<GroveExplorerCore.Modifier> = []
            var key = Substring(stroke)
            while let first = key.first, let modifier = marks[first], key.count > 1 {
                modifiers.insert(modifier)
                key = key.dropFirst()
            }
            let isCommand = CommandList.command(key: String(key), modifiers: modifiers) != nil
            let isTheLists = CommandList.listKeys.contains { $0.key == String(key) && $0.modifiers == modifiers }
            #expect(isCommand || isTheLists, "\(stroke) of spec §7 is in neither table")
        }
    }
}
