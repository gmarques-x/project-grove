import Foundation
@testable import GroveExplorerCore
import Testing

/// The session to and from a file, in a temporary folder of the test's own.
@Suite final class SessionTests {
    private let root: URL
    private let file: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grove-explorer-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        file = root.appendingPathComponent("explorer-session.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Two panes, several tabs, history and a sort: something of everything.
    private func session() -> Session {
        var browser = Browser(start: folder("/Users/someone"), twoPanes: true, showHidden: true)
        browser.go(to: folder("/Users/someone/Developer"))
        browser.go(to: folder("/Users/someone/Developer/project grove"))
        _ = browser.goBack()
        browser.newTab(folder: URL(fileURLWithPath: "/var/x"))
        browser.setSort(.modified)
        browser.setSort(.modified)
        browser.switchPane()
        browser.go(to: folder("/Volumes/Backup/é"))
        return Session(browser: browser, sidebarWidth: 212.5, split: 0.4, sidebarHidden: true)
    }

    private func write(_ text: String) throws {
        try Data(text.utf8).write(to: file)
    }

    @Test func aSavedSessionLoadsAsItWas() throws {
        let session = session()
        try session.save(to: file)
        #expect(Session.load(from: file) == session)
    }

    @Test func savingReplacesTheFileAndLeavesNothingElse() throws {
        try session().save(to: file)
        var later = session()
        later.sidebarHidden = false
        later.browser.togglePanes()
        try later.save(to: file)

        #expect(Session.load(from: file) == later)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
            == ["explorer-session.json"])
    }

    @Test func savingMakesTheFolderWhenItIsMissing() throws {
        let deeper = root.appendingPathComponent("state/grove/explorer-session.json")
        let session = session()
        try session.save(to: deeper)
        #expect(Session.load(from: deeper) == session)
    }

    @Test func savingWhereItCannotBeWrittenThrows() throws {
        try write("in the way")
        #expect(throws: (any Error).self) {
            try self.session().save(to: self.file.appendingPathComponent("inside-a-file.json"))
        }
    }

    @Test func noFileIsNoSession() {
        #expect(Session.load(from: file) == nil)
    }

    @Test func garbageIsNoSession() throws {
        try write("\u{0}\u{1}not json at all {{{")
        #expect(Session.load(from: file) == nil)
        try write("")
        #expect(Session.load(from: file) == nil)
        try write(#"{"browser": 3}"#)
        #expect(Session.load(from: file) == nil)
        try write("[]")
        #expect(Session.load(from: file) == nil)
    }

    @Test func aFileFromAFutureShapeStillLoads() throws {
        let session = session()
        try session.save(to: file)

        // A later version's file: a key this one doesn't know at each level.
        var top = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        top["previewWidth"] = 300
        var browser = try #require(top["browser"] as? [String: Any])
        browser["columns"] = ["name", "tags"]
        var panes = try #require(browser["panes"] as? [[String: Any]])
        panes[0]["view"] = "icons"
        var tabs = try #require(panes[0]["tabs"] as? [[String: Any]])
        tabs[0]["selection"] = ["a.txt"]
        panes[0]["tabs"] = tabs
        browser["panes"] = panes
        top["browser"] = browser
        try JSONSerialization.data(withJSONObject: top).write(to: file)

        #expect(Session.load(from: file) == session)
    }

    /// A file that parses but describes a window that can't be: it would
    /// crash the first time the active tab is asked for.
    @Test(arguments: [
        "noPanes", "threePanes", "aPaneWithoutTabs", "currentPastTheTabs", "currentNegative",
        "activeWithoutAPane",
    ])
    func aSessionThatCannotBeIsNoSession(_ damage: String) throws {
        var session = session()
        switch damage {
        case "noPanes": session.browser.panes = []
        case "threePanes": session.browser.panes.append(session.browser.panes[0])
        case "aPaneWithoutTabs": session.browser.panes[1].tabs = []
        case "currentPastTheTabs": session.browser.panes[0].current = 2
        case "currentNegative": session.browser.panes[0].current = -1
        default:
            session.browser.panes.removeLast()
            session.browser.active = .right
        }
        try session.save(to: file)
        #expect(Session.load(from: file) == nil)
    }
}
