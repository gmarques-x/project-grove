import AppKit
import ApplicationServices
import GroveExplorerCore

/// The audit's second half: the lists asked as an assistive app asks them,
/// through the accessibility server, with the tokens such an app holds.
/// What the in-process walk can't see is here: a token stands for one
/// object and dies with it, so a row must be the same live object from
/// one answer to the next.
///
/// The client is this process itself (`AXUIElementCreateApplication` of
/// its own pid). A question a process puts to itself is answered on the
/// thread that asks, so it is asked on the main thread, where the app's
/// accessibility code expects to be. For the server to answer, the
/// application has to have finished launching (its run loop is still
/// never run, and no delegate or scene starts) and the window has to be
/// ordered in: it is, far off every screen and clear, for the length of
/// the check, and ordered out again.
@MainActor
enum AccessibilityLive {
    /// What was found wrong, and how many things were asked.
    struct Result: Sendable {
        var problems: [String] = []
        var asked = 0
        var tables = 0
        /// Rows inside an open folder whose level was checked, folders
        /// whose fold was, and rows kept through their folder's close and reopen.
        var levels = 0
        var folds = 0
        var reopened = 0
    }

    /// The server's own word for "that element is gone".
    private static let gone = AXError.invalidUIElement

    private static var launched = false

    /// Checks the lists of `window`; `model` is what they show (a sort and
    /// a filter are put on it to move and to take away rows).
    @MainActor
    static func check(_ window: NSWindow, model: AppModel) -> Result {
        if !launched {
            NSApp.finishLaunching()
            launched = true
        }
        window.alphaValue = 0
        window.orderBack(nil)
        defer { window.orderOut(nil) }

        return client(sides: model.sides, window: window, model: model)
    }

    /// Lets the run loop turn: SwiftUI brings the lists in line with the
    /// model, and what a turn releases is released.
    private static func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    private static func client(sides: [Side], window shown: NSWindow, model: AppModel) -> Result {
        var result = Result()
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 10)

        func value(_ element: AXUIElement, _ attribute: String) -> (value: CFTypeRef?, error: AXError) {
            var value: CFTypeRef?
            result.asked += 1
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return (value, error)
        }
        func list(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
            (value(element, attribute).value as? [AXUIElement]) ?? []
        }
        func text(_ element: AXUIElement, _ attribute: String) -> String? { value(element, attribute).value as? String }
        func tables(under element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
            // A list is an outline, as an `NSOutlineView` is: its folders open in place.
            if text(element, "AXRole") == "AXOutline" { return [element] }
            guard depth < 16 else { return [] }
            return list(element, "AXChildren").flatMap { tables(under: $0, depth: depth + 1) }
        }
        func same(_ a: [AXUIElement], _ b: [AXUIElement]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { CFEqual($0, $1) }
        }
        func settable(_ element: AXUIElement, _ attribute: String) -> Bool {
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
            return settable.boolValue
        }

        /// Each row as an `NSOutlineView`'s says it: an outline row, its
        /// level (0 for the tab folder's items), whether its folder is open
        /// (a folder can be opened and closed by setting that, nothing else
        /// can), the row it is inside, and the rows it has open beneath it.
        func checkTree(_ rows: [AXUIElement], shown: [TreeRow], problem: (String) -> Void) {
            for (index, (row, tree)) in zip(rows, shown).enumerated() {
                if text(row, "AXSubrole") != "AXOutlineRow" {
                    problem("row \(index) is not an outline's row")
                    break
                }
                if (value(row, "AXDisclosureLevel").value as? Int) != tree.depth {
                    problem("row \(index) does not say its level, \(tree.depth)")
                }
                let open = tree.fold == .open || tree.fold == .loading
                if (value(row, "AXDisclosing").value as? Bool) != open {
                    problem("row \(index) does not say its folder is \(open ? "open" : "closed")")
                }
                if settable(row, "AXDisclosing") != (tree.fold != .none) {
                    problem("row \(index) \(tree.fold == .none ? "can be" : "can't be") opened or closed")
                }
                let parent = tree.depth == 0 ? nil : shown[..<index].lastIndex { $0.depth == tree.depth - 1 }
                let by = value(row, "AXDisclosedByRow").value
                if let parent, !(by.map { CFEqual($0, rows[parent]) } ?? false) {
                    problem("row \(index) does not say it is inside row \(parent)")
                } else if parent == nil, by != nil {
                    problem("row \(index), at the top, says it is inside a row")
                }
                let beneath = shown[(index + 1)...].prefix { $0.depth > tree.depth }
                let disclosed = beneath.indices.filter { shown[$0].depth == tree.depth + 1 }.map { rows[$0] }
                if !same(disclosed, list(row, "AXDisclosedRows")) { problem("row \(index) does not give the rows it has open") }
                if tree.depth > 0 { result.levels += 1 }
                if tree.fold != .none { result.folds += 1 }
            }
        }

        /// A folder closed by VoiceOver's fold action and opened again: the
        /// rows that were inside it are no rows while it is closed, and
        /// after its read lands they are the same elements, saying the same.
        func checkCloseAndReopen(
            _ table: AXUIElement, rows: [AXUIElement], shown: [TreeRow], model: AppModel, side: Side,
            problem: (String) -> Void
        ) {
            // Under a filter a folder kept for the matches inside it is no
            // row once closed (nothing inside it shows): there is no row to open again.
            guard model.listing(for: side)?.filteredFrom == nil,
                let child = shown.firstIndex(where: { $0.depth > 0 }),
                let parent = shown[..<child].lastIndex(where: { $0.depth == shown[child].depth - 1 })
            else { return }
            let folder = shown[parent].entry.url.pathKey
            let said = rows.map { text($0, "AXDescription") }
            // The audit reads nothing: the listings the folder had are put back, as its read would.
            let read = model.listings[side]?.children.filter {
                $0.key.pathKey == folder || $0.key.pathKey.hasPrefix(folder + "/")
            } ?? [:]
            let closing = AXUIElementSetAttributeValue(rows[parent], "AXDisclosing" as CFString, kCFBooleanFalse)
            settle()
            guard closing == .success else { return problem("a folder can't be closed (error \(closing.rawValue))") }
            if (value(rows[parent], "AXDisclosing").value as? Bool) != false { problem("a folder closed says it is open") }
            if list(table, "AXRows").contains(where: { CFEqual($0, rows[child]) }) {
                problem("a row inside a closed folder is still a row")
            }
            let opening = AXUIElementSetAttributeValue(rows[parent], "AXDisclosing" as CFString, kCFBooleanTrue)
            settle()
            guard opening == .success else { return problem("a folder can't be opened (error \(opening.rawValue))") }
            if (value(rows[parent], "AXDisclosing").value as? Bool) != true { problem("a folder opened says it is closed") }
            model.listings[side]?.children.merge(read) { $1 }
            model.listings[side]?.treeVersion += 1
            model.arrange(side)
            settle()
            if !same(rows, list(table, "AXRows")) {
                problem("the rows after a folder was closed and opened again are not the same elements")
            } else if rows.map({ text($0, "AXDescription") }) != said {
                problem("a row says other words after its folder was closed and opened again")
            } else {
                result.reopened += shown[(parent + 1)...].prefix { $0.depth > shown[parent].depth }.count
            }
        }

        let windows = list(app, "AXWindows")
        guard let window = windows.first else {
            // The usual reason: the program that runs this (the terminal)
            // is not allowed to use the accessibility server.
            let why = AXIsProcessTrusted()
                ? ""
                : " (this process is not trusted for accessibility: allow the terminal that runs it under"
                    + " Privacy & Security › Accessibility)"
            result.problems.append("the accessibility server gives no window: nothing was asked through it" + why)
            return result
        }
        let found = tables(under: window)
        result.tables = found.count
        // A window under the conflict prompt offers only the prompt.
        guard found.count == sides.count else {
            if model.work.prompt == nil {
                result.problems.append("\(found.count) lists were found for \(sides.count) panes: they were not checked")
            }
            return result
        }

        for (side, table) in zip(sides, found) {
            let name = "list of the \(side == .left ? "left" : "right") pane"
            func problem(_ words: String) { result.problems.append("\(name): \(words)") }

            // VoiceOver says what the list is by its description, as an NSOutlineView's.
            let described = text(table, "AXRoleDescription") ?? ""
            if described != NSAccessibility.Role.outline.description(with: nil) {
                problem("the list is described as “\(described)”, not as an outline")
            }
            let rows = list(table, "AXRows")
            guard !rows.isEmpty else { continue }
            // 1. A row answers: what it is, what it says, where it is, whose it is.
            let said = rows.map { text($0, "AXDescription") }
            for (index, row) in rows.enumerated() {
                let role = value(row, "AXRole")
                if role.error != .success || role.value as? String != "AXRow" {
                    problem("row \(index) does not answer for its role (error \(role.error.rawValue))")
                    break
                }
                if (said[index] ?? "").isEmpty { problem("row \(index) says nothing") }
                if (value(row, "AXIndex").value as? Int) != index { problem("row \(index) is not at its index") }
                if !(value(row, "AXParent").value.map { CFEqual($0, table) } ?? false) { problem("row \(index) is not the table's") }
                if !(value(row, "AXWindow").value.map { CFEqual($0, window) } ?? false) { problem("row \(index) has not the window") }
                if value(row, "AXChildren").value.map({ ($0 as? [AXUIElement])?.isEmpty == false }) ?? false {
                    problem("row \(index) has children")
                }
            }
            var actions: CFArray?
            AXUIElementCopyActionNames(rows[0], &actions)
            if !((actions as? [String]) ?? []).contains("AXShowMenu") { problem("a row has no show-menu action") }
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(rows[0], "AXSelected" as CFString, &settable)
            if !settable.boolValue { problem("a row can't be selected") }
            if rows.count > 1, CFEqual(rows[0], rows[1]) { problem("two different rows are the same element") }
            // The columns have names.
            for column in list(table, "AXColumns") where (text(column, "AXDescription") ?? "").isEmpty {
                problem("a column has no name")
            }
            // A count and a part of the list, as asked for a long one.
            var count: CFIndex = 0
            AXUIElementGetAttributeValueCount(table, "AXRows" as CFString, &count)
            if count != rows.count { problem("the count of rows (\(count)) is not the rows' (\(rows.count))") }
            var part: CFArray?
            AXUIElementCopyAttributeValues(table, "AXChildren" as CFString, 0, 2, &part)
            if !same(Array(rows.prefix(2)), (part as? [AXUIElement]) ?? []) { problem("a part of the children is not those children") }

            // 2. Asked again: the same elements.
            if !same(rows, list(table, "AXRows")) { problem("two successive answers give rows that are not the same elements") }

            // 3. After what a turn of the run loop releases is released, and
            // the list is loaded again: still there, still the same.
            settle()
            if value(rows[0], "AXRole").error == gone { problem("a row is gone once the answer it came in is released") }
            (shown.contentView.map(allTables) ?? []).forEach { $0.reloadData() }
            settle()
            if value(rows[0], "AXRole").error == gone { problem("a row is gone after the list is loaded again") }
            if !same(rows, list(table, "AXRows")) { problem("the rows after a reload are not the same elements") }

            // 3b. The tree (spec §16), as an outline's rows say it: each
            // row's level, whether its folder is open, the row it is in
            // and the rows it has open, as the model has them.
            let shown = treeRows(model, side)
            if shown.count != rows.count {
                problem("\(rows.count) rows for the tree's \(shown.count) (a loading line is no row)")
            } else {
                checkTree(rows, shown: shown, problem: problem)
                checkCloseAndReopen(table, rows: rows, shown: shown, model: model, side: side, problem: problem)
            }

            // 4. The rows move (the sort is turned round): a row held
            // follows its file to where that is now.
            model.sort(by: .name, in: side)
            settle()
            let moved = list(table, "AXRows")
            if moved.count == rows.count, rows.count > 1 {
                if same(rows, moved) { problem("turning the sort round moved no row: the check could not be made") }
                for (index, row) in rows.enumerated() {
                    guard let now = moved.firstIndex(where: { CFEqual($0, row) }) else {
                        problem("row \(index) is not among the rows after they moved")
                        break
                    }
                    if text(row, "AXDescription") != said[index] { problem("row \(index) says another file's words after the rows moved") }
                    if (value(row, "AXIndex").value as? Int) != now { problem("row \(index) did not follow its file to row \(now)") }
                }
            } else {
                problem("the rows after the sort was turned round are not as many (\(moved.count) for \(rows.count))")
            }

            // 5. The files go (a filter that nothing matches): a row held
            // answers that it is gone, or with nothing; it doesn't answer
            // as another file, and nothing breaks.
            model.beginFilter()
            model.setFilter("\u{1}no name has this\u{1}", in: side)
            settle()
            let left = list(table, "AXRows")
            if !left.isEmpty { problem("a filter nothing matches left \(left.count) rows: the check could not be made") }
            let after = value(rows[0], "AXDescription")
            if after.error == .success, let words = after.value as? String, !words.isEmpty {
                problem("a row whose file went still says “\(words)”")
            }
            // Only of a row whose file did go: with rows left, the first
            // may be a live one, and its menu would really open.
            if left.isEmpty {
                _ = AXUIElementPerformAction(rows[0], "AXShowMenu" as CFString)
                _ = AXUIElementSetAttributeValue(rows[0], "AXSelected" as CFString, kCFBooleanTrue)
                _ = AXUIElementSetAttributeValue(table, "AXSelectedRows" as CFString, [rows[0]] as CFArray)
                if !list(table, "AXSelectedRows").isEmpty { problem("a row whose file went could still be selected") }
            }
        }
        return result
    }

    /// The rows of the pane's tree in their order: what the list shows but
    /// its loading lines, which are no rows to VoiceOver.
    private static func treeRows(_ model: AppModel, _ side: Side) -> [TreeRow] {
        (model.listing(for: side)?.items ?? []).compactMap { if case .row(let row) = $0 { row } else { nil } }
    }

    private static func allTables(under view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(allTables)
    }
}
