import Testing
@testable import GroveKeysCore

@Suite struct TomlWriteTests {
    @Test func roundTripsShippedFile() throws {
        let text = try fixture("keys.toml")
        #expect(try TomlDocument.parse(text).serialized() == text)
    }

    @Test func editKeepsComments() throws {
        var doc = try TomlDocument.parse("""
        [hyper]
        # how long a tap is
        tap_ms = 200 # milliseconds
        """)
        doc.sections[0].entries[0].value = .int(250)
        #expect(doc.serialized() == """
        [hyper]
        # how long a tap is
        tap_ms = 250 # milliseconds

        """)
    }

    @Test func writesStringsEscapedAndArraysSpaced() {
        let doc = TomlDocument(sections: [
            TomlSection(path: ["a"], entries: [
                TomlEntry(key: "x", value: .string("say \"hi\"\\")),
                TomlEntry(key: "y", value: .array(["a", "b"])),
                TomlEntry(key: "alt-1", value: .bool(true)),
            ]),
            TomlSection(path: ["monitors", "My Mac"]),
        ])
        #expect(doc.serialized() == """
        [a]
        x = "say \\"hi\\"\\\\"
        y = ["a", "b"]
        alt-1 = true

        [monitors."My Mac"]

        """)
    }

    @Test func multiLineArrayErrorNamesItsOwnLine() {
        #expect(throws: TomlError(line: 3, message: "arrays must hold strings")) {
            try TomlDocument.parse("x = [\n\"a\",\n1\n]")
        }
    }
}
