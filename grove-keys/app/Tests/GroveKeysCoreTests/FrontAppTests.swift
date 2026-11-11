import Testing
@testable import GroveKeysCore

@Suite struct FrontAppTests {
    @Test func keepsTheLastAppThatIsntGroveKeys() {
        var t = FrontAppTracker()
        #expect(t.current == nil)
        t.update(bundleID: "com.mitchellh.ghostty", pid: 10)
        #expect(t.current?.pid == 10)
        t.update(bundleID: "com.projectgrove.keys", pid: 99)
        #expect(t.current?.bundleID == "com.mitchellh.ghostty")
        t.update(bundleID: "com.google.Chrome", pid: 20)
        #expect(t.current?.pid == 20)
    }

    @Test func anAppWithoutABundleIDStillCounts() {
        var t = FrontAppTracker()
        t.update(bundleID: nil, pid: 30)
        #expect(t.current?.pid == 30)
        #expect(t.current?.bundleID == nil)
    }
}
