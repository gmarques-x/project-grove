import Testing
@testable import GroveKeysCore

@Suite struct BindingRowsTests {
    func main() throws -> [(key: String, value: TomlValue)] {
        let keys = try KeysFile(text: fixture("keys.toml"))
        return keys.modes[0].bindings
    }

    @Test func foldsNineWorkspaces() throws {
        let bindings = try main()
        let unfolded = BindingRows.rows(mode: bindings, folded: false)
        #expect(unfolded.count == 34)
        #expect(unfolded.allSatisfy { $0.count == 1 })
        let folded = BindingRows.rows(mode: bindings, folded: true)
        #expect(folded.count == 18)
        let ws = folded.first { $0.count == 9 }
        #expect(ws?.shortcuts == "⌥ 1 … 9")
        #expect(ws?.action == "workspace 1 … 9")
        #expect(ws?.keys.count == 9)
        #expect(folded.contains { $0.shortcuts == "⌥⇧ 1 … 9" && $0.action == "move-node-to-workspace 1 … 9" })
        #expect(unfolded.first { $0.keys == ["alt-h"] }?.shortcuts == "⌥ H")
    }

    @Test func incompleteRunDoesNotFold() throws {
        let bindings = try main().filter { $0.key != "alt-5" }
        let rows = BindingRows.rows(mode: bindings, folded: true)
        #expect(!rows.contains { $0.shortcuts == "⌥ 1 … 9" })
        #expect(rows.contains { $0.keys == ["alt-1"] })
        #expect(rows.count == 34 - 1 - 9 + 1)
    }

    @Test func arrowsWalkTheRowsAcrossGroupsAndStopAtTheEnds() {
        let ids = ["launch:t", "launch:b", "mode:main:alt-h", "mode:service:r"]
        #expect(BindingRows.step(from: nil, by: 1, in: ids) == "launch:t")
        #expect(BindingRows.step(from: nil, by: -1, in: ids) == "mode:service:r")
        #expect(BindingRows.step(from: "launch:b", by: 1, in: ids) == "mode:main:alt-h")
        #expect(BindingRows.step(from: "mode:main:alt-h", by: -1, in: ids) == "launch:b")
        #expect(BindingRows.step(from: "launch:t", by: -1, in: ids) == "launch:t")
        #expect(BindingRows.step(from: "mode:service:r", by: 1, in: ids) == "mode:service:r")
        #expect(BindingRows.step(from: "gone", by: 1, in: ids) == "launch:t")
        #expect(BindingRows.step(from: "launch:t", by: 1, in: []) == nil)
    }

    @Test func removingARowSelectsTheNextElseThePrevious() {
        let ids = ["a", "b", "c"]
        #expect(BindingRows.neighbor(ofRemoved: "a", in: ids) == "b")
        #expect(BindingRows.neighbor(ofRemoved: "c", in: ids) == "b")
        #expect(BindingRows.neighbor(ofRemoved: "a", in: ["a"]) == nil)
        #expect(BindingRows.neighbor(ofRemoved: "x", in: ids) == nil)
    }
}
