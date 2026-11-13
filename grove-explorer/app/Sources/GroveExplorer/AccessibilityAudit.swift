import AppKit
import GroveExplorerCore
import GroveThemesCore

/// `GroveExplorer --audit-accessibility <state>|all [--tree]`: builds the
/// window of a render's state, offscreen as a render does (no window is
/// shown, the app never starts), walks the accessibility tree under it and
/// prints every control that has nothing to say for itself: no label and
/// no title; and every cell, column, busy indicator or thing of no known
/// kind that has no label, no value and nothing inside it (VoiceOver
/// would stop on it and say nothing). With `--tree`, the whole tree as
/// VoiceOver would meet it. Exits 1 on any of those, when a tree could
/// not be walked, or a command has no action; 2 when it has not ended
/// after a minute.
///
/// Then each list is asked through the accessibility server, as an
/// assistive app asks (`AccessibilityLive`): for that alone the
/// application finishes launching and the window is ordered in, clear and
/// far off every screen, and out again. Nothing is ever on a screen.
///
/// What it can't tell: how VoiceOver words an element, what it announces
/// when something changes, and anything of the menus. Those are by hand.
@MainActor
enum AccessibilityAudit {
    /// What must say what it is.
    private static let controls: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXSlider",
        "AXIncrementor", "AXLink", "AXDisclosureTriangle", "AXComboBox", "AXTable", "AXOutline", "AXList",
        "AXProgressIndicator", "AXImage", "AXTabGroup", "AXSplitter", "AXValueIndicator",
    ]
    /// What VoiceOver stops on whatever it is: it must say something or hold something.
    private static let stops: Set<String> = ["AXCell", "AXColumn", "AXBusyIndicator", "AXUnknown"]
    /// Deeper than any window's tree goes.
    private static let deepest = 60
    /// The audit ends by then, done or not: this many seconds for a
    /// state, three times that for all of them (they take about one each;
    /// a loaded machine is slower, a walk that is stuck never ends).
    private static let limit = 60

    private struct Count {
        var elements = 0
        var controls = 0
        var unlabelled: [String] = []
        /// How many rows were asked for twice, and again after a reload, and compared.
        var identityChecked = 0
        /// The nodes met: one that comes round again is not walked twice,
        /// whether or not it is an element (a loop through things that are
        /// none never gets deeper by the count of elements).
        var seen: Set<ObjectIdentifier> = []
    }

    static func run(_ arguments: [String]) -> Never {
        let tree = arguments.contains("--tree")
        let names = arguments.filter { $0 != "--tree" }
        guard names.count == 1 else {
            fail("usage: GroveExplorer --audit-accessibility <state>|all [--tree]\nstates: \(Render.stateNames)")
        }
        let states = names[0] == "all" ? Render.stateNames.components(separatedBy: ", ") : [names[0]]
        // Off the main thread, which may be the one that is stuck.
        let limit = states.count == 1 ? limit : 3 * limit
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(limit)) {
            FileHandle.standardError.write(Data("the audit has not ended after \(limit) seconds: given up\n".utf8))
            exit(2)
        }
        var failed = false
        for state in states {
            let (view, _, model) = Render.window(showing: state, colors: ThemeColors.fallback)
            wakeAccessibility(of: view)
            var count = Count()
            if tree { print("\(state):") }
            walk(view, depth: 1, path: [], tree: tree, into: &count)
            print(
                "\(state): \(count.elements) elements, \(count.controls) controls, \(count.unlabelled.count) unlabelled"
                    + (count.identityChecked > 0 ? ", \(count.identityChecked) rows the same objects across answers and a reload" : ""))
            for line in count.unlabelled { print("  UNLABELLED \(line)") }
            // The header alone has more: SwiftUI's part of the tree was not there to walk.
            if count.elements < 10 {
                print("  the accessibility tree was not built offscreen: nothing was checked")
                failed = true
            }
            if !count.unlabelled.isEmpty { failed = true }
            // Then the lists as an assistive app is served them.
            if let window = view.window {
                let live = AccessibilityLive.check(window, model: model)
                print(
                    "  through the accessibility server: \(live.tables) lists, \(live.asked) questions, "
                        + "\(live.problems.count) problems"
                        + (live.folds > 0
                            ? "; \(live.levels) rows at their levels, \(live.folds) folders open or closed, "
                                + "\(live.reopened) rows kept through a close and reopen"
                            : ""))
                for problem in live.problems { print("  LIVE \(problem)") }
                if !live.problems.isEmpty { failed = true }
            }
        }
        let missing = CommandTable.missingActions, stray = CommandTable.strayActions
        print("commands without an action: \(missing.isEmpty ? "none" : missing.joined(separator: ", "))")
        print("actions without a command: \(stray.isEmpty ? "none" : stray.joined(separator: ", "))")
        exit(failed || !missing.isEmpty || !stray.isEmpty ? 1 : 0)
    }

    /// SwiftUI builds its part of the tree only once an assistive app has
    /// said it is there. Said here to this process alone, the way such an
    /// app says it (the attribute it sets on a program it is about to
    /// read; nothing of the system's is set or asked), then a few turns of
    /// the run loop for the tree to be made.
    private static func wakeAccessibility(of view: NSView) {
        // By name: it is the older way of setting an attribute, which is
        // the one an assistive app's request comes in by.
        let set = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        guard NSApp.responds(to: set) else { return }
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(set, with: true as NSNumber, with: attribute as NSString)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()
    }

    // The tree's nodes are AppKit's views, AppKit's own stand-ins for rows
    // and columns, and SwiftUI's nodes: what they share is the methods of
    // the accessibility protocol, asked for here by name.

    /// The older names of the same questions, which AppKit's stand-ins for
    /// a table's rows still answer to.
    private static let attributes = [
        "accessibilityRole": "AXRole", "accessibilityLabel": "AXDescription", "accessibilityTitle": "AXTitle",
        "accessibilityValue": "AXValue", "accessibilityChildren": "AXChildren", "isAccessibilitySelected": "AXSelected",
    ]

    /// What the node's method `getter` answers; nil when it has none.
    /// `key` is the same for key-value coding ("accessibilityElement" for
    /// `isAccessibilityElement`).
    private static func value(_ getter: String, key: String? = nil, of node: NSObject) -> Any? {
        if node.responds(to: NSSelectorFromString(getter)) { return node.value(forKey: key ?? getter) }
        let older = NSSelectorFromString("accessibilityAttributeValue:")
        if let attribute = attributes[getter], node.responds(to: older) {
            return node.perform(older, with: attribute as NSString)?.takeUnretainedValue()
        }
        if getter == "isAccessibilityElement", node.responds(to: NSSelectorFromString("accessibilityIsIgnored")) {
            return (node.value(forKey: "accessibilityIsIgnored") as? Bool).map { !$0 }
        }
        return nil
    }

    private static func text(_ getter: String, of node: NSObject) -> String {
        switch value(getter, of: node) {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    /// A table answers two ways of asking, the older by attribute: an
    /// assistive app served by that one must be given the same rows and
    /// columns (the list's own, not the table's silent stand-ins).
    private static func checkOlderAnswers(of table: NSObject, path: [String], into count: inout Count) {
        let older = NSSelectorFromString("accessibilityAttributeValue:")
        guard table.responds(to: older) else { return }
        for (attribute, getter) in [
            ("AXChildren", "accessibilityChildren"), ("AXRows", "accessibilityRows"),
            ("AXVisibleRows", "accessibilityVisibleRows"), ("AXSelectedRows", "accessibilitySelectedRows"),
            ("AXColumns", "accessibilityColumns"),
        ] {
            let old = table.perform(older, with: attribute as NSString)?.takeUnretainedValue() as? [NSObject] ?? []
            let new = table.value(forKey: getter) as? [NSObject] ?? []
            if old.count != new.count || zip(old, new).contains(where: { $0 !== $1 }) {
                count.unlabelled.append(
                    (path + ["\(attribute) asked the older way gives other elements"]).joined(separator: " › "))
            }
        }
    }

    /// An assistive app holds a row by the object it was given: a table's
    /// rows must be the same objects from one answer to the next, and
    /// after the list is loaded again, as a folder that changes does to
    /// it. (`AccessibilityLive` asks the same through the server.)
    private static func checkRowsKeepTheirIdentity(in table: NSObject, path: [String], into count: inout Count) {
        func rows() -> [NSObject] { table.value(forKey: "accessibilityRows") as? [NSObject] ?? [] }
        // The same objects: a token an assistive app holds is one object's.
        func same(_ a: [NSObject], _ b: [NSObject]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { $0 === $1 }
        }
        let first = autoreleasepool { rows() }, second = autoreleasepool { rows() }
        (table as? NSTableView)?.reloadData()
        let afterReload = autoreleasepool { rows() }
        var problems: [String] = []
        if !same(first, second) { problems.append("two answers in a row give rows that are not the same objects") }
        if !same(first, afterReload) { problems.append("the rows after a reload are not the same objects as before") }
        if first.count > 1, first[0] === first[1] { problems.append("two different rows are one object") }
        for problem in problems { count.unlabelled.append((path + [problem]).joined(separator: " › ")) }
        count.identityChecked += first.count
    }

    private static func walk(_ element: Any, depth: Int, path: [String], tree: Bool, into count: inout Count) {
        guard let node = element as? NSObject, count.seen.insert(ObjectIdentifier(node)).inserted else { return }
        guard depth < deepest else {
            count.unlabelled.append("the tree is deeper than \(deepest) under " + path.joined(separator: " › "))
            return
        }
        let role = text("accessibilityRole", of: node)
        let isElement = (value("isAccessibilityElement", key: "accessibilityElement", of: node) as? Bool) ?? false
        // SwiftUI's hosting view has its nodes in the order VoiceOver walks them.
        var children = (value("accessibilityChildrenInNavigationOrder", of: node) as? [Any]) ?? []
        if children.isEmpty { children = (value("accessibilityChildren", of: node) as? [Any]) ?? [] }
        var path = path
        if isElement, !role.isEmpty {
            count.elements += 1
            let name = [text("accessibilityLabel", of: node), text("accessibilityTitle", of: node)].first { !$0.isEmpty } ?? ""
            let said = text("accessibilityValue", of: node)
            let selected = (value("isAccessibilitySelected", key: "accessibilitySelected", of: node) as? Bool) == true
            let words = role + (name.isEmpty ? "" : " “\(name)”") + (said.isEmpty ? "" : " = “\(said)”")
                + (selected ? " [selected]" : "")
            if tree { print(String(repeating: "  ", count: depth) + words) }
            if controls.contains(role) {
                count.controls += 1
                // A text field's text is no name for it.
                if name.isEmpty { count.unlabelled.append((path + [words]).joined(separator: " › ")) }
            } else if stops.contains(role), name.isEmpty, said.isEmpty, children.isEmpty {
                count.unlabelled.append((path + [words]).joined(separator: " › ") + " (says nothing, holds nothing)")
            }
            path.append(words)
            // A scroll bar is the system's own, parts and all.
            if role == "AXScrollBar" { return }
        }
        for child in children {
            walk(child, depth: depth + (isElement ? 1 : 0), path: path, tree: tree, into: &count)
        }
        // After its rows were walked: the second check loads the list again.
        if isElement, role == "AXOutline" {
            checkOlderAnswers(of: node, path: path, into: &count)
            checkRowsKeepTheirIdentity(in: node, path: path, into: &count)
        }
    }
}
