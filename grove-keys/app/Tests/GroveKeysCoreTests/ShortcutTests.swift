import Testing
@testable import GroveKeysCore

@Suite struct ShortcutTests {
    @Test func hyper() throws {
        let s = try #require(Shortcut(aerospace: "hyper-t"))
        #expect(s.isHyper)
        #expect(s.modifiers == [.cmd, .ctrl, .alt, .shift])
        #expect(s.aerospace == "hyper-t")
        #expect(s.symbols == "⌃⌥⇧⌘ T")
    }

    @Test func optionShift() throws {
        let s = try #require(Shortcut(aerospace: "alt-shift-semicolon"))
        #expect(s.symbols == "⌥⇧ ;")
        #expect(s.aerospace == "alt-shift-semicolon")
        #expect(!s.isHyper)
        #expect(try #require(Shortcut(aerospace: "alt-shift-1")).symbols == "⌥⇧ 1")
    }

    @Test func spelledOutHyperIsHyper() throws {
        let s = try #require(Shortcut(aerospace: "cmd-ctrl-alt-shift-1"))
        #expect(s.isHyper)
        #expect(s.aerospace == "hyper-1")
    }

    @Test func bareKeysAndOrder() throws {
        #expect(try #require(Shortcut(aerospace: "esc")).symbols == "Esc")
        #expect(try #require(Shortcut(aerospace: "backspace")).symbols == "⌫")
        #expect(try #require(Shortcut(aerospace: "shift-cmd-a")).aerospace == "cmd-shift-a")
    }

    @Test func rejectsNonsense() {
        #expect(Shortcut(aerospace: "") == nil)
        #expect(Shortcut(aerospace: "alt-") == nil)
        #expect(Shortcut(aerospace: "foo-t") == nil)
    }

    @Test func keyNames() {
        #expect(KeyNames.keyCode("a") == 0)
        #expect(KeyNames.keyCode("semicolon") == 41)
        #expect(KeyNames.keyCode("nope") == nil)
        #expect(KeyNames.name(53) == "esc")
        #expect(KeyNames.name(41) == "semicolon")
    }
}
