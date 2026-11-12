import Testing
@testable import GroveKeysCore

@Suite struct MenuFailureTests {
    @Test func eachFailureNamesTheRowAndTheReason() {
        #expect(MenuFailure.title == "Grove")
        #expect(MenuFailure.cannotStart(row: "Reload", reason: "The file doesn’t exist.").body
                == "\"Reload\" couldn't start: The file doesn’t exist.")
        #expect(MenuFailure.nothingToOpen(row: "Notes", target: "ht tp://x").body
                == "\"Notes\" has nothing to open: ht tp://x")
        #expect(MenuFailure.nothingToOpen(row: "Notes", target: "").body
                == "\"Notes\" has nothing to open: its open line is empty")
        #expect(MenuFailure.unknownRow(id: "lokc").body == "No row \"lokc\" in the Grove menu")
        #expect(MenuFailure.cannotLock(reason: "pmset is missing").body
                == "\"Lock\" couldn't lock the screen: pmset is missing")
        #expect(MenuFailure.menuItemGone(path: ["File", "Export", "PDF…"]).body
                == "\"PDF…\" is no longer in the app's menu (File › Export)")
        #expect(MenuFailure.menuItemGone(path: ["Quit"]).body == "\"Quit\" is no longer in the app's menu")
    }

    @Test func theBodyIsOneLineAndNotEndless() {
        let body = MenuFailure.cannotStart(row: "A", reason: "first\n  second\n\nthird").body
        #expect(body == "\"A\" couldn't start: first second third")
        let long = MenuFailure.cannotStart(row: "A", reason: String(repeating: "x", count: 400)).body
        #expect(long.count == 160)
        #expect(long.hasSuffix("…"))
    }
}
