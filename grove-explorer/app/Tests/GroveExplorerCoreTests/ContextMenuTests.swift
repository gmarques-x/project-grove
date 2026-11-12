import Foundation
import GroveExplorerCore
import Testing

@Suite struct ContextMenuTests {
    private func titles(_ items: [ContextMenu.Item]) -> [String] {
        items.map { item in
            switch item {
            case .separator: "-"
            case let .row(row): row.title
            }
        }
    }

    private func row(_ title: String, in items: [ContextMenu.Item]) -> ContextMenu.Row? {
        for case let .row(row) in items where row.title == title { return row }
        return nil
    }

    @Test func aSelectionsRowsAreTheSpecsInItsOrder() {
        #expect(titles(ContextMenu.items(selected: 1, showsHidden: false)) == [
            "Open", "Open With", "-", "Quick Look", "-", "Rename", "Duplicate", "Copy Path", "-", "Move to Trash", "-",
            "Show in Finder", "Open in Ghostty",
        ])
    }

    @Test func theRowsAreTheMenuBarsCommands() {
        let actions = ContextMenu.items(selected: 1, showsHidden: false).compactMap { item -> ContextMenu.Action? in
            if case let .row(row) = item { return row.action }
            return nil
        }
        #expect(actions == [
            .command("open"), .openWith, .command("quickLook"), .command("rename"), .command("duplicate"),
            .command("copyPaths"), .command("moveToTrash"), .showInFinder, .command("openInGhostty"),
        ])
        // Each command's title is the one `CommandList` gives its menu-bar row.
        for item in ContextMenu.items(selected: 1, showsHidden: false) + ContextMenu.items(selected: 0, showsHidden: false) {
            guard case let .row(row) = item, case let .command(id) = row.action, id != "toggleHidden" else { continue }
            #expect(CommandList.all.first { $0.id == id }?.title == row.title)
        }
    }

    @Test func renameIsForOneItemOnly() {
        #expect(row("Rename", in: ContextMenu.items(selected: 1, showsHidden: false))?.enabled == true)
        let several = ContextMenu.items(selected: 3, showsHidden: false)
        #expect(row("Rename", in: several)?.enabled == false)
        // Everything else works on several.
        for case let .row(row) in several where row.title != "Rename" { #expect(row.enabled) }
    }

    @Test func emptySpaceHasNewFolderPasteAndTheHiddenItems() {
        let items = ContextMenu.items(selected: 0, showsHidden: false)
        #expect(titles(items) == ["New Folder", "Paste", "-", "Show Hidden Items"])
        #expect(row("New Folder", in: items)?.action == .command("newFolder"))
        #expect(row("Paste", in: items)?.action == .command("paste"))
        #expect(row("Show Hidden Items", in: items)?.action == .command("toggleHidden"))
    }

    @Test func showHiddenItemsIsTickedWhileTheyShow() {
        #expect(row("Show Hidden Items", in: ContextMenu.items(selected: 0, showsHidden: false))?.checked == false)
        #expect(row("Show Hidden Items", in: ContextMenu.items(selected: 0, showsHidden: true))?.checked == true)
        for case let .row(row) in ContextMenu.items(selected: 2, showsHidden: true) { #expect(!row.checked) }
    }

    @Test func aMenuNeitherStartsNorEndsWithALineNorHasTwoTogether() {
        for selected in 0...2 {
            let items = ContextMenu.items(selected: selected, showsHidden: false)
            #expect(items.first != .separator && items.last != .separator)
            for (item, next) in zip(items, items.dropFirst()) { #expect(!(item == .separator && next == .separator)) }
        }
    }
}
