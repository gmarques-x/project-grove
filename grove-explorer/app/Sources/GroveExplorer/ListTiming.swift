import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// `GroveExplorer --time-list [rows]`: builds the window offscreen (as
/// `--render` does: never shown, the app never started, nothing read) on a
/// made-up folder of `rows` entries, 50,000 unless given, and prints how long
/// the main thread is held by what a selection change and a sort cost: the
/// model's part, the status bar's words and the table's update. For the
/// 50,000-entry criterion, which no render can show.
@MainActor
enum ListTiming {
    static func run(_ arguments: [String]) -> Never {
        let count = arguments.first.flatMap(Int.init) ?? 50_000
        NSApplication.shared.setActivationPolicy(.prohibited)
        GroveIcons.load()

        print("A flat folder:")
        measure(Sample.model(panes: [bigFolder(count)], showHidden: false, colors: .fallback), count: count)
        // Spec §16: the same number of rows across 200 open folders.
        print("A tree, \(treeFolders) folders open:")
        measure(bigTree(count), count: count, filter: "file-1")
        exit(0)
    }

    private static func measure(_ model: AppModel, count: Int, filter: String? = nil) {
        let size = CGSize(width: 948, height: 700)
        let root = Render.offscreen(
            WindowView(model: model).content.frame(width: size.width, height: size.height), size: size,
            colors: .fallback)
        guard let table = find(FileTableView.self, in: root), let list = table.delegate as? FileList.Coordinator else {
            fail("the list isn't in the window")
        }
        let columns = ListColumns(paneWidth: size.width)
        let urls = model.entries(for: .left).map(\.url)
        print("\(urls.count) rows, \(table.numberOfRows) in the table")
        let rows = urls.count

        func step(_ name: String, _ change: () -> Void) {
            let changed = time(change)
            let status = time { _ = model.status(for: .left) }
            let update = time { list.update(columns: columns) }
            print("\(name): model \(changed) ms, status \(status) ms, table update \(update) ms")
        }
        func time(_ work: () -> Void) -> String {
            let start = DispatchTime.now().uptimeNanoseconds
            work()
            return String(format: "%.2f", Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }

        step("select one row") { model.select([urls[rows / 2]], in: .left) }
        step("select another") { model.select([urls[rows / 3]], in: .left) }
        step("select 1,000 rows") { model.select(Set(urls[..<min(1_000, urls.count)]), in: .left) }
        step("select every row") { model.select(Set(urls), in: .left) }
        step("one row again") { model.select([urls[0]], in: .left) }
        // In the app the sort itself runs off the main thread; here it is
        // on it (a fixed model sorts at once), so "model" is the sort's own time.
        step("sort by size") { model.sort(by: .size, in: .left) }
        step("sort by name") { model.sort(by: .name, in: .left) }
        if let filter {
            // As the sort: off the main thread in the app, on it here.
            step("filter \"\(filter)\"") {
                model.beginFilter()
                model.setFilter(filter, in: .left)
            }
            print("  \(model.entries(for: .left).count) rows under the filter: \(model.status(for: .left))")
            step("clear the filter") { model.clearFilter(in: .left) }
        }
    }

    private static func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
        if let found = view as? V { return found }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }

    private static let treeFolders = 200

    /// A folder of `treeFolders` folders, all open, with `count` files
    /// among them: the tree's rows, as `bigFolder` is the flat list's.
    private static func bigTree(_ count: Int) -> AppModel {
        let folder = Sample.home.appendingPathComponent("Big", isDirectory: true)
        let folders = (0..<treeFolders).map { ("folder-\(($0 * 7_919) % treeFolders)", Int64($0) * 4_096, Sample.now) }
        let model = Sample.model(
            panes: [Sample.pane(folder, folders: folders, files: [], selected: [], pointer: nil)], showHidden: false,
            colors: .fallback)
        guard let listing = model.listings[.left] else { fail("no listing") }
        let types = ["md", "swift", "png", "json", "pdf", "zip"]
        let each = max(1, (count - treeFolders) / treeFolders)
        var children: [URL: [Entry]] = [:]
        for parent in listing.all {
            children[parent.url] = (0..<each).map { number in
                let name = "file-\((number * 7_919) % each).\(types[number % types.count])"
                return Entry(
                    url: parent.url.appendingPathComponent(name), name: name, kind: .file,
                    size: Int64(number % 5_000) * 1_337, modified: Sample.now.addingTimeInterval(-Double(number) * 977),
                    isHidden: false, typeDescription: "Document")
            }
        }
        model.listings[.left]?.children = children
        model.change { $0.setOpen(Set(listing.all.map(\.url)), in: .left) }
        model.arrange(.left)
        return model
    }

    /// A folder of `count` entries: one in twenty-five a folder with a known
    /// total, the rest files of a few types, with sizes and dates that differ.
    private static func bigFolder(_ count: Int) -> Sample.Pane {
        let types = ["md", "swift", "png", "json", "pdf", "zip"]
        var folders: [(String, Int64?, Date)] = [], files: [(String, Int64, Date)] = []
        for number in 0..<count {
            let date = Sample.now.addingTimeInterval(-Double(number % 9_000) * 977)
            // Not in the order they sort in.
            let scrambled = (number * 7_919) % count
            if number % 25 == 0 {
                folders.append(("folder-\(scrambled)", Int64(scrambled) * 4_096, date))
            } else {
                files.append(("file-\(scrambled).\(types[number % types.count])", Int64(scrambled % 5_000) * 1_337, date))
            }
        }
        return Sample.pane(
            Sample.home.appendingPathComponent("Big", isDirectory: true), folders: folders, files: files, selected: [],
            pointer: nil)
    }
}
