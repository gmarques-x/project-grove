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
}
