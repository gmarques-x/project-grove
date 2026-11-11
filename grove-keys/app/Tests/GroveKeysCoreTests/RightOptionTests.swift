import Testing
@testable import GroveKeysCore

@Suite struct RightOptionTests {
    /// Flags as a keyboard sends them: the Option bit and the device's bit for the side.
    static let right = RightOption.option | RightOption.rightOption
    static let left = RightOption.option | RightOption.leftOption
    /// NX_DEVICELSHIFTKEYMASK: other device bits don't matter.
    static let shift = RightOption.shift | 0x2

    func types(_ flags: UInt64, mode: RightOptionMode = .characters, _ disposition: Disposition = .pass) -> Bool {
        RightOption.types(mode: mode, flags: flags, disposition: disposition)
    }

    @Test func theRightOptionAloneOrWithShiftTypes() {
        #expect(types(Self.right))
        #expect(types(Self.right | Self.shift))
        #expect(types(Self.right | 0x100))  // the "non-coalesced" bit every key event has
    }

    @Test func theLeftOptionIsAShortcut() {
        #expect(!types(Self.left))
        #expect(!types(Self.left | Self.shift))
        #expect(!types(Self.left | Self.right))  // both held
    }

    @Test func noOptionOrNoSideIsLeftAlone() {
        #expect(!types(0))
        #expect(!types(Self.shift))
        // Option without a device bit (an event another tool made): not known to be the right key.
        #expect(!types(RightOption.option))
    }

    @Test func commandOrControlMakeItAShortcut() {
        #expect(!types(Self.right | RightOption.command))
        #expect(!types(Self.right | RightOption.control))
    }

    @Test func hyperKeysStayHyper() {
        #expect(!types(Self.right, .passWithHyper))
        #expect(!types(Self.right, .swallow))
        // The machine itself: Hyper held, a key with the right Option.
        var m = HyperMachine(settings: HyperSettings(), launchKeys: [])
        _ = m.handle(KeyEvent(kind: .down, keyCode: HyperMachine.f18, time: 0))
        let held = m.handle(KeyEvent(kind: .down, keyCode: 19, time: 0.1)).0
        #expect(!types(Self.right, held))
    }

    @Test func theSettingTurnsItOff() {
        #expect(!types(Self.right, mode: .shortcuts))
        #expect(HyperSettings().rightOption == .characters)
    }

    @Test func withoutOptionKeepsTheOtherFlags() {
        #expect(RightOption.withoutOption(Self.right | Self.shift | 0x100) == Self.shift | 0x100)
        #expect(RightOption.withoutOption(Self.shift) == Self.shift)
    }

    @Test func textIsWhatCanBeTyped() {
        #expect(RightOption.isText("@"))
        #expect(RightOption.isText("€"))
        #expect(RightOption.isText("\u{F8FF}"))  // ⌥1 on the Portuguese layout
        #expect(RightOption.isText("\u{A0}"))  // ⌥Space
        #expect(RightOption.isText("˜"))
        #expect(!RightOption.isText(""))
        #expect(!RightOption.isText("\t"))
        #expect(!RightOption.isText("\r"))
        #expect(!RightOption.isText("\u{1B}"))
        #expect(!RightOption.isText("\u{7F}"))
        #expect(!RightOption.isText("\u{10}"))  // the F keys
        #expect(!RightOption.isText("\u{1C}"))  // the arrows
        #expect(!RightOption.isText("\u{F702}"))  // AppKit's left arrow
    }
}
