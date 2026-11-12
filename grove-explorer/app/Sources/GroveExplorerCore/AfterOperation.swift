import Foundation

/// What the window does once a run has ended: which items it selects and
/// which folder totals are no longer right.
public enum AfterOperation {
    /// The items a run left where the user will look for them: what was
    /// made (a copy, a duplicate, a new folder) and what was moved or
    /// renamed, where it now is. They are selected, as Finder does.
    public static func newItems(of outcome: Outcome) -> [URL] {
        outcome.changes.compactMap { change in
            switch change {
            case let .created(url): url
            case let .moved(_, to): to
            case .trashed, .replaced: nil
            }
        }
    }

    /// Of `new`, the items of `folder` that its listing has, as the listing
    /// writes their URLs (`listed`), and whether that is all of them: a
    /// listing read while the run was going may have only some.
    public static func arrivals(_ new: [URL], in folder: URL, listed: [URL]) -> (found: [URL], complete: Bool) {
        let here = folder.standardizedFileURL.path
        let expected = new.map(\.standardizedFileURL).filter { $0.deletingLastPathComponent().path == here }.map(\.path)
        guard !expected.isEmpty else { return ([], false) }
        var byPath: [String: URL] = [:]
        for url in listed { byPath[url.standardizedFileURL.path] = url }
        let found = expected.compactMap { byPath[$0] }
        return (found, found.count == expected.count)
    }

    /// The folders whose contents a run changed, each once: where its items
    /// were and where they went, and the folders of every change it made.
    public static func touchedFolders(by operation: Operation, outcome: Outcome) -> [URL] {
        var folders: [URL] = []
        func parent(_ url: URL) -> URL { url.deletingLastPathComponent() }
        switch operation {
        case let .copy(_, folder): folders.append(folder)
        case let .move(items, folder): folders += [folder] + items.map(parent)
        case let .duplicate(items), let .trash(items): folders += items.map(parent)
        case let .rename(item, _): folders.append(parent(item))
        case let .newFolder(folder, _): folders.append(folder)
        }
        for change in outcome.changes {
            switch change {
            case let .created(url): folders.append(parent(url))
            case let .moved(from, to): folders += [parent(from), parent(to)]
            case let .trashed(original, _), let .replaced(original, _): folders.append(parent(original))
            }
        }
        var seen: Set<String> = []
        return folders.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Of the folders whose totals are `known`, those no longer right once
    /// `touched` changed: each touched folder and every folder it is in.
    public static func staleTotals(among known: [URL], touched: [URL]) -> [URL] {
        let changed = touched.map(\.standardizedFileURL.path)
        return known.filter { url in
            let path = url.standardizedFileURL.path
            let prefix = path == "/" ? "/" : path + "/"
            return changed.contains { $0 == path || $0.hasPrefix(prefix) }
        }
    }
}
