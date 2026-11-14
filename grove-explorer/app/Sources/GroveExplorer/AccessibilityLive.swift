import AppKit
import ApplicationServices
import GroveExplorerCore
import GroveUI

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

    private static func launch() {
        if !launched {
            NSApp.finishLaunching()
            launched = true
        }
    }

    /// Checks the lists of `window`; `model` is what they show (a sort and
    /// a filter are put on it to move and to take away rows).
    @MainActor
    static func check(_ window: NSWindow, model: AppModel) -> Result {
        launch()
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
            // Under a filter too: a folder kept as context stays a row once closed (spec §16).
            guard let child = shown.firstIndex(where: { $0.depth > 0 }),
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

// MARK: The list's menu

extension AccessibilityLive {
    /// What the menu check found, and how much it saw.
    struct MenuResult {
        var problems: [String] = []
        var items = 0
        var apps = 0
    }

    /// The `menu` state's: the active pane's menu, opened as ⌃Return opens
    /// it (a Grove menu, `GroveMenuList`), its panel where its window is,
    /// far off every screen, asked through the accessibility server: a
    /// menu of menu items with the list's rows' titles and enabled states,
    /// Open With a submenu, which VoiceOver's press opens, with its apps.
    /// Then it is closed, and nothing of it is left.
    static func checkMenu(_ window: NSWindow, model: AppModel) -> MenuResult {
        launch()
        window.alphaValue = 0
        window.orderBack(nil)
        defer {
            GroveMenuList.close()
            window.orderOut(nil)
        }
        var result = MenuResult()
        func problem(_ words: String) { result.problems.append(words) }

        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 10)
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return value
        }
        func list(_ element: AXUIElement, _ attribute: String = "AXChildren") -> [AXUIElement] {
            (value(element, attribute) as? [AXUIElement]) ?? []
        }
        func text(_ element: AXUIElement, _ attribute: String) -> String { (value(element, attribute) as? String) ?? "" }
        /// The menus the app shows: each the content of a window of its own.
        func menus() -> [AXUIElement] {
            list(app).flatMap { list($0) }.filter { text($0, "AXRole") == "AXMenu" }
        }
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

        // ⌃Return, with the keyboard in the active pane's list.
        model.showContextMenu()
        settle()
        guard GroveMenuList.isOpen, model.reach.menuIsUp else {
            problem("⌃Return opened no menu")
            return result
        }
        // Where it is: off every screen, as its window is.
        for shown in NSApp.windows where shown.isVisible && shown !== window {
            if NSScreen.screens.contains(where: { $0.frame.intersects(shown.frame) }) {
                problem("the menu's panel is on a screen, at \(shown.frame)")
            }
        }

        // The rows it must have: the list's, for what is selected.
        let expected: [(title: String, enabled: Bool, submenu: Bool)] =
            GroveExplorerCore.ContextMenu.items(selected: model.chosenItems.count, showsHidden: model.browser.showHidden)
            .compactMap { item in
                guard case let .row(row) = item else { return nil }
                switch row.action {
                case let .command(id):
                    return (row.title, row.enabled && (CommandTable.command(id)?.isEnabled(model) ?? false), false)
                // As `ListMenu.row` has them: nothing to open, nothing to show.
                case .openWith: return (row.title, row.enabled && !model.chosenItems.isEmpty, true)
                case .showInFinder: return (row.title, row.enabled && !model.chosenItems.isEmpty, false)
                }
            }
        let open = menus()
        guard open.count == 1, let menu = open.first else {
            problem("the server gives \(open.count) menus, not 1")
            return result
        }
        let items = list(menu)
        result.items = items.count
        if items.map({ text($0, "AXTitle") }) != expected.map(\.title) {
            problem("its items are \(items.map { text($0, "AXTitle") }), not \(expected.map(\.title))")
        }
        for (item, row) in zip(items, expected) {
            let title = text(item, "AXTitle")
            if text(item, "AXRole") != "AXMenuItem" { problem("“\(title)” is no menu item") }
            if (value(item, "AXEnabled") as? Bool) != row.enabled {
                problem("“\(title)” says it is \(row.enabled ? "disabled" : "enabled")")
            }
            let submenu = list(item).filter { text($0, "AXRole") == "AXMenu" }
            if submenu.isEmpty == row.submenu { problem("“\(title)” \(row.submenu ? "has no" : "has a") submenu") }
        }

        // Open With, pressed as VoiceOver presses it: its apps, the default first.
        guard let openWith = items.first(where: { text($0, "AXTitle") == "Open With" }) else {
            problem("there is no Open With")
            return result
        }
        let pressed = AXUIElementPerformAction(openWith, kAXPressAction as CFString)
        settle()
        if pressed != .success { problem("Open With can't be pressed (\(pressed.rawValue))") }
        let apps = list(openWith).first { text($0, "AXRole") == "AXMenu" }.map { list($0) } ?? []
        result.apps = apps.count
        let found = model.openWithStandIn ?? (nil, [])
        let name = { (app: URL) in app.deletingPathExtension().lastPathComponent }
        let others = found.all.filter { $0 != found.standard }.map(name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let appTitles = found.standard.map { [name($0) + " (default)"] + others } ?? others
        let titles = apps.map { text($0, "AXTitle") }
        if titles != (appTitles.isEmpty ? ["No Application Opens This"] : appTitles) {
            problem("Open With's items are \(titles), not \(appTitles)")
        }
        if apps.contains(where: { text($0, "AXRole") != "AXMenuItem" }) { problem("an app of Open With is no menu item") }
        if menus().count != 2 { problem("with Open With open the server gives \(menus().count) menus, not 2") }

        // Closed: nothing of it is left, a key may open the next, and the
        // keyboard is where it was, in the list.
        GroveMenuList.close()
        settle()
        if GroveMenuList.isOpen || model.reach.menuIsUp { problem("closed, it is still up") }
        if !menus().isEmpty { problem("closed, the server still gives \(menus().count) menus") }
        let table = checkFocus(after: "the menu", in: window, list: nil, app: app, problem)

        // The menu of the list's empty space, with Show Hidden Items ticked:
        // nothing selected, hidden items shown; both put back after.
        let side = model.browser.active, selection = model.selection(for: side), hidden = model.browser.showHidden
        defer {
            if model.browser.showHidden != hidden { model.toggleHidden() }
            model.select(selection, in: side)
            settle()
        }
        model.select([], in: side)
        if !hidden { model.toggleHidden() }
        settle()
        model.showContextMenu()
        settle()
        guard let empty = menus().first, menus().count == 1 else {
            problem("⌃Return with nothing selected opened \(menus().count) menus, not 1")
            return result
        }
        let emptyRows = GroveExplorerCore.ContextMenu.items(selected: 0, showsHidden: true).compactMap { item in
            if case let .row(row) = item { row } else { nil }
        }
        let emptyItems = list(empty)
        if emptyItems.map({ text($0, "AXTitle") }) != emptyRows.map(\.title) {
            problem("the empty space's items are \(emptyItems.map { text($0, "AXTitle") }), not \(emptyRows.map(\.title))")
        }
        for (item, row) in zip(emptyItems, emptyRows) {
            let mark = text(item, "AXMenuItemMarkChar")
            if mark != (row.checked ? "✓" : "") {
                problem("“\(row.title)” has the mark “\(mark)”, not “\(row.checked ? "✓" : "")”")
            }
        }
        if !emptyRows.contains(where: \.checked) { problem("the empty space's menu has no ticked row to check") }
        GroveMenuList.close()
        settle()
        if !menus().isEmpty { problem("closed, the empty space's menu is still there") }
        checkFocus(after: "the empty space's menu", in: window, list: table, app: app, problem)
        return result
    }

    /// After a menu closed: the keyboard is in the list it was opened
    /// from (the window's first responder is that table, `list` the first
    /// time), and the accessibility server's list is that same table (its
    /// frame). The server's `AXFocusedUIElement` is checked when it gives
    /// one: offscreen, in an app that isn't in front (the audit never
    /// brings it there), the window can't be key, so it gives none.
    @discardableResult
    private static func checkFocus(after name: String, in window: NSWindow, list: NSTableView?,
                                   app: AXUIElement, _ problem: (String) -> Void) -> NSTableView? {
        func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return value
        }
        func role(_ element: AXUIElement) -> String { (value(element, "AXRole") as? String) ?? "" }
        guard let table = window.firstResponder as? NSTableView, list == nil || table === list else {
            problem("after \(name) closed, the keyboard is in \(String(describing: window.firstResponder)), "
                    + "not the list it was opened from")
            return list
        }
        // The table's frame as the server gives frames: points from the main
        // display's top-left corner.
        let onScreen = window.convertToScreen(table.convert(table.bounds, to: nil))
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let expected = CGRect(x: onScreen.minX, y: top - onScreen.maxY, width: onScreen.width, height: onScreen.height)
        func lists(_ element: AXUIElement) -> [AXUIElement] {
            if ["AXTable", "AXOutline"].contains(role(element)) { return [element] }
            return ((value(element, "AXChildren") as? [AXUIElement]) ?? []).flatMap(lists)
        }
        let frames: [CGRect] = ((value(app, "AXWindows") as? [AXUIElement]) ?? []).flatMap(lists).compactMap { list in
            var point = CGPoint.zero, size = CGSize.zero
            guard let position = value(list, "AXPosition"), let extent = value(list, "AXSize"),
                  AXValueGetValue(position as! AXValue, .cgPoint, &point),
                  AXValueGetValue(extent as! AXValue, .cgSize, &size) else { return nil }
            return CGRect(origin: point, size: size)
        }
        // The same column of the window: the server's frame and the view's
        // differ by a few points in height (the server's is the clipped
        // table's, with its edge), so the left, the width and an overlap.
        let close = { (a: CGRect) in
            abs(a.minX - expected.minX) <= 1 && abs(a.width - expected.width) <= 1 && a.intersects(expected)
        }
        if !frames.contains(where: close) {
            problem("after \(name) closed, the server has no list where the focused table is (\(expected)); it has \(frames)")
        }
        if let focused = value(app, "AXFocusedUIElement"), CFGetTypeID(focused) == AXUIElementGetTypeID(),
           !["AXTable", "AXOutline"].contains(role(focused as! AXUIElement)) {
            problem("after \(name) closed, the server's focused element is \(role(focused as! AXUIElement)), not the list")
        }
        return table
    }}
