import Testing
@testable import GroveKeysCore

@Suite struct LauncherChordTests {
    static let space = LauncherChord.space
    /// ⌘ as a keyboard sends it: the flag and the left key's device bit.
    static let cmd = RightOption.command | 0x8
    static let rightCmd = RightOption.command | 0x10

    func down(_ code: UInt16 = space, isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(kind: .down, keyCode: code, time: 0, isRepeat: isRepeat)
    }
    func up(_ code: UInt16 = space) -> KeyEvent { KeyEvent(kind: .up, keyCode: code, time: 0) }

    @Test func cmdSpaceTogglesAndIsSwallowedWhole() {
        var chord = LauncherChord()
        #expect(chord.handle(down(), flags: Self.cmd, key: .cmdSpace, disposition: .pass) == .toggle)
        #expect(chord.handle(down(isRepeat: true), flags: Self.cmd, key: .cmdSpace, disposition: .pass) == .swallow)
        #expect(chord.handle(up(), flags: Self.cmd, key: .cmdSpace, disposition: .pass) == .swallow)
        // The next press toggles again; either ⌘ key.
        #expect(chord.handle(down(), flags: Self.rightCmd, key: .cmdSpace, disposition: .pass) == .toggle)
    }

    @Test func commandLetGoFirstStillSwallowsTheRest() {
        var chord = LauncherChord()
        _ = chord.handle(down(), flags: Self.cmd, key: .cmdSpace, disposition: .pass)
        #expect(chord.handle(down(isRepeat: true), flags: 0, key: .cmdSpace, disposition: .pass) == .swallow)
        #expect(chord.handle(up(), flags: 0, key: .cmdSpace, disposition: .pass) == .swallow)
        // And then Space is Space again.
        #expect(chord.handle(down(), flags: 0, key: .cmdSpace, disposition: .pass) == .pass)
        #expect(chord.handle(up(), flags: 0, key: .cmdSpace, disposition: .pass) == .pass)
    }

    @Test func onlyExactlyCommand() {
        var chord = LauncherChord()
        let others = [0, RightOption.shift, Self.cmd | RightOption.shift, Self.cmd | RightOption.option,
                      Self.cmd | RightOption.control, RightOption.control,
                      RightOption.option | RightOption.rightOption]
        for flags in others {
            #expect(chord.handle(down(), flags: flags, key: .cmdSpace, disposition: .pass) == .pass)
            #expect(chord.handle(up(), flags: flags, key: .cmdSpace, disposition: .pass) == .pass)
        }
        // Another key with ⌘.
        #expect(chord.handle(down(0), flags: Self.cmd, key: .cmdSpace, disposition: .pass) == .pass)
    }

    @Test func hyperSpaceIsNotTheLauncher() {
        // Caps Lock held + Space: the machine adds ⌃⌥⇧⌘ itself, and says so.
        var machine = HyperMachine(settings: HyperSettings(), launchKeys: [])
        _ = machine.handle(KeyEvent(kind: .down, keyCode: HyperMachine.f18, time: 0))
        let held = machine.handle(down()).0
        #expect(held == .passWithHyper)
        var chord = LauncherChord()
        #expect(chord.handle(down(), flags: Self.cmd, key: .cmdSpace, disposition: held) == .pass)
        #expect(chord.handle(down(), flags: Self.cmd, key: .cmdSpace, disposition: .swallow) == .pass)
    }

    @Test func noneTurnsItOff() {
        var chord = LauncherChord()
        #expect(chord.handle(down(), flags: Self.cmd, key: .none, disposition: .pass) == .pass)
        #expect(chord.handle(up(), flags: Self.cmd, key: .none, disposition: .pass) == .pass)
    }

    @Test func aRepeatFromBeforeAResetIsKeptFromSpotlightButTogglesNothing() {
        var chord = LauncherChord()
        _ = chord.handle(down(), flags: Self.cmd, key: .cmdSpace, disposition: .pass)
        chord.reset()
        #expect(chord.handle(down(isRepeat: true), flags: Self.cmd, key: .cmdSpace, disposition: .pass) == .swallow)
        #expect(chord.handle(up(), flags: Self.cmd, key: .cmdSpace, disposition: .pass) == .pass)
    }

    /// ⌘Space is not a right-Option key, and right ⌥ + Space is not the launcher.
    @Test func itLivesBesideTheRightOption() {
        #expect(!RightOption.types(mode: .characters, flags: Self.cmd, disposition: .pass))
        var chord = LauncherChord()
        let rightOption = RightOption.option | RightOption.rightOption
        #expect(chord.handle(down(), flags: rightOption, key: .cmdSpace, disposition: .pass) == .pass)
        #expect(RightOption.types(mode: .characters, flags: rightOption, disposition: .pass))
    }
}
