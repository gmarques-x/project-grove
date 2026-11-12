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
            if text(element, "AXRole") == "AXTable" { return [element] }
            guard depth < 16 else { return [] }
            return list(element, "AXChildren").flatMap { tables(under: $0, depth: depth + 1) }
        }
        func same(_ a: [AXUIElement], _ b: [AXUIElement]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { CFEqual($0, $1) }
        }

        let windows = list(app, "AXWindows")
        guard let window = windows.first else {
            result.problems.append("the accessibility server gives no window: nothing was asked through it")
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
            _ = AXUIElementPerformAction(rows[0], "AXShowMenu" as CFString)
            _ = AXUIElementSetAttributeValue(rows[0], "AXSelected" as CFString, kCFBooleanTrue)
            _ = AXUIElementSetAttributeValue(table, "AXSelectedRows" as CFString, [rows[0]] as CFArray)
            if !list(table, "AXSelectedRows").isEmpty { problem("a row whose file went could still be selected") }
        }
        return result
    }

    private static func allTables(under view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(allTables)
    }
}
