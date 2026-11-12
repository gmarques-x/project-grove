import AppKit
import GroveExplorerCore
import GroveThemesCore

/// `GroveExplorer --audit-accessibility <state>|all [--tree]`: builds the
/// window of a render's state, offscreen as a render does (no window is
/// shown, the app never starts), walks the accessibility tree under it and
/// prints every control that has nothing to say for itself: no label and
/// no title. With `--tree`, the whole tree as VoiceOver would meet it.
/// Exits 1 when a control is unlabelled, a tree could not be walked, or a
/// command has no action.
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
    /// Deeper than any window's tree goes: one that loops is said, not walked for ever.
    private static let deepest = 60

    private struct Count {
        var elements = 0
        var controls = 0
        var unlabelled: [String] = []
    }

    static func run(_ arguments: [String]) -> Never {
        let tree = arguments.contains("--tree")
        let names = arguments.filter { $0 != "--tree" }
        guard names.count == 1 else {
            fail("usage: GroveExplorer --audit-accessibility <state>|all [--tree]\nstates: \(Render.stateNames)")
        }
        let states = names[0] == "all" ? Render.stateNames.components(separatedBy: ", ") : [names[0]]
        var failed = false
        for state in states {
            let (view, _, _) = Render.window(showing: state, colors: ThemeColors.fallback)
            wakeAccessibility(of: view)
            var count = Count()
            if tree { print("\(state):") }
            walk(view, depth: 1, path: [], tree: tree, into: &count)
            print("\(state): \(count.elements) elements, \(count.controls) controls, \(count.unlabelled.count) unlabelled")
            for line in count.unlabelled { print("  UNLABELLED \(line)") }
            // The header alone has more: SwiftUI's part of the tree was not there to walk.
            if count.elements < 10 {
                print("  the accessibility tree was not built offscreen: nothing was checked")
                failed = true
            }
            if !count.unlabelled.isEmpty { failed = true }
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

    private static func walk(_ element: Any, depth: Int, path: [String], tree: Bool, into count: inout Count) {
        guard let node = element as? NSObject else { return }
        guard depth < deepest else {
            count.unlabelled.append("the tree is deeper than \(deepest) under " + path.joined(separator: " › "))
            return
        }
        let role = text("accessibilityRole", of: node)
        let isElement = (value("isAccessibilityElement", key: "accessibilityElement", of: node) as? Bool) ?? false
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
            }
            path.append(words)
            // A scroll bar is the system's own, parts and all.
            if role == "AXScrollBar" { return }
        }
        // SwiftUI's hosting view has its nodes in the order VoiceOver walks them.
        var children = (value("accessibilityChildrenInNavigationOrder", of: node) as? [Any]) ?? []
        if children.isEmpty { children = (value("accessibilityChildren", of: node) as? [Any]) ?? [] }
        for child in children {
            walk(child, depth: depth + (isElement ? 1 : 0), path: path, tree: tree, into: &count)
        }
    }
}
