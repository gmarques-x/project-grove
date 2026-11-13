import Foundation
import GroveExplorerCore
import Testing

/// Whether a disk is in use by the window's own file commands: what
/// ejecting it is refused for.
@Suite struct VolumeUseTests {
    private let backup = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// No disk is asked: every path is told by its spelling alone.
    private let none: VolumeUse.DeviceLookup = { _ in nil }

    /// A made-up disk layout: the device of each path that exists, links
    /// followed, as `stat` would say it.
    private func devices(_ known: [String: dev_t]) -> VolumeUse.DeviceLookup { { known[$0] } }

    /// Home on device 1, Backup on 5, and `~/on-backup`, a link to a
    /// folder on Backup.
    private var layout: VolumeUse.DeviceLookup {
        devices([
            "/": 1, "/Users": 1, "/Users/me": 1, "/Users/me/Documents": 1, "/Users/me/a.txt": 1,
            "/Volumes": 1, "/Volumes/Backup": 5, "/Volumes/Backup/photos": 5, "/Volumes/Backup/b.txt": 5,
            "/Users/me/on-backup": 5,
            // On Backup, a link that leads home, and another disk attached inside it.
            "/Volumes/Backup/to-home": 1, "/Volumes/Backup/inner": 9,
        ])
    }

    // MARK: A path on a volume, as the disks say it

    @Test func aPlaceIsOnTheVolumeItsDeviceIs() {
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos"), volume: backup, device: layout))
        #expect(!VolumeUse.isOn(url("/Users/me/Documents"), volume: backup, device: layout))
        #expect(VolumeUse.isOn(backup, volume: backup, device: layout))
    }

    /// What the path's spelling can't tell: a folder that is a link to the disk.
    @Test func aPlaceReachedThroughALinkIsOnTheVolumeTheLinkLeadsTo() {
        #expect(VolumeUse.isOn(url("/Users/me/on-backup"), volume: backup, device: layout))
        #expect(!VolumeUse.isOn(url("/Users/me/on-backup"), volume: backup, device: none))
        let copy = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Users/me/on-backup"))
        #expect(VolumeUse.touches(copy, volume: backup, device: layout))
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(copy)], device: layout)
                == "Backup is in use by a copy: wait for it or cancel it")
    }

    /// A place that is not there yet (where a copy goes) is on the disk
    /// of the nearest folder above it that is.
    @Test func aPlaceNotThereYetIsWhereItsNearestFolderIs() {
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos/2026/new.png"), volume: backup, device: layout))
        #expect(VolumeUse.isOn(url("/Users/me/on-backup/new/deeper"), volume: backup, device: layout))
        #expect(!VolumeUse.isOn(url("/Users/me/Documents/new/deeper"), volume: backup, device: layout))
    }

    @Test func anotherDiskAttachedUnderTheVolumeIsNotTheVolume() {
        #expect(!VolumeUse.isOn(url("/Volumes/Backup/inner/file"), volume: backup, device: layout))
    }

    /// An item is where it lies, whatever it leads to: a link on the
    /// disk is copied or trashed as a link, from that disk.
    @Test func anItemThatIsALinkElsewhereStillLiesOnItsVolume() {
        let link = url("/Volumes/Backup/to-home")
        #expect(VolumeUse.touches(.trash(items: [link]), volume: backup, device: layout))
        #expect(VolumeUse.touches(.duplicate(items: [link]), volume: backup, device: layout))
        #expect(VolumeUse.touches(.rename(item: link, to: "x"), volume: backup, device: layout))
        #expect(VolumeUse.touches(.copy(items: [link], to: url("/Users/me/Documents")), volume: backup, device: layout))
        // And a link at home that leads to the disk is still a thing at home…
        let home = url("/Users/me/on-backup")
        // …but it is refused all the same: what it leads to is on the disk.
        #expect(VolumeUse.touches(.trash(items: [home]), volume: backup, device: layout))
    }

    /// The disk can't be asked (it stopped answering, or is gone): the
    /// path's spelling decides, as before.
    @Test func whenTheVolumeCannotBeAskedThePathDecides() {
        let noRoot = devices(["/": 1, "/Users/me": 1])
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos/a.png"), volume: backup, device: noRoot))
        #expect(!VolumeUse.isOn(url("/Volumes/Backup 2/a.png"), volume: backup, device: noRoot))
        #expect(!VolumeUse.isOn(url("/Users/me/a.txt"), volume: backup, device: noRoot))
    }

    @Test func aCommandOntoAnEjectingDiskThroughALinkIsRefused() {
        let ejecting = [VolumeUse.Ejecting(name: "Backup", root: backup)]
        let copy = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Users/me/on-backup"))
        #expect(
            VolumeUse.commandRefusal(for: .operation(copy), ejecting: ejecting, device: layout)
                == "Backup is being ejected: wait for it, then try again")
    }

    // MARK: A path on a volume

    @Test func aPathIsOnAVolumeAtOrUnderItsRoot() {
        #expect(VolumeUse.isOn(url("/Volumes/Backup"), volume: backup, device: none))
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos/a.png"), volume: backup, device: none))
        #expect(!VolumeUse.isOn(url("/Users/me/Backup"), volume: backup, device: none))
        #expect(!VolumeUse.isOn(url("/Volumes"), volume: backup, device: none))
    }

    /// "Backup 2" is another disk, not something on "Backup".
    @Test func aNameThatOnlyStartsTheSameIsAnotherVolume() {
        #expect(!VolumeUse.isOn(url("/Volumes/Backup 2/a.png"), volume: backup, device: none))
        #expect(!VolumeUse.isOn(url("/Volumes/Backup2"), volume: backup, device: none))
        #expect(!VolumeUse.isOn(url("/Volumes/Back"), volume: backup, device: none))
    }

    @Test func pathsAreComparedStandardized() {
        #expect(VolumeUse.isOn(url("/Volumes/Backup/photos/../docs/a.txt"), volume: backup, device: none))
        #expect(!VolumeUse.isOn(url("/Volumes/Backup/../Other/a.txt"), volume: backup, device: none))
        #expect(VolumeUse.isOn(url("/Volumes/Backup/a"), volume: URL(fileURLWithPath: "/Volumes/Backup/", isDirectory: true), device: none))
    }

    // MARK: An operation

    @Test func aCopyOrAMoveTouchesTheVolumeOfItsItemsAndOfItsTarget() {
        let from = Operation.copy(items: [url("/Users/me/a.txt"), url("/Volumes/Backup/b.txt")], to: url("/Users/me/Documents"))
        let to = Operation.move(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup/in"))
        let neither = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup 2/in"))
        #expect(VolumeUse.touches(from, volume: backup, device: none))
        #expect(VolumeUse.touches(to, volume: backup, device: none))
        #expect(!VolumeUse.touches(neither, volume: backup, device: none))
    }

    @Test func theOtherOperationsTouchTheVolumeTheirItemsAreOn() {
        #expect(VolumeUse.touches(.duplicate(items: [url("/Volumes/Backup/a")]), volume: backup, device: none))
        #expect(VolumeUse.touches(.rename(item: url("/Volumes/Backup/a"), to: "b"), volume: backup, device: none))
        #expect(VolumeUse.touches(.newFolder(in: url("/Volumes/Backup"), name: "new"), volume: backup, device: none))
        #expect(VolumeUse.touches(.trash(items: [url("/Volumes/Backup/a")]), volume: backup, device: none))
        #expect(!VolumeUse.touches(.duplicate(items: [url("/Users/me/a")]), volume: backup, device: none))
        #expect(!VolumeUse.touches(.rename(item: url("/Users/me/a"), to: "Backup"), volume: backup, device: none))
        #expect(!VolumeUse.touches(.newFolder(in: url("/Users/me"), name: "Backup"), volume: backup, device: none))
        #expect(!VolumeUse.touches(.trash(items: []), volume: backup, device: none))
    }

    // MARK: Ejecting

    @Test func ejectingIsRefusedWhileACommandInHandOrWaitingUsesTheVolume() {
        let home = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Users/me/Documents"))
        let onIt = Operation.move(items: [url("/Volumes/Backup/b.txt")], to: url("/Users/me"))
        #expect(VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [], device: none) == nil)
        #expect(VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(home)], device: none) == nil)
        // The first command that uses it is named, waiting or in hand.
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(home), .operation(onIt)], device: none)
                == "Backup is in use by a move: wait for it or cancel it")
        #expect(
            VolumeUse.ejectRefusal(
                of: "Backup", at: backup, commands: [.operation(.copy(items: [url("/Users/me/a")], to: backup))],
                device: none)
                == "Backup is in use by a copy: wait for it or cancel it")
    }

    /// What an undo or a redo will touch is known only to the undo stack:
    /// while one is in hand or waiting no disk is ejected.
    @Test func anUndoOrARedoRefusesEveryVolume() {
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.undo], device: none)
                == "Backup can't be ejected during an undo: wait for it")
        #expect(
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.redo], device: none)
                == "Backup can't be ejected during a redo: wait for it")
    }

    // MARK: A command while a disk is being ejected

    /// The other way round: the eject is already on its way, and a command
    /// onto that disk would be the one holding it, or fail item by item.
    @Test func aCommandOntoADiskBeingEjectedIsRefused() {
        let ejecting = [VolumeUse.Ejecting(name: "Backup", root: backup)]
        let onto = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup/in"))
        let from = Operation.trash(items: [url("/Volumes/Backup/a.txt")])
        let elsewhere = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup 2"))
        #expect(
            VolumeUse.commandRefusal(for: .operation(onto), ejecting: ejecting, device: none)
                == "Backup is being ejected: wait for it, then try again")
        #expect(
            VolumeUse.commandRefusal(for: .operation(from), ejecting: ejecting, device: none)
                == "Backup is being ejected: wait for it, then try again")
        #expect(VolumeUse.commandRefusal(for: .operation(elsewhere), ejecting: ejecting, device: none) == nil)
    }

    @Test func noCommandIsRefusedWhileNothingIsBeingEjected() {
        let onto = Operation.copy(items: [url("/Users/me/a.txt")], to: url("/Volumes/Backup/in"))
        #expect(VolumeUse.commandRefusal(for: .operation(onto), ejecting: [], device: none) == nil)
        #expect(VolumeUse.commandRefusal(for: .undo, ejecting: [], device: none) == nil)
        #expect(VolumeUse.commandRefusal(for: .redo, ejecting: [], device: none) == nil)
    }

    /// What an undo or a redo will touch is the undo stack's to know: none
    /// begins while any disk is being ejected.
    @Test func anUndoOrARedoWaitsForAnyEject() {
        let ejecting = [VolumeUse.Ejecting(name: "Backup", root: backup)]
        #expect(
            VolumeUse.commandRefusal(for: .undo, ejecting: ejecting, device: none)
                == "Backup is being ejected: undo when that is done")
        #expect(
            VolumeUse.commandRefusal(for: .redo, ejecting: ejecting, device: none)
                == "Backup is being ejected: redo when that is done")
    }

    @Test func theDiskTheCommandTouchesIsTheOneNamed() {
        let ejecting = [
            VolumeUse.Ejecting(name: "Photos", root: url("/Volumes/Photos")), VolumeUse.Ejecting(name: "Backup", root: backup),
        ]
        let onto = Operation.move(items: [url("/Volumes/Backup/a.txt")], to: url("/Users/me"))
        #expect(
            VolumeUse.commandRefusal(for: .operation(onto), ejecting: ejecting, device: none)
                == "Backup is being ejected: wait for it, then try again")
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
            VolumeUse.ejectRefusal(of: "Backup", at: backup, commands: [.operation(operation)], device: none)
                == "Backup is in use by \(words): wait for it or cancel it")
    }
}
