import Foundation

/// The rules the app's open folders follow (spec §16): which are read and
/// watched, which went, how a rename in the app carries them.
extension Tree {
    /// The open folders that show, or will once a parent still being read
    /// lands: every folder between each and `root` is open and, wherever its
    /// parent's listing is in `children` (`root`'s own may be), an entry of
    /// it. These are read and watched; the rest of `open` is remembered
    /// (inside a closed folder, to show again when it opens) or gone.
    public static func reachable(open: Set<URL>, root: URL, children: [URL: [Entry]]) -> Set<URL> {
        open.subtracting(orphans(open: open, root: root, children: children))
    }

    /// The open folders that a fresh read of `folder` (its entries as
    /// `listing`) says went: those directly in it that are no `.folder`
    /// entry of it any more (removed, renamed by another program, made a
    /// file), and every open folder beneath one of those. What is open
    /// inside a closed folder that is still there stays: ← closes a folder
    /// and remembers what was open in it.
    public static func vanished(in folder: URL, listing: [Entry], open: Set<URL>) -> Set<URL> {
        let here = folder.standardizedPath
        let folders = Set(listing.lazy.filter { $0.kind == .folder }.map(\.url.standardizedPath))
        let gone = open.compactMap { url -> String? in
            let path = url.standardizedPath
            return (path as NSString).deletingLastPathComponent == here && !folders.contains(path) ? path : nil
        }
        guard !gone.isEmpty else { return [] }
        return open.filter { url in
            let path = url.standardizedPath
            return gone.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    /// `open` once the folder at `from` was renamed or moved to `to` in the
    /// app: it, and whatever was open inside it, stay open there.
    public static func remapped(_ open: Set<URL>, from: URL, to: URL) -> Set<URL> {
        let old = from.standardizedPath, new = to.standardizedPath
        return Set(open.map { url in
            let path = url.standardizedPath
            if path == old { return URL(fileURLWithPath: new, isDirectory: true) }
            guard path.hasPrefix(old + "/") else { return url }
            return URL(fileURLWithPath: new + path.dropFirst(old.count), isDirectory: true)
        })
    }

    /// `operands(of:in:)`, through `index` (where each row's URL is in
    /// `items`, as the URL is spelled there): a selection of rows that are
    /// all at depth 0 can't hold one inside another, and costs its own
    /// size, not the list's. The same URLs in the same order either way.
    public static func operands(of selection: Set<URL>, in items: [TreeItem], index: [URL: Int]) -> [URL] {
        var places: [Int] = []
        places.reserveCapacity(selection.count)
        for url in selection {
            guard let place = index[url], items.indices.contains(place), case .row(let row) = items[place],
                row.entry.url == url
            else { return operands(of: selection, in: items) }
            if row.depth > 0 { return operands(of: selection, in: items) }
            places.append(place)
        }
        return places.sorted().compactMap { if case .row(let row) = items[$0] { row.entry.url } else { nil } }
    }
}
