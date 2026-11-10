import Testing
@testable import GroveKeysCore

@Suite struct HyperMachineTests {
    static let f18 = HyperMachine.f18
    static let one: UInt16 = 18
    static let t: UInt16 = 17
    static let a: UInt16 = 0

    func down(_ k: UInt16, _ t: Double) -> KeyEvent { KeyEvent(kind: .down, keyCode: k, time: t) }
    func up(_ k: UInt16, _ t: Double) -> KeyEvent { KeyEvent(kind: .up, keyCode: k, time: t) }
    func machine(_ edit: (inout HyperSettings) -> Void = { _ in }, launch: Set<String> = []) -> HyperMachine {
        var s = HyperSettings()
        edit(&s)
        return HyperMachine(settings: s, launchKeys: launch)
    }

    @Test func tapSendsEscape() {
        var m = machine()
        #expect(m.handle(down(Self.f18, 0)).0 == .swallow)
        let (d, e) = m.handle(up(Self.f18, 0.1))
        #expect(d == .swallow)
        #expect(e == [.postEscape])
    }

    @Test func slowTapSendsNothing() {
        var m = machine()
        _ = m.handle(down(Self.f18, 0))
        let (d, e) = m.handle(up(Self.f18, 0.25))
        #expect(d == .swallow)
        #expect(e == [])
    }

    @Test func tapNoneSendsNothing() {
        var m = machine { $0.tap = .none }
        _ = m.handle(down(Self.f18, 0))
        #expect(m.handle(up(Self.f18, 0.1)).1 == [])
    }

    @Test func holdAddsHyper() {
        var m = machine()
        _ = m.handle(down(Self.f18, 0))
        #expect(m.handle(down(Self.one, 0.05)).0 == .passWithHyper)
        #expect(m.handle(up(Self.one, 0.08)).0 == .passWithHyper)
        #expect(m.handle(up(Self.f18, 0.1)).1 == [])
    }

    @Test func keyUpAfterReleaseStillHyper() {
        var m = machine()
        _ = m.handle(down(Self.f18, 0))
        _ = m.handle(down(Self.one, 0.05))
        _ = m.handle(up(Self.f18, 0.08))
        #expect(m.handle(up(Self.one, 0.1)).0 == .passWithHyper)
        #expect(m.handle(down(Self.one, 0.2)).0 == .pass)
    }

    @Test func cheatSheetShowsAndHides() {
        var m = machine()
        _ = m.handle(down(Self.f18, 0))
        #expect(m.tick(now: 0.5) == [.showCheatSheet])
        #expect(m.tick(now: 0.6) == [])
        #expect(m.handle(up(Self.f18, 0.9)).1 == [.hideCheatSheet])

        var off = machine { $0.cheatsheetMs = 0 }
        _ = off.handle(down(Self.f18, 0))
        #expect(off.tick(now: 5) == [])
    }

    @Test func releaseAfterSheetNeverEscapes() {
        var m = machine { $0.tapMs = 2000 }
        _ = m.handle(down(Self.f18, 0))
        _ = m.tick(now: 0.5)
        #expect(m.handle(up(Self.f18, 0.6)).1 == [.hideCheatSheet])
    }

    @Test func keyAfterCheatSheetHidesIt() {
        var m = machine()
        _ = m.handle(down(Self.f18, 0))
        _ = m.tick(now: 0.5)
        let (d, e) = m.handle(down(Self.t, 0.6))
        #expect(d == .passWithHyper)
        #expect(e == [.hideCheatSheet])
        #expect(m.handle(up(Self.f18, 0.7)).1 == [])
    }

    @Test func launcherSwallows() {
        var m = machine(launch: ["t"])
        _ = m.handle(down(Self.f18, 0))
        let (d, e) = m.handle(down(Self.t, 0.1))
        #expect(d == .swallow)
        #expect(e == [.launch(key: "t")])
        _ = m.handle(up(Self.f18, 0.15))
        #expect(m.handle(up(Self.t, 0.2)).0 == .swallow)
    }

    @Test func resetMidHold() {
        var m = machine()
        _ = m.handle(down(Self.f18, 0))
        _ = m.tick(now: 0.5)
        #expect(m.reset() == [.hideCheatSheet])
        _ = m.handle(down(Self.f18, 1.0))
        #expect(m.handle(up(Self.f18, 1.1)).1 == [.postEscape])
    }

    @Test func disabledPassesEverything() {
        var m = machine { $0.enabled = false }
        for e in [down(Self.f18, 0), down(Self.one, 0.1), up(Self.one, 0.2), up(Self.f18, 0.3)] {
            let (d, fx) = m.handle(e)
            #expect(d == .pass)
            #expect(fx == [])
        }
    }

    @Test func otherKeysPassWhenNotHeld() {
        var m = machine()
        #expect(m.handle(down(Self.a, 0)).0 == .pass)
    }
}
