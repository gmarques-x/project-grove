import Testing
@testable import GroveKeysCore

@Suite struct TomlParseTests {
    @Test func parsesHeadersKeysAndValues() throws {
        let text = """
        [hyper]
        tap = "escape"
        tap_ms = 200
        enabled = true
        [aerospace.main]
        alt-1 = 'workspace 1'
        esc = ["reload-config", "mode main"]
        [monitors."Test-Mac"]
        "1" = "secondary"
        """
        let doc = try TomlDocument.parse(text)
        #expect(doc.sections.map(\.path) == [["hyper"], ["aerospace", "main"], ["monitors", "Test-Mac"]])
        let hyper = try #require(doc.section(["hyper"]))
        #expect(hyper.entries.map(\.value) == [.string("escape"), .int(200), .bool(true)])
        let main = try #require(doc.section(["aerospace", "main"]))
        #expect(main.entries[0].key == "alt-1")
        #expect(main.entries[0].value == .string("workspace 1"))
        #expect(main.entries[1].value == .array(["reload-config", "mode main"]))
        let mon = try #require(doc.section(["monitors", "Test-Mac"]))
        #expect(mon.entries[0].key == "1")
        #expect(mon.entries[0].value == .string("secondary"))
        #expect(doc.section(["nope"]) == nil)
    }

    @Test func keepsComments() throws {
        let text = """
        # c1
        [hyper]
        # c2
        tap = "escape" # c3
        tap_ms = 200
        # last one
        """
        let doc = try TomlDocument.parse(text)
        let hyper = try #require(doc.section(["hyper"]))
        #expect(hyper.leadingComments == ["# c1"])
        #expect(hyper.entries[0].leadingComments == ["# c2"])
        #expect(hyper.entries[0].trailingComment == "# c3")
        #expect(hyper.entries[1].leadingComments == [])
        #expect(hyper.entries[1].trailingComment == nil)
        #expect(doc.trailingComments == ["# last one"])
    }

    @Test func fileHeaderCommentBeforeBlankLineBelongsToTopLevel() throws {
        let doc = try TomlDocument.parse("# Grove Keys.\n\n[hyper]\ntap_ms = 1\n")
        #expect(doc.sections[0].path == [])
        #expect(doc.sections[0].leadingComments == ["# Grove Keys."])
        #expect(doc.sections[1].leadingComments == [])
    }

    @Test func keepsHeaderTrailingCommentAndMultiLineArrays() throws {
        let text = "[launch]  # Hyper + key\nx = [\n  \"a\", # first\n  \"b\",\n] # end\n"
        let doc = try TomlDocument.parse(text)
        let s = try #require(doc.section(["launch"]))
        #expect(s.trailingComment == "# Hyper + key")
        #expect(s.entries[0].value == .array(["a", "b"]))
        #expect(s.entries[0].trailingComment == "# end")
    }

    @Test func escapesInStrings() throws {
        let doc = try TomlDocument.parse(#"""
        [x]
        a = "a \"b\" \\ c"
        b = "has # inside" # real
        """#)
        let x = try #require(doc.section(["x"]))
        #expect(x.entries[0].value == .string(#"a "b" \ c"#))
        #expect(x.entries[1].value == .string("has # inside"))
        #expect(x.entries[1].trailingComment == "# real")
    }

    @Test(arguments: [
        ("[hyper]\ntap = 1\ntap = 2\n", 3, #"duplicate key "tap""#),
        ("[hyper]\n[a]\n[hyper]\n", 3, "duplicate table [hyper]"),
        ("[a]\na.b = 1\n", 2, "dotted keys are not supported"),
        ("[a]\nx = { a = 1 }\n", 2, "inline tables are not supported"),
        ("[a]\nx = \"open\n", 2, "unterminated string"),
        ("[a]\nx = [1, 2]\n", 2, "arrays must hold strings"),
        ("[a]\nx 1\n", 2, "expected ="),
    ])
    func errorsCarryLineNumbers(text: String, line: Int, message: String) {
        do {
            _ = try TomlDocument.parse(text)
            Issue.record("expected an error for \(text.debugDescription)")
        } catch {
            #expect(error.line == line)
            #expect(error.message.contains(message), "got: \(error.message)")
        }
    }
}
