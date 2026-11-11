import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct MonitorsFileTests {
    @Test func readsAssignmentsInFileOrder() throws {
        let f = try MonitorsFile(text: "[monitors]\n2 = \"secondary\"\n1 = 'main'\n\"9\" = \"LG UltraFine\"\n")
        #expect(f.assignments.map(\.workspace) == ["2", "1", "9"])
        #expect(f.assignments.map(\.target) == ["secondary", "main", "LG UltraFine"])
    }

    @Test func anEmptyFileOrNoTableIsNoAssignments() throws {
        #expect(try MonitorsFile(text: "").assignments.isEmpty)
        #expect(try MonitorsFile(text: "# nothing yet\n").assignments.isEmpty)
        #expect(try MonitorsFile(text: "[monitors]\n").assignments.isEmpty)
        #expect(MonitorsFile().assignments.isEmpty)
    }

    /// What the app writes on the first change in the Monitors panel.
    @Test func theFirstChangeWritesTheHeaderAndTheTable() throws {
        var f = MonitorsFile()
        f.set(workspace: "1", target: "main")
        let text = f.document.serialized()
        #expect(text.hasPrefix("# Grove Keys: "))
        #expect(text.hasSuffix("""

            [monitors] # workspace → "main" | "secondary" | "built-in" | a display name
            "1" = "main"

            """))
        #expect(try MonitorsFile(text: text) == f)
        let out = AeroSpaceRenderer.render(keys: try KeysFile(text: ""), base: "", monitors: f.assignments)
        #expect(out.contains("[workspace-to-monitor-force-assignment]\n\"1\" = \"main\""))
    }

    @Test func setReplacesWhereItStandsAndKeepsComments() throws {
        var f = try MonitorsFile(text: "# mine\n\n[monitors] # hint\n# the big one\n1 = \"main\" # desk\n2 = \"secondary\"\n")
        f.set(workspace: "1", target: "built-in")
        f.set(workspace: "3", target: "main")
        #expect(f.document.serialized() == """
            # mine

            [monitors] # hint
            # the big one
            "1" = "built-in" # desk
            "2" = "secondary"
            "3" = "main"

            """)
    }

    @Test func setCreatesTheTableInAHandMadeFile() throws {
        var f = try MonitorsFile(text: "# just a comment\n")
        f.set(workspace: "4", target: "secondary")
        #expect(f.assignments.map(\.workspace) == ["4"])
        #expect(try MonitorsFile(text: f.document.serialized()).assignments.map(\.target) == ["secondary"])
    }

    @Test func validationErrorsCarryTheLine() {
        func error(_ text: String) -> TomlError? {
            do { _ = try MonitorsFile(text: text); return nil } catch { return error }
        }
        #expect(error("[monitors]\n1 = \"main\"\n2 = 3\n")
            == TomlError(line: 3, message: "workspace 2 must be assigned a monitor in quotes"))
        #expect(error("[monitors]\n1 = [\"main\"]\n")?.line == 2)
        #expect(error("[monitors]\n1 = \"main\n")?.line == 2)  // a parse error
        // Other tables are not this file's business.
        #expect(error("[other]\n1 = 3\n") == nil)
    }

    @Test func readFromDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("monitors.toml")
        // Not there: no assignments, and nothing is created by reading.
        #expect(try MonitorsFile.read(from: url) == MonitorsFile())
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try "[monitors]\n1 = \"secondary\"\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(try MonitorsFile.read(from: url).assignments.map(\.target) == ["secondary"])
        // There but not UTF-8: a line-0 error, never "no assignments".
        try Data([0x5b, 0xff, 0xfe, 0x5d, 0x0a]).write(to: url)
        #expect(throws: TomlError(line: 0, message: "monitors.toml can't be read")) { try MonitorsFile.read(from: url) }
    }
}
