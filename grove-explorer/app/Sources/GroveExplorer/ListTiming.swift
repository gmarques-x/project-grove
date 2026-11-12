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

        let pane = bigFolder(count)
        let model = Sample.model(panes: [pane], showHidden: false, colors: .fallback)
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

        step("select one row") { model.select([urls[count / 2]], in: .left) }
        step("select another") { model.select([urls[count / 3]], in: .left) }
        step("select 1,000 rows") { model.select(Set(urls[..<min(1_000, urls.count)]), in: .left) }
        step("select every row") { model.select(Set(urls), in: .left) }
        step("one row again") { model.select([urls[0]], in: .left) }
        // In the app the sort itself runs off the main thread; here it is
        // on it (a fixed model sorts at once), so "model" is the sort's own time.
        step("sort by size") { model.sort(by: .size, in: .left) }
        step("sort by name") { model.sort(by: .name, in: .left) }
        exit(0)
    }

    private static func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
        if let found = view as? V { return found }
        return view.subviews.lazy.compactMap { find(type, in: $0) }.first
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
