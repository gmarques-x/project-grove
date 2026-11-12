import Foundation
import GroveExplorerCore
import Testing

/// Whether a disk is in use by the window's own file commands: what
/// ejecting it is refused for.
@Suite struct VolumeUseTests {
    private let backup = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    // MARK: A path on a volume

    @Test func aPathIsOnAVolumeAtOrUnderItsRoot() {
        #expect(VolumeUse.isOn(url("/Volumes/Backup"), volume: backup))
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos/a.png"), volume: backup))
        #expect(!VolumeUse.isOn(url("/Users/me/Backup"), volume: backup))
        #expect(!VolumeUse.isOn(url("/Volumes"), volume: backup))
    }

    /// "Backup 2" is another disk, not something on "Backup".
    @Test func aNameThatOnlyStartsTheSameIsAnotherVolume() {
        #expect(!VolumeUse.isOn(url("/Volumes/Backup 2/a.png"), volume: backup))
        #expect(!VolumeUse.isOn(url("/Volumes/Backup2"), volume: backup))
        #expect(!VolumeUse.isOn(url("/Volumes/Back"), volume: backup))
    }

    @Test func pathsAreComparedStandardized() {
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos/../docs/a.txt"), volume: backup))
        #expect(!VolumeUse.isOn(url("/Volumes/Backup/../Other/a.txt"), volume: backup))
        #expect(VolumeUse.isOn(url("/Volumes/Backup/a"), volume: URL(fileURLWithPath: "/Volumes/Backup/", isDirectory: true)))
    }

    // MARK: An operation

    @Test func aCopyOrAMoveTouchesTheVolumeOfItsItemsAndOfItsTarget() {
        let from = Operation.copy(items: [url("/Users/me/a.txt"), url("/Volumes/Backup/b.txt")], to: url("/Users/me/Documents"))
        let to = Operation.move(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup/in"))
        let neither = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup 2/in"))
        #expect(VolumeUse.touches(from, volume: backup))
        #expect(VolumeUse.touches(to, volume: backup))
        #expect(!VolumeUse.touches(neither, volume: backup))
    }

    @Test func theOtherOperationsTouchTheVolumeTheirItemsAreOn() {
        #expect(VolumeUse.touches(.duplicate(items: [url("/Volumes/Backup/a")]), volume: backup))
        #expect(VolumeUse.touches(.rename(item: url("/Volumes/Backup/a"), to: "b"), volume: backup))
        #expect(VolumeUse.touches(.newFolder(in: url("/Volumes/Backup"), name: "new"), volume: backup))
        #expect(VolumeUse.touches(.trash(items: [url("/Volumes/Backup/a")]), volume: backup))
        #expect(!VolumeUse.touches(.duplicate(items: [url("/Users/me/a")]), volume: backup))
        #expect(!VolumeUse.touches(.rename(item: url("/Users/me/a"), to: "Backup"), volume: backup))
        #expect(!VolumeUse.touches(.newFolder(in: url("/Users/me"), name: "Backup"), volume: backup))
        #expect(!VolumeUse.touches(.trash(items: []), volume: backup))
    }

    // MARK: Ejecting

    @Test func ejectingIsRefusedWhileACommandInHandOrWaitingUsesTheVolume() {
        let home = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Users/me/Documents"))
        let onIt = Operation.move(items: [url("/Volumes/Backup/b.txt")], to: url("/Users/me"))
        #expect(VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: []) == nil)
        #expect(VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(home)]) == nil)
        // The first command that uses it is named, waiting or in hand.
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(home), .operation(onIt)])
                == "Backup is in use by a move: wait for it or cancel it")
        #expect(
            VolumeUse.ejectRefusal(
                of: "Backup", at: backup, commands: [.operation(.copy(items: [url("/Users/me/a")], to: backup))])
                == "Backup is in use by a copy: wait for it or cancel it")
    }

    /// What an undo or a redo will touch is known only to the undo stack:
    /// while one is in hand or waiting no disk is ejected.
    @Test func anUndoOrARedoRefusesEveryVolume() {
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.undo])
                == "Backup can't be ejected during an undo: wait for it")
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.redo])
                == "Backup can't be ejected during a redo: wait for it")
    }

    @Test(arguments: [
        (Operation.copy(items: [], to: URL(fileURLWithPath: "/Volumes/Backup")), "a copy"),
        (.move(items: [], to: URL(fileURLWithPath: "/Volumes/Backup")), "a move"),
        (.duplicate(items: [URL(fileURLWithPath: "/Volumes/Backup/a")]), "a duplicate"),
        (.rename(item: URL(fileURLWithPath: "/Volumes/Backup/a"), to: "b"), "a rename"),
        (.newFolder(in: URL(fileURLWithPath: "/Volumes/Backup"), name: "n"), "a new folder"),
        (.trash(items: [URL(fileURLWithPath: "/Volumes/Backup/a")]), "a move to the Trash"),
    ] as [(GroveExplorerCore.Operation, String)])
    func theRefusalNamesWhatUsesIt(operation: GroveExplorerCore.Operation, words: String) {
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(operation)])
                == "Backup is in use by \(words): wait for it or cancel it")
    }
}
