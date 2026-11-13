import Foundation
import GroveExplorerCore
import Testing

@Suite struct TreeLayoutTests {
    // MARK: Where things sit

    /// Level 0: the gutter at the pane's edge (under the header's "Name"),
    /// the icon 16 pt after it.
    @Test func atTheTopLevelTheGutterStartsAtTheEdge() {
        #expect(TreeLayout.gutterStart(depth: 0) == ListColumns.edge)
        #expect(TreeLayout.iconStart(depth: 0) == ListColumns.edge + 16)
    }

    /// Each level is one gutter further in: a child's chevron under its parent's icon.
    @Test func eachLevelIs16FurtherIn() {
        #expect(TreeLayout.gutterStart(depth: 1) == TreeLayout.iconStart(depth: 0))
        #expect(TreeLayout.iconStart(depth: 3) == ListColumns.edge + 3 * 16 + 16)
    }

    /// Never capped: a deep level is as far in as its depth says.
    @Test func theIndentIsNeverCapped() {
        #expect(TreeLayout.gutterStart(depth: 40) == ListColumns.edge + 40 * 16)
    }

    /// The chevron's 12 pt box, at the gutter's start.
    @Test func theChevronBoxIs12AtTheGuttersStart() {
        let box = TreeLayout.chevronBox(depth: 2)
        #expect(box.x == ListColumns.edge + 32)
        #expect(box.width == 12)
    }

    // MARK: Which part of a row a point is in

    @Test func aPointBeforeTheGutterIsBefore() {
        #expect(TreeLayout.part(atX: 0, depth: 0) == .before)
        #expect(TreeLayout.part(atX: ListColumns.edge + 15.9, depth: 1) == .before)
    }

    /// The whole 16 pt cell, the 4 pt after the box included.
    @Test func theGutterIsItsWhole16Points() {
        #expect(TreeLayout.part(atX: ListColumns.edge, depth: 0) == .gutter)
        #expect(TreeLayout.part(atX: ListColumns.edge + 15.9, depth: 0) == .gutter)
        #expect(TreeLayout.part(atX: ListColumns.edge + 16, depth: 1) == .gutter)
        #expect(TreeLayout.part(atX: ListColumns.edge + 16, depth: 0) == .icon)
    }

    @Test func theIconThenTheName() {
        let icon = TreeLayout.iconStart(depth: 2)
        #expect(TreeLayout.part(atX: icon, depth: 2) == .icon)
        #expect(TreeLayout.part(atX: icon + 15.9, depth: 2) == .icon)
        #expect(TreeLayout.part(atX: icon + 16, depth: 2) == .name)
        #expect(TreeLayout.part(atX: 900, depth: 2) == .name)
    }

    // MARK: The chevron

    @Test func theChevronOfEachFold() {
        #expect(TreeLayout.chevron(for: .none) == nil)
        #expect(TreeLayout.chevron(for: .closed) == .closed)
        #expect(TreeLayout.chevron(for: .open) == .open)
        // Opened, still being read: the open chevron, the "···" line beneath.
        #expect(TreeLayout.chevron(for: .loading) == .open)
    }

    /// A click toggles only in the gutter of a row that has a chevron.
    @Test func aClickTogglesOnlyOnAChevronsGutter() {
        let gutter = TreeLayout.gutterStart(depth: 1) + 2
        #expect(TreeLayout.togglesFold(atX: gutter, depth: 1, fold: .closed))
        #expect(TreeLayout.togglesFold(atX: gutter, depth: 1, fold: .loading))
        #expect(!TreeLayout.togglesFold(atX: gutter, depth: 1, fold: .none))
        #expect(!TreeLayout.togglesFold(atX: TreeLayout.iconStart(depth: 1), depth: 1, fold: .open))
        #expect(!TreeLayout.togglesFold(atX: TreeLayout.gutterStart(depth: 0) + 2, depth: 1, fold: .open))
    }

    // MARK: The Size column

    private func folder(_ kind: Entry.Kind = .folder, size: Int64? = nil) -> Entry {
        Entry(url: URL(fileURLWithPath: "/a/b", isDirectory: true), name: "b", kind: kind, size: size,
              modified: nil, isHidden: false, typeDescription: "Folder")
    }

    @Test func aFolderBeingMeasuredSaysDots() {
        #expect(Formatting.sizeColumn(folder(), total: nil, awaitsTotal: true) == "···")
        #expect(Formatting.sizeColumn(folder(.package), total: nil, awaitsTotal: true) == "···")
    }

    /// No total on its way (it can't be read): "--", as for a file without a size.
    @Test func anUnreadableFolderSaysDashes() {
        #expect(Formatting.sizeColumn(folder(), total: nil, awaitsTotal: false) == "--")
    }

    @Test func aKnownSizeIsWritten() {
        #expect(Formatting.sizeColumn(folder(), total: 348_000, awaitsTotal: false) == "348 KB")
        #expect(Formatting.sizeColumn(folder(.file, size: 4_000), total: nil, awaitsTotal: true) == "4 KB")
        #expect(Formatting.sizeColumn(folder(.symlink(toFolder: true)), total: nil, awaitsTotal: true) == "--")
    }
}
