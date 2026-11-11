import Testing
@testable import GroveKeysCore

/// An in-memory element tree shaped like Accessibility's: a bar item's or
/// item's first child is its menu, whose children are its items.
final class Node {
    let title: String?
    var children: [Node]
    init(_ title: String?, _ children: [Node] = []) {
        self.title = title
        self.children = children
    }
    /// An item with a submenu.
    static func menu(_ title: String, _ items: [Node]) -> Node { Node(title, [Node(nil, items)]) }
}

@Suite struct MenuResolveTests {
    let bar = Node(nil, [
        .menu("File", [Node("New Window"), Node(""), Node("Close")]),
        .menu("View", [Node("Show Tab Bar"), Node("Show Tab Bar"), .menu("Zoom", [Node("In"), Node("Out")])]),
    ])

    func find(_ steps: [(String, Int)]) -> Node? {
        MenuPath(steps: steps.map { .init(title: $0.0, index: $0.1) })
            .resolve(in: bar, title: { $0.title }, children: { $0.children })
    }

    @Test func findsItemsAtEachDepth() {
        #expect(find([("File", 0)])?.title == "File")
        #expect(find([("File", 0), ("Close", 0)])?.title == "Close")
        #expect(find([("View", 0), ("Zoom", 0), ("Out", 0)])?.title == "Out")
    }

    @Test func equalTitlesUseTheIndex() {
        let second = find([("View", 0), ("Show Tab Bar", 1)])
        #expect(second === bar.children[1].children[0].children[1])
        #expect(find([("View", 0), ("Show Tab Bar", 2)]) == nil)
    }

    @Test func missingRenamedOrMenulessStepsAreNil() {
        #expect(find([("Edit", 0)]) == nil)
        #expect(find([("File", 0), ("Print", 0)]) == nil)
        #expect(find([("File", 0), ("Close", 0), ("Anything", 0)]) == nil)
        #expect(find([]) == nil)
    }
}

@Suite struct MenuPressTests {
    @Test func theAppIsBroughtForwardBeforeThePress() {
        var events: [String] = []
        let source = RecordingSource { events.append("press") }
        let path = MenuPath(steps: [.init(title: "Edit", index: 0), .init(title: "Copy", index: 0)])
        let pressed = MenuPress.run(path, in: source, activate: { events.append("activate") })
        #expect(pressed)
        #expect(events == ["activate", "press"])
    }
}

final class RecordingSource: MenuSource, @unchecked Sendable {
    let onPress: () -> Void
    init(onPress: @escaping () -> Void) { self.onPress = onPress }
    func items(at path: MenuPath) -> [RawItem]? { nil }
    func press(_ path: MenuPath) -> Bool { onPress(); return true }
}
