import Foundation
import GroveExplorerCore

/// Looking into folders for their chevrons (spec §16): whether a folder
/// has an item that would show, asked of the folders in view first, a few
/// at a time, off the main thread, for the pane's tab only.
extension AppModel {
    // MARK: Looking into folders for their chevrons

    /// Looks into the closed folders of the rows not yet looked into
    /// (`FolderPeek.wanted`), in row order, those in view first
    /// (`peeksFirst`), a few at a time and off the main thread. Until a
    /// folder's answer is in, it has no chevron.
    func wantPeeks(in side: Side) {
        guard live, trees[side] != nil, let listing = listing(for: side), listing.isRead else { return }
        let peeking = trees[side]?.peeking ?? []
        trees[side]?.peekQueue = FolderPeek.wanted(listing.items, known: listing.peeks)
            .filter { !peeking.contains($0.pathKey) && !isBeingEjected($0) }
        pumpPeeks(in: side)
    }

    /// The rows in view: their folders are looked into before the others.
    func peeksFirst(_ visible: [URL], in side: Side) {
        guard let queue = trees[side]?.peekQueue, !queue.isEmpty else { return }
        let first = Set(visible)
        let front = queue.filter(first.contains)
        guard !front.isEmpty else { return }
        trees[side]?.peekQueue = front + queue.filter { !first.contains($0) }
    }

    private func pumpPeeks(in side: Side) {
        guard let key = trees[side]?.key else { return }
        let showHidden = browser.showHidden
        while let tree = trees[side], tree.peeking.count < PaneTree.peeksAtOnce, let folder = tree.peekQueue.first {
            trees[side]?.peekQueue.removeFirst()
            trees[side]?.peeking.insert(folder.pathKey)
            Task {
                let answer = await Task.detached { FolderPeek.hasContents(folder, showHidden: showHidden) }.value
                // The tab left, or hidden items were switched: not this answer.
                guard trees[side]?.key == key else { return }
                trees[side]?.peeking.remove(folder.pathKey)
                let void = trees[side]?.peeksVoid.remove(folder.pathKey) != nil
                if !void, browser.showHidden == showHidden, listing(for: side) != nil {
                    // Can't be read: no chevron, and not asked again until it changes.
                    listings[side]?.peeks[folder] = answer ?? false
                    listings[side]?.treeVersion += 1
                    // No answer and a no are both no chevron: the rows are
                    // made again only when the row's chevron is not the answer.
                    let shows = listing(for: side)?.row(of: folder)?.fold == .closed
                    if (answer == true) != shows { arrangeTree(side) }
                }
                pumpPeeks(in: side)
            }
        }
    }

    /// What was found in `folders` is out of date (they changed): they are
    /// looked into again once their rows are next arranged.
    func forgetPeeks(of folders: [URL], in side: Side) {
        guard !folders.isEmpty else { return }
        let paths = Set(folders.map(\.pathKey))
        if let peeking = trees[side]?.peeking, !peeking.isDisjoint(with: paths) {
            trees[side]?.peeksVoid.formUnion(peeking.intersection(paths))
        }
        guard let peeks = listings[side]?.peeks, !peeks.isEmpty else { return }
        let kept = peeks.filter { !paths.contains($0.key.pathKey) }
        guard kept.count != peeks.count else { return }
        listings[side]?.peeks = kept
        listings[side]?.treeVersion += 1
    }

    /// Hidden items were shown or hidden: whether a folder has something
    /// that would show is another question now, asked again of every folder.
    func forgetAllPeeks() {
        for side in [Side.left, .right] {
            if listings[side]?.peeks.isEmpty == false {
                listings[side]?.peeks = [:]
                listings[side]?.treeVersion += 1
            }
            if var tree = trees[side] {
                // Those on their way were asked with the other answer to hidden items.
                tree.peekQueue = []
                tree.peeksVoid.formUnion(tree.peeking)
                trees[side] = tree
            }
        }
    }
}
