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
        #expect(!CommandList.keysOnly.contains("open"))
        #expect(CommandList.keysOnly.allSatisfy { command($0) != nil })
    }
}
