import Foundation
import GroveExplorerCore
import Testing

@Suite struct DropTests {
    private let downloads = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
    private let documents = URL(fileURLWithPath: "/Users/me/Documents", isDirectory: true)

    private func file(_ name: String, in folder: URL) -> URL { folder.appendingPathComponent(name) }

    private func verb(
        item: Int? = 1, target: Int? = 1, _ modifiers: Set<Modifier> = [], fromThisApp: Bool = true,
        allowsCopy: Bool = true, allowsMove: Bool = true
    ) -> Drop.Verb? {
        Drop.verb(
            firstItemVolume: item, targetVolume: target, modifiers: modifiers, fromThisApp: fromThisApp,
            allowsCopy: allowsCopy, allowsMove: allowsMove)
    }

    // MARK: Copy or move

    @Test func onTheSameVolumeADropMoves() {
        #expect(verb(item: 1, target: 1) == .move)
    }

    @Test func acrossVolumesADropCopies() {
        #expect(verb(item: 1, target: 2) == .copy)
    }

    @Test func aVolumeThatCantBeToldCopies() {
        // Nothing is lost by a copy: two unknowns are not "the same volume".
        #expect(verb(item: nil, target: 1) == .copy)
        #expect(verb(item: 1, target: nil) == .copy)
        #expect(verb(item: nil, target: nil) == .copy)
    }

    @Test func optionCopiesOnTheSameVolume() {
        #expect(verb(item: 1, target: 1, [.option]) == .copy)
    }

    @Test func commandMovesAcrossVolumes() {
        #expect(verb(item: 1, target: 2, [.command]) == .move)
    }

    @Test func optionWinsOverCommand() {
        // Finder makes an alias of ⌥⌘; no link is offered here, and of the
        // two a copy is the one that loses nothing.
        #expect(verb(item: 1, target: 1, [.option, .command]) == .copy)
    }

    @Test func shiftAndControlChangeNothing() {
        #expect(verb(item: 1, target: 1, [.shift, .control]) == .move)
        #expect(verb(item: 1, target: 2, [.shift, .control]) == .copy)
    }

    @Test func aDropFromAnotherAppCopiesEvenOnTheSameVolume() {
        #expect(verb(item: 1, target: 1, fromThisApp: false) == .copy)
    }

    @Test func aDropFromAnotherAppMovesOnlyWithCommandAndWhenItsSourceAllows() {
        #expect(verb(item: 1, target: 1, [.command], fromThisApp: false) == .move)
        #expect(verb(item: 1, target: 1, [.command], fromThisApp: false, allowsMove: false) == .copy)
    }

    @Test func aMoveTheSourceDoesNotAllowIsACopy() {
        #expect(verb(item: 1, target: 1, allowsMove: false) == .copy)
    }

    @Test func aCopyTheSourceDoesNotAllowIsRefusedAndNeverTurnedIntoAMove() {
        #expect(verb(item: 1, target: 2, allowsCopy: false) == nil)
        #expect(verb(item: 1, target: 1, [.option], allowsCopy: false) == nil)
        #expect(verb(item: 1, target: 1, allowsCopy: false, allowsMove: false) == nil)
        // A move it does allow is still a move.
        #expect(verb(item: 1, target: 1, allowsCopy: false) == .move)
    }

    // MARK: What a drop becomes

    @Test func aDropIsOneCopyOrOneMoveOfTheItemsInTheirOrder() {
        let items = [file("b.md", in: downloads), file("a.md", in: downloads)]
        #expect(Drop.operations(for: items, into: documents, verb: .copy) == [.copy(items: items, to: documents)])
        #expect(Drop.operations(for: items, into: documents, verb: .move) == [.move(items: items, to: documents)])
    }

    @Test func droppingItemsOnTheFolderTheyAreInDoesNothing() {
        let items = [file("a.md", in: downloads), file("b.md", in: downloads)]
        #expect(Drop.operations(for: items, into: downloads, verb: .move).isEmpty)
        // No duplicate on a drop, with ⌥ either.
        #expect(Drop.operations(for: items, into: downloads, verb: .copy).isEmpty)
        // The folder under another spelling of its path is the same folder.
        let spelled = URL(fileURLWithPath: "/Users/me/Documents/../Downloads/", isDirectory: true)
        #expect(Drop.operations(for: items, into: spelled, verb: .move).isEmpty)
    }

    @Test func onlyTheItemsFromElsewhereGo() {
        let here = file("a.md", in: documents), there = file("b.md", in: downloads)
        #expect(Drop.operations(for: [here, there], into: documents, verb: .move) == [.move(items: [there], to: documents)])
    }

    @Test func noItemsIsNothing() {
        #expect(Drop.operations(for: [], into: documents, verb: .copy).isEmpty)
    }

    @Test func anItemNamedTwiceGoesOnce() {
        let item = file("a.md", in: downloads)
        let again = URL(fileURLWithPath: "/Users/me/Downloads/./a.md")
        #expect(Drop.operations(for: [item, again], into: documents, verb: .copy) == [.copy(items: [item], to: documents)])
    }

    @Test func aFolderDroppedOnItselfOrIntoItselfIsLeftForTheRunnerToRefuse() {
        // `OperationRunner.validate` refuses these with its sentence; the
        // drop does not swallow them silently.
        let folder = downloads.appendingPathComponent("fonts", isDirectory: true)
        #expect(Drop.operations(for: [folder], into: folder, verb: .move) == [.move(items: [folder], to: folder)])
        let inside = folder.appendingPathComponent("old", isDirectory: true)
        #expect(Drop.operations(for: [folder], into: inside, verb: .copy) == [.copy(items: [folder], to: inside)])
    }

    // MARK: Which rows take a drop

    @Test func foldersDisksAndLinksToFoldersTakeADrop() {
        #expect(Drop.takesDrop(.folder))
        #expect(Drop.takesDrop(.volume))
        #expect(Drop.takesDrop(.symlink(toFolder: true)))
    }

    @Test func filesPackagesAliasesAndOtherLinksDoNot() {
        #expect(!Drop.takesDrop(.file))
        #expect(!Drop.takesDrop(.package))
        #expect(!Drop.takesDrop(.alias))
        #expect(!Drop.takesDrop(.symlink(toFolder: false)))
    }
}
