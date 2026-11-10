import Foundation
import Testing
@testable import GroveThemesCore

@Suite struct StatusTextTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-11-10 13:10:04 UTC
    let switchedAt = Date(timeIntervalSince1970: 1_794_316_204)

    func steps(_ fixture: String) throws -> [Step] {
        try GroveThemesClient.decoder.decode(SwitchResult.self, from: Fixture.data(fixture)).steps
    }

    func entry(_ steps: [Step], scheme: String = "dark-medium", exit: Int = 0) -> LogEntry {
        LogEntry(time: switchedAt, scheme: scheme, exit: exit, steps: steps)
    }

    @Test func sameDay() throws {
        let line = StatusText.line(for: entry(try steps("set.json")),
                                   now: switchedAt.addingTimeInterval(3600), calendar: calendar)
        #expect(line == "Switched to Dark Medium at 13:10 · 10 updated now, yazi next launch")
    }

    @Test func appearanceNeedsYou() throws {
        let changed = try steps("set.json").map {
            $0.name == "appearance" ? Step(name: "appearance", result: .needsYou, message: "allow it") : $0
        }
        let line = StatusText.line(for: entry(changed), now: switchedAt, calendar: calendar)
        #expect(line == "Switched to Dark Medium at 13:10 · 9 updated now, yazi next launch · appearance needs you")
        #expect(line.hasSuffix(" · appearance needs you"))
    }

    @Test func needsYouFixtureAndFailure() throws {
        var mixed = try steps("set-needs-you.json")
        mixed[mixed.firstIndex { $0.name == "accent" }!] = Step(name: "accent", result: .failed, message: "defaults said no")
        let line = StatusText.line(for: entry(mixed, scheme: "light-soft", exit: 1), now: switchedAt, calendar: calendar)
        #expect(line == "Switched to Light Soft at 13:10 · 7 updated now, yazi next launch · appearance needs you, accent failed, wallpaper needs you")
    }

    @Test func dayBefore() throws {
        let line = StatusText.line(for: entry(try steps("set.json")),
                                   now: switchedAt.addingTimeInterval(86_400), calendar: calendar)
        #expect(line == "Switched to Dark Medium on 10 Nov at 13:10 · 10 updated now, yazi next launch")
        let earlier = LogEntry(time: switchedAt.addingTimeInterval(-86_400), scheme: "dark-medium", exit: 0,
                               steps: try steps("set.json"))
        #expect(StatusText.line(for: earlier, now: switchedAt, calendar: calendar)
            .hasPrefix("Switched to Dark Medium on 9 Nov at 13:10 · "))
    }

    @Test func chips() throws {
        let changed = try steps("set.json").map {
            $0.name == "appearance" ? Step(name: "appearance", result: .needsYou, message: "allow it") : $0
        }
        let chips = StatusText.chips(for: entry(changed))
        #expect(chips.map(\.text) == ["9 now", "yazi next launch", "needs you: appearance"])
        #expect(chips.map(\.kind) == [.live, .nextLaunch, .needsYou])
        #expect(chips[1].message == "read at launch")
        #expect(chips[2].message == "allow it")

        let clean = StatusText.chips(for: entry(try steps("set.json")))
        #expect(clean.map(\.text) == ["10 now", "yazi next launch"])
        #expect(clean[0].kind == .live)
    }

    @Test func failedChip() {
        let chips = StatusText.chips(for: entry([Step(name: "configs", result: .failed, message: "render broke")]))
        #expect(chips == [Chip(text: "failed: configs", kind: .failed, message: "render broke")])
    }
}

@Suite struct HexTests {
    @Test func parses() throws {
        let rgb = try #require(Hex.rgb("#2D353B"))
        #expect(rgb.red == 45.0 / 255)
        #expect(rgb.green == 53.0 / 255)
        #expect(rgb.blue == 59.0 / 255)
        #expect(Hex.rgb("#a7c080")?.green == 192.0 / 255)
    }

    @Test func rejects() {
        #expect(Hex.rgb("2D353B") == nil)
        #expect(Hex.rgb("#XYZ") == nil)
        #expect(Hex.rgb("") == nil)
        #expect(Hex.rgb("#2D353") == nil)
        #expect(Hex.rgb("#2D353G") == nil)
    }
}

@Suite struct StatePathTests {
    let home = URL(fileURLWithPath: "/Users/someone")

    @Test func fromGroveState() {
        #expect(StatePath.url(environment: ["GROVE_STATE": "/tmp/s"], home: home).path == "/tmp/s/theme")
    }

    @Test func defaultPath() {
        #expect(StatePath.url(environment: [:], home: home).path == "/Users/someone/.local/state/grove/theme")
        #expect(StatePath.url(environment: ["GROVE_STATE": ""], home: home).path
            == "/Users/someone/.local/state/grove/theme")
    }
}
