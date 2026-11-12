import Foundation

/// What a drag and drop of files decides before the runner is asked (spec
/// §8): whether a drop copies or moves, and which operation it is. The
/// operation is then issued like any command's; nothing here touches a file.
public enum Drop {
    public enum Verb: Equatable, Sendable {
        case copy, move
    }

    /// Whether a drop copies or moves: Finder's rules. Within the app it
    /// moves on the same volume and copies across volumes; ⌥ forces a copy,
    /// ⌘ a move. From another app it is a copy unless ⌘ is held.
    ///
    /// A volume is given by whatever identifies it (the system's volume
    /// identifier); one that can't be told (nil) is the same as no other,
    /// so the drop copies, which loses nothing. Of items from several
    /// volumes only the first one's volume is asked about, as Finder does:
    /// the whole drop is then one copy or one move, and a move of the items
    /// from another volume is the runner's copy-then-remove.
    ///
    /// `allowsCopy` and `allowsMove` are what the drag's source lets the
    /// destination do. A move it doesn't allow becomes a copy; a copy it
    /// doesn't allow is refused (nil) and never becomes a move.
    public static func verb<Volume: Equatable>(
        firstItemVolume: Volume?, targetVolume: Volume?, modifiers: Set<Modifier>, fromThisApp: Bool,
        allowsCopy: Bool, allowsMove: Bool
    ) -> Verb? {
        let wanted: Verb
        if modifiers.contains(.option) {
            // With ⌘ too Finder makes an alias; none is offered here, and
            // of the two a copy is the one that loses nothing.
            wanted = .copy
        } else if modifiers.contains(.command) {
            wanted = .move
        } else if fromThisApp, let from = firstItemVolume, let to = targetVolume, from == to {
            wanted = .move
        } else {
            wanted = .copy
        }
        switch wanted {
        case .move where allowsMove: return .move
        case .move, .copy: return allowsCopy ? .copy : nil
        }
    }

    /// What dropping `items` on `folder` is: one copy or one move of the
    /// items that are not in that folder already, in the order given.
    /// Nothing (no operation) when all of them are there: a drop never
    /// duplicates. An item given twice goes once.
    ///
    /// A folder dropped on itself or into itself is not sorted out here:
    /// the operation is made, and the runner's `validate` refuses it with
    /// its sentence.
    public static func operations(for items: [URL], into folder: URL, verb: Verb) -> [Operation] {
        let here = folder.standardizedFileURL.path
        var seen: Set<String> = []
        let going = items.filter { item in
            let standard = item.standardizedFileURL
            return standard.deletingLastPathComponent().path != here && seen.insert(standard.path).inserted
        }
        guard !going.isEmpty else { return [] }
        switch verb {
        case .copy: return [.copy(items: going, to: folder)]
        case .move: return [.move(items: going, to: folder)]
        }
    }

    /// Whether a row of this kind is a place to drop on: what opens as a
    /// folder in a tab. On any other row a drop is for the pane's folder.
    public static func takesDrop(_ kind: Entry.Kind) -> Bool {
        switch kind {
        case .folder, .volume, .symlink(toFolder: true): true
        case .file, .package, .alias, .symlink(toFolder: false): false
        }
    }
}
