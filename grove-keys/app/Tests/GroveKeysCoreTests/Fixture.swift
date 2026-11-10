import Foundation

func fixture(_ name: String) throws -> String {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    return try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
}
