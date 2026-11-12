import Foundation
import Testing
@testable import GroveKeysCore

/// The Mac, faked: what was asked of it, in order, and a `pmset` that the
/// dialog's answer changes.
private final class FakeSystem: KeepAwakeSystem, @unchecked Sendable {
    var log: [String] = []
    var holds = true
    var sleepDisabledNow: Bool? = false
    /// How the next dialogs end; `.done` when none is left.
    var answers: [IgnoreLid.Outcome] = []
    var file: String?

    func hold() -> Bool {
        log.append("hold")
        return holds
    }

    func release() { log.append("release") }

    func writeState(_ contents: String?) {
        log.append("file " + (contents ?? "removed"))
        file = contents
    }

    func sleepDisabled() async -> Bool? { sleepDisabledNow }

    func setSleepDisabled(_ on: Bool) async -> IgnoreLid.Outcome {
        log.append("pmset \(on ? 1 : 0)")
        let answer = answers.isEmpty ? .done : answers.removeFirst()
        if answer == .done { sleepDisabledNow = on }
        return answer
    }
}

@MainActor
@Suite struct BatteryKeepAwakeTests {
    let now = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func onAndOffWithoutAnEnd() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        var seen: [KeepAwakeState] = []
        controller.onChange = { seen.append($0) }
        controller.turnOn(now: now)
        #expect(controller.state.isOn)
        #expect(controller.state.endsAt == nil)
        #expect(controller.state.timeLeft(now: now) == nil)
        #expect(system.log == ["hold", "file on"])
        controller.turnOn(now: now) // already on: nothing held twice
        #expect(system.log.count == 2)
        await controller.turnOff()
        #expect(!controller.state.isOn)
        #expect(system.log == ["hold", "file on", "release", "file removed"])
        #expect(system.file == nil)
        #expect(seen.map(\.isOn) == [true, false])
        await controller.turnOff() // already off
        #expect(system.log.count == 4)
    }

    @Test func aDurationEndsItself() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.choose(.twoHours, now: now)
        #expect(system.log.isEmpty) // a choice while off holds nothing
        controller.turnOn(now: now)
        #expect(controller.state.endsAt == now.addingTimeInterval(7200))
        #expect(system.file == "1794007200")
        #expect(controller.state.timeLeft(now: now.addingTimeInterval(18 * 60)) == "1:42 left")
        #expect(controller.state.timeLeft(now: now.addingTimeInterval(7200 - 20)) == "0:01 left")
        await controller.expire(now: now.addingTimeInterval(7199))
        #expect(controller.state.isOn)
        await controller.expire(now: now.addingTimeInterval(7200))
        #expect(!controller.state.isOn)
        #expect(controller.state.endsAt == nil)
        #expect(controller.state.duration == .twoHours) // the choice is kept
        #expect(system.log.suffix(2) == ["release", "file removed"])
    }

    @Test func choosingWhileOnStartsAgainFromNow() {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        let later = now.addingTimeInterval(600)
        controller.choose(.oneHour, now: later)
        #expect(controller.state.endsAt == later.addingTimeInterval(3600))
        #expect(system.file == "1794004200")
        controller.choose(.untilOff, now: later)
        #expect(controller.state.endsAt == nil)
        #expect(system.file == "on")
    }

    @Test func aRefusedAssertionLeavesItOff() {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        system.holds = false
        controller.turnOn(now: now)
        #expect(!controller.state.isOn)
        #expect(controller.state.note == KeepAwakeController.holdFailed)
        #expect(system.file == nil)
    }

    @Test func ignoreLidNeedsKeepAwake() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        await controller.setIgnoreLid(true, refused: false)
        #expect(!controller.state.lidIgnored)
        #expect(controller.state.note == KeepAwakeController.needsKeepAwake)
        #expect(system.log.isEmpty)
    }

    @Test func ignoreLidIsRefusedOnALowBattery() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: true)
        #expect(!controller.state.lidIgnored)
        #expect(controller.state.note == KeepAwakeController.refusedOnBattery)
        #expect(!system.log.contains("pmset 1"))
    }

    @Test func aLowBatteryAsksIgnoreLidOffOncePerFall() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: false)
        #expect(controller.state.lidIgnored)
        // Above the limit: nothing asked.
        await controller.protect(refused: false)
        #expect(system.log.filter { $0 == "pmset 0" }.isEmpty)
        // Under it: asked off; the dialog is dismissed, so it stays on.
        system.answers = [.cancelled]
        await controller.protect(refused: true)
        #expect(system.log.filter { $0 == "pmset 0" }.count == 1)
        #expect(controller.state.lidIgnored)
        #expect(controller.state.note == KeepAwakeController.refusedOnBattery)
        // Not asked again while still low.
        await controller.protect(refused: true)
        #expect(system.log.filter { $0 == "pmset 0" }.count == 1)
        // Recovered, then low again: asked again, and this time answered.
        await controller.protect(refused: false)
        await controller.protect(refused: true)
        #expect(system.log.filter { $0 == "pmset 0" }.count == 2)
        #expect(!controller.state.lidIgnored)
    }

    @Test func aLowBatteryLeavesAnotherToolsSettingAlone() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        system.sleepDisabledNow = true
        await controller.refreshLid()
        await controller.protect(refused: true)
        #expect(!system.log.contains("pmset 0"))
    }

    @Test func ignoreLidOnAndOff() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        var busy: [Bool] = []
        controller.onChange = { busy.append($0.lidBusy) }
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: false)
        #expect(controller.state.lidIgnored)
        #expect(!controller.state.lidStuck)
        #expect(busy == [false, true, false]) // the dialog's wait is shown
        // Off is allowed whatever the battery says.
        await controller.setIgnoreLid(false, refused: true)
        #expect(!controller.state.lidIgnored)
        #expect(system.log == ["hold", "file on", "pmset 1", "pmset 0"])
    }

    @Test func aDismissedPromptReturnsTheSwitch() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        system.answers = [.cancelled]
        await controller.setIgnoreLid(true, refused: false)
        #expect(!controller.state.lidIgnored)
        #expect(!controller.state.lidBusy)
        #expect(controller.state.note == nil)
    }

    @Test func aFailureIsSaidInOneLine() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        system.answers = [.failed("pmset: not found")]
        await controller.setIgnoreLid(true, refused: false)
        #expect(!controller.state.lidIgnored)
        #expect(controller.state.note == "pmset: not found")
    }

    @Test func keepAwakeOffTurnsIgnoreLidOff() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: false)
        await controller.turnOff()
        #expect(!controller.state.isOn)
        #expect(!controller.state.lidIgnored)
        #expect(!controller.state.lidStuck)
        #expect(system.log == ["hold", "file on", "pmset 1", "release", "file removed", "pmset 0"])
    }

    @Test func theTimerEndingTurnsIgnoreLidOffToo() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.choose(.oneHour, now: now)
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: false)
        await controller.expire(now: now.addingTimeInterval(3601))
        #expect(!controller.state.isOn)
        #expect(system.sleepDisabledNow == false)
    }

    @Test func aCancelledTurnOffIsShownAsStuck() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: false)
        system.answers = [.cancelled]
        await controller.turnOff()
        #expect(!controller.state.isOn)
        #expect(controller.state.lidIgnored)
        #expect(controller.state.lidStuck)
        #expect(controller.state.note == nil)
        // One click: off is allowed without Keep Awake.
        await controller.setIgnoreLid(false, refused: false)
        #expect(!controller.state.lidStuck)
        #expect(system.sleepDisabledNow == false)
    }

    @Test func theNextOpeningReadsTheTruth() async {
        // Left on by a killed app, or by another tool.
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        system.sleepDisabledNow = true
        await controller.refreshLid()
        #expect(controller.state.lidStuck)
        system.sleepDisabledNow = false
        await controller.refreshLid()
        #expect(!controller.state.lidIgnored)
        // pmset unreadable: what was known stays.
        system.sleepDisabledNow = true
        await controller.refreshLid()
        system.sleepDisabledNow = nil
        await controller.refreshLid()
        #expect(controller.state.lidIgnored)
    }

    @Test func turnedOnElsewhereWhileKeepAwakeIsOn() async {
        // Keep Awake's end reads pmset before deciding there is nothing to undo.
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        system.sleepDisabledNow = true
        await controller.turnOff()
        #expect(system.log.last == "pmset 0")
        #expect(!controller.state.lidIgnored)
    }

    @Test func theAppsEndReleasesWithoutAPrompt() async {
        let system = FakeSystem(), controller = KeepAwakeController(system: system)
        controller.turnOn(now: now)
        await controller.setIgnoreLid(true, refused: false)
        controller.releaseNow()
        #expect(!controller.state.isOn)
        #expect(system.log.suffix(2) == ["release", "file removed"])
        #expect(controller.state.lidStuck)
    }

    @Test func stateFile() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(KeepAwakeFile.url(environment: ["GROVE_STATE": "/tmp/state"], home: home).path == "/tmp/state/keep-awake")
        #expect(KeepAwakeFile.url(environment: [:], home: home).path == "/Users/someone/.local/state/grove/keep-awake")
        #expect(KeepAwakeFile.contents(endsAt: nil) == "on")
        #expect(KeepAwakeFile.contents(endsAt: now) == "1794000000")
        #expect(KeepAwakeFile.parse("on\n") == .some(nil))
        #expect(KeepAwakeFile.parse("1794000000\n") == .some(now))
        #expect(KeepAwakeFile.parse("") == nil)
        #expect(KeepAwakeFile.parse("off") == nil)
        #expect(KeepAwakeFile.parse("-5") == nil)
    }

    @Test func durations() {
        #expect(KeepAwakeDuration.allCases.map(\.title) == ["Until turned off", "1 hour", "2 hours", "4 hours"])
        #expect(KeepAwakeDuration.allCases.map(\.seconds) == [nil, 3600, 7200, 14400])
        #expect(KeepAwakeState().duration == .untilOff)
    }
}
