import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct KeysStateTests {
    @Test func writesSnakeCaseJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gk-" + UUID().uuidString)
        let url = KeysState.url(environment: ["GROVE_STATE": dir.path], home: URL(fileURLWithPath: "/nowhere"))
        #expect(url == dir.appendingPathComponent("keys.json"))

        try KeysState(accessibility: true, inputMonitoring: false, mapping: false).write(to: url)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Bool]
        #expect(object == ["accessibility": true, "input_monitoring": false, "mapping": false])
        #expect(try JSONDecoder().decode(KeysState.self, from: Data(contentsOf: url))
            == KeysState(accessibility: true, inputMonitoring: false, mapping: false))
    }

    @Test func defaultsUnderHome() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(KeysState.url(environment: ["GROVE_STATE": ""], home: home).path
            == "/Users/someone/.local/state/grove/keys.json")
        #expect(KeysState.url(environment: [:], home: home).path
            == "/Users/someone/.local/state/grove/keys.json")
    }
}
