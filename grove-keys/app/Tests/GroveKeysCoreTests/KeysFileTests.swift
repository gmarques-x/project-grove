import Testing
@testable import GroveKeysCore
import GroveThemesCore

@Suite struct KeysFileTests {
    @Test func defaultsWhenHyperMissing() throws {
        let f = try KeysFile(text: "[launch]\n")
        #expect(f.hyper == HyperSettings())
        #expect(f.hyper.enabled && f.hyper.tap == .escape && f.hyper.tapMs == 200 && f.hyper.cheatsheetMs == 500)
    }

    /// The shared TOML reader (GroveThemesCore) writes the shipped file back
    /// as it read it. Here and not with the reader's own tests: the file is
    /// this package's fixture.
    @Test func roundTripsShippedFile() throws {
        let text = try fixture("keys.toml")
        #expect(try TomlDocument.parse(text).serialized() == text)
    }

    @Test func readsShippedFile() throws {
        let f = try KeysFile(text: try fixture("keys.toml"))
        #expect(f.hyper == HyperSettings())
        #expect(f.launch.isEmpty)
        #expect(f.modes.map(\.name) == ["main", "service"])
        #expect(f.modes[1].bindings.first?.key == "esc")
        #expect(f.modes[1].bindings.first?.value == .array(["reload-config", "mode main"]))
        #expect(f.document.sections.map(\.path) == [[], ["hyper"], ["launch"], ["aerospace", "main"], ["aerospace", "service"]])
    }

    @Test func modesAreInFileOrderWithMainFirst() throws {
        let f = try KeysFile(text: "[aerospace.service]\na = \"x\"\n[aerospace.extra]\nb = \"y\"\n[aerospace.main]\nc = \"z\"\n")
        #expect(f.modes.map(\.name) == ["main", "service", "extra"])
    }

    @Test func setLaunchWritesUnderLaunch() throws {
        var f = try KeysFile(text: try fixture("keys.toml"))
        f.setLaunch(key: "t", bundleID: "com.mitchellh.ghostty")
        #expect(f.launch.map(\.key) == ["t"])
        #expect(f.launch.map(\.bundleID) == ["com.mitchellh.ghostty"])
        let text = f.document.serialized()
        let launch = try #require(text.range(of: "[launch]"))
        let line = try #require(text.range(of: "t = \"com.mitchellh.ghostty\""))
        let next = try #require(text.range(of: "[aerospace.main]"))
        #expect(launch.upperBound < line.lowerBound && line.upperBound < next.lowerBound)
        f.removeLaunch(key: "t")
        #expect(f.launch.isEmpty)
    }

    @Test func removeBindingRemovesOnlyThatKey() throws {
        var f = try KeysFile(text: "[aerospace.main]\na = \"x\"\nb = \"y\"\n")
        f.removeBinding(mode: "main", key: "a")
        #expect(f.modes[0].bindings.map(\.key) == ["b"])
    }

    @Test func setBindingReplacesOrAppends() throws {
        var f = try KeysFile(text: "[aerospace.main]\na = \"x\"\n")
        f.setBinding(mode: "main", key: "a", value: .string("z"))
        f.setBinding(mode: "main", key: "b", value: .array(["p", "q"]))
        f.setBinding(mode: "fresh", key: "c", value: .string("w"))
        #expect(f.modes.map(\.name) == ["main", "fresh"])
        #expect(f.modes[0].bindings.map(\.key) == ["a", "b"])
        #expect(f.modes[0].bindings[0].value == .string("z"))
    }

    @Test func setHyperKeepsUntouchedEntries() throws {
        var f = try KeysFile(text: "[hyper]\nkey = \"caps_lock\" # only\ntap_ms = 200\n")
        var h = f.hyper
        h.tapMs = 300; h.enabled = false; h.tap = .none
        f.setHyper(h)
        #expect(f.hyper == h)
        #expect(f.document.serialized().contains("key = \"caps_lock\" # only"))
    }

    @Test func rightOptionIsCharactersUnlessTheFileSaysShortcuts() throws {
        #expect(try KeysFile(text: "[hyper]\ntap_ms = 200\n").hyper.rightOption == .characters)
        var f = try KeysFile(text: "[hyper]\nright_option = \"shortcuts\" # both alike\n")
        #expect(f.hyper.rightOption == .shortcuts)
        var h = f.hyper
        h.rightOption = .characters
        f.setHyper(h)
        #expect(f.hyper.rightOption == .characters)
        #expect(f.document.serialized().contains("right_option = \"characters\" # both alike"))
    }

    @Test func theLauncherKeyIsCmdSpaceUnlessTheFileSaysNone() throws {
        #expect(try KeysFile(text: "").hyper.launcher == .cmdSpace)
        var f = try KeysFile(text: "[hyper]\nlauncher = \"none\"\n")
        #expect(f.hyper.launcher == .none)
        var h = f.hyper
        h.launcher = .cmdSpace
        f.setHyper(h)
        #expect(f.document.serialized().contains("launcher = \"cmd-space\""))
        #expect(try KeysFile(text: fixture("keys.toml")).hyper.launcher == .cmdSpace)
    }

    /// Monitors moved to monitors.toml. A `[monitors."<host>"]` table still
    /// in someone's keys.toml is an unknown table: not validated (the `3`),
    /// and written back as it was.
    @Test func aLeftoverMonitorsTableIsKeptAndIgnored() throws {
        let text = "[launch]\nt = \"a.b\"\n\n[monitors.\"Test-Mac\"] # old\n\"1\" = \"secondary\"\n\"2\" = 3\n"
        var f = try KeysFile(text: text)
        #expect(f.document.serialized() == text)
        f.setBinding(mode: "main", key: "a", value: .string("x"))
        #expect(f.document.serialized().hasSuffix("\n[monitors.\"Test-Mac\"] # old\n\"1\" = \"secondary\"\n\"2\" = 3\n"))
    }

    @Test func newSectionsGoInFixedOrder() throws {
        var f = try KeysFile(text: "[aerospace.main]\na = \"x\"\n[monitors.M]\n")
        f.setLaunch(key: "t", bundleID: "b")
        f.setHyper(HyperSettings())
        #expect(f.document.sections.map(\.path) == [["hyper"], ["launch"], ["aerospace", "main"], ["monitors", "M"]])
    }

    @Test func validationErrorsCarryTheLine() {
        #expect(throws: TomlError.self) { try KeysFile(text: "[hyper]\ntap_ms = 1\ntap = \"space\"\n") }
        func line(_ text: String) -> Int? {
            do { _ = try KeysFile(text: text); return nil } catch { return error.line }
        }
        #expect(line("[hyper]\ntap_ms = 1\ntap = \"space\"\n") == 3)
        #expect(line("[hyper]\ncolor = \"red\"\n") == 2)
        #expect(line("\n[hyper]\ntap_ms = -5\n") == 3)
        #expect(line("[hyper]\nkey = \"right_shift\"\n") == 2)
        #expect(line("[hyper]\nright_option = \"letters\"\n") == 2)
        #expect(line("[hyper]\nright_option = true\n") == 2)
        #expect(line("[hyper]\nlauncher = \"alt-space\"\n") == 2)
        #expect(line("[hyper]\nlauncher = 1\n") == 2)
        #expect(line("[launch]\nt = 3\n") == 2)
        #expect(line("[aerospace.main]\na = 3\n") == 2)
    }
}
