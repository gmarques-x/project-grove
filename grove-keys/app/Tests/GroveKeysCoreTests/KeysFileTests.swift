import Testing
@testable import GroveKeysCore

@Suite struct KeysFileTests {
    @Test func defaultsWhenHyperMissing() throws {
        let f = try KeysFile(text: "[launch]\n")
        #expect(f.hyper == HyperSettings())
        #expect(f.hyper.enabled && f.hyper.tap == .escape && f.hyper.tapMs == 200 && f.hyper.cheatsheetMs == 500)
    }

    @Test func readsShippedFile() throws {
        let f = try KeysFile(text: try fixture("keys.toml"))
        #expect(f.hyper == HyperSettings())
        #expect(f.launch.isEmpty)
        #expect(f.modes.map(\.name) == ["main", "service"])
        #expect(f.modes[1].bindings.first?.key == "esc")
        #expect(f.modes[1].bindings.first?.value == .array(["reload-config", "mode main"]))
        #expect(f.monitors(host: "Test-Mac").isEmpty)
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

    @Test func setMonitorCreatesHostSectionAtEnd() throws {
        var f = try KeysFile(text: try fixture("keys.toml"))
        f.setMonitor(host: "Other-Mac", workspace: "1", target: "secondary")
        #expect(f.document.serialized().hasSuffix("\n[monitors.\"Other-Mac\"]\n\"1\" = \"secondary\"\n"))
        #expect(f.monitors(host: "Other-Mac").map(\.workspace) == ["1"])
        #expect(f.monitors(host: "Other-Mac").map(\.target) == ["secondary"])
        #expect(f.monitors(host: "Elsewhere").isEmpty)
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
        #expect(line("[launch]\nt = 3\n") == 2)
        #expect(line("[aerospace.main]\na = 3\n") == 2)
    }
}
