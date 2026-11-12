import Foundation
import GroveThemesCore

// Keep Awake and Ignore Lid, the battery panel's two switches (spec
// 2026-11-12-bar-panels-design §6). Everything that touches the Mac is
// behind `KeepAwakeSystem`; the rules are here and tested with a fake.

/// How long Keep Awake stays on.
public enum KeepAwakeDuration: Int, CaseIterable, Sendable {
    case untilOff = 0
    case oneHour = 1
    case twoHours = 2
    case fourHours = 4

    public var title: String {
        switch self {
        case .untilOff: "Until turned off"
        case .oneHour: "1 hour"
        case .twoHours: "2 hours"
        case .fourHours: "4 hours"
        }
    }

    /// nil: no end.
    public var seconds: TimeInterval? { self == .untilOff ? nil : TimeInterval(rawValue) * 3600 }
}

/// `$GROVE_STATE/keep-awake`: what Grove Keys tells the bar while Keep Awake
/// is on. One line: `on`, or the second it ends at (Unix time). No file
/// when it is off.
public enum KeepAwakeFile {
    /// Default `~/.local/state/grove/keep-awake`.
    public static func url(environment: [String: String], home: URL) -> URL {
        StatePath.url(environment: environment, home: home)
            .deletingLastPathComponent().appendingPathComponent("keep-awake")
    }

    public static func contents(endsAt: Date?) -> String {
        endsAt.map { String(Int($0.timeIntervalSince1970.rounded())) } ?? "on"
    }

    /// What a file says: `.some(nil)` on without an end, `.some(date)` on
    /// until then, nil for anything else.
    public static func parse(_ text: String) -> Date?? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if word == "on" { return .some(nil) }
        guard !word.isEmpty, word.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = TimeInterval(word)
        else { return nil }
        return .some(Date(timeIntervalSince1970: seconds))
    }
}

/// `pmset`'s side of Ignore Lid.
public enum IgnoreLid {
    /// The `SleepDisabled` line of `pmset -g`: true while the Mac is told
    /// never to sleep, lid closed included. nil when the line isn't there.
    public static func sleepDisabled(pmset output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2, words[0] == "SleepDisabled" else { continue }
            return words[1] == "1" ? true : words[1] == "0" ? false : nil
        }
        return nil
    }

    public static let osascript = "/usr/bin/osascript"

    /// The change, asked through macOS's own authorization dialog: the owner
    /// answers it, Grove never sees a password.
    public static func arguments(on: Bool) -> [String] {
        ["-e", "do shell script \"/usr/bin/pmset -a disablesleep \(on ? 1 : 0)\" with administrator privileges"]
    }

    /// How the dialog ended.
    public enum Outcome: Equatable, Sendable {
        case done
        /// The owner dismissed the dialog: nothing to report.
        case cancelled
        case failed(String)
    }

    /// From osascript's exit status and what it printed. A dismissed dialog
    /// is "execution error: User canceled. (-128)" with status 1.
    public static func outcome(status: Int32, output: String, timedOut: Bool = false) -> Outcome {
        if timedOut { return .cancelled }
        if status == 0 { return .done }
        if output.contains("(-128)") || output.localizedCaseInsensitiveContains("User canceled") { return .cancelled }
        let line = output.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return .failed(line.isEmpty ? "pmset could not be run (status \(status))" : line)
    }
}

/// What the two switches show.
public struct KeepAwakeState: Equatable, Sendable {
    public var isOn = false
    /// The duration chosen, on or off.
    public var duration = KeepAwakeDuration.untilOff
    /// When it switches itself off; nil while off or without an end.
    public var endsAt: Date?
    /// `pmset`'s `SleepDisabled`, as last read: the truth, never remembered
    /// across openings.
    public var lidIgnored = false
    /// The authorization dialog is up.
    public var lidBusy = false
    /// One line under the switches: why something was refused or failed.
    public var note: String?

    public init() {}

    /// Ignore Lid without Keep Awake: left on by a cancelled prompt, a
    /// killed app or another tool. Shown as a warning with one click to
    /// turn it off.
    public var lidStuck: Bool { lidIgnored && !isOn && !lidBusy }

    /// "1:42 left" while on with an end, to the minute, rounded up (so it
    /// never reads 0:00 while still on).
    public func timeLeft(now: Date) -> String? {
        guard isOn, let endsAt else { return nil }
        let minutes = Int((max(0, endsAt.timeIntervalSince(now)) / 60).rounded(.up))
        return BatteryText.clock(minutes: minutes) + " left"
    }
}

/// The Mac, as Keep Awake needs it.
public protocol KeepAwakeSystem: Sendable {
    /// Takes the two power assertions (the Mac and its display don't sleep
    /// from idleness). False when macOS refused.
    func hold() -> Bool
    /// Gives them back.
    func release()
    /// Writes `$GROVE_STATE/keep-awake`; nil removes it.
    func writeState(_ contents: String?)
    /// `pmset -g`'s `SleepDisabled`; nil when it can't be read.
    func sleepDisabled() async -> Bool?
    /// Asks macOS to change it (the authorization dialog); returns when the
    /// dialog is answered.
    func setSleepDisabled(_ on: Bool) async -> IgnoreLid.Outcome
}

/// Keep Awake and Ignore Lid's rules. One per app; it outlives the panel.
@MainActor
public final class KeepAwakeController {
    public private(set) var state = KeepAwakeState() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    /// Told of every change, on the main actor.
    public var onChange: (@MainActor (KeepAwakeState) -> Void)?

    private let system: any KeepAwakeSystem
    /// `protect` has asked since the charge last was above the limit.
    private var askedToProtect = false

    public init(system: any KeepAwakeSystem) {
        self.system = system
    }

    public static let refusedOnBattery = "Not under 20% on battery (battery protection)"
    public static let needsKeepAwake = "Ignore Lid needs Keep Awake on."
    public static let holdFailed = "macOS refused to keep the Mac awake."

    /// Switches Keep Awake on for the chosen duration, counted from `now`.
    public func turnOn(now: Date) {
        guard !state.isOn else { return }
        guard system.hold() else {
            state.note = Self.holdFailed
            return
        }
        var next = state
        next.isOn = true
        next.endsAt = next.duration.seconds.map { now.addingTimeInterval($0) }
        next.note = nil
        state = next
        system.writeState(KeepAwakeFile.contents(endsAt: next.endsAt))
    }

    /// Switches Keep Awake off, and Ignore Lid with it: the Mac must not be
    /// left unable to sleep (the authorization dialog again).
    public func turnOff() async {
        guard state.isOn else { return }
        releaseNow()
        if let real = await system.sleepDisabled() { state.lidIgnored = real }
        if state.lidIgnored { await change(lid: false) }
    }

    /// The duration's choice. While on, the time starts again from `now`.
    public func choose(_ duration: KeepAwakeDuration, now: Date) {
        var next = state
        next.duration = duration
        if next.isOn {
            next.endsAt = duration.seconds.map { now.addingTimeInterval($0) }
            system.writeState(KeepAwakeFile.contents(endsAt: next.endsAt))
        }
        state = next
    }

    /// The duration's timer: off once the end has come.
    public func expire(now: Date) async {
        guard state.isOn, let endsAt = state.endsAt, endsAt <= now else { return }
        await turnOff()
    }

    /// Reads the real `SleepDisabled`; at every opening of the panel.
    public func refreshLid() async {
        guard !state.lidBusy, let real = await system.sleepDisabled() else { return }
        // Nothing asked meanwhile.
        if !state.lidBusy { state.lidIgnored = real }
    }

    /// The Ignore Lid switch. On only while Keep Awake is on, and not under
    /// 20% on battery (`refused`: `BatteryReading.refusesIgnoreLid`); off is
    /// always allowed. Returns once the dialog is answered and the real
    /// state read back.
    public func setIgnoreLid(_ on: Bool, refused: Bool) async {
        guard !state.lidBusy else { return }
        if on {
            guard state.isOn else {
                state.note = Self.needsKeepAwake
                return
            }
            guard !refused else {
                state.note = Self.refusedOnBattery
                return
            }
        }
        await change(lid: on)
    }

    /// Battery protection while Ignore Lid is on: when the charge falls under
    /// 20% on battery (`refused`), Ignore Lid is asked off, once per fall (a
    /// dismissed dialog isn't asked again until the charge has recovered).
    /// macOS only changes it through its authorization dialog, so with the
    /// lid shut the dialog waits unanswered: Grove can ask, not force.
    public func protect(refused: Bool) async {
        guard refused else {
            askedToProtect = false
            return
        }
        guard state.isOn, state.lidIgnored, !state.lidBusy, !askedToProtect else { return }
        askedToProtect = true
        await change(lid: false)
        if state.lidIgnored { state.note = Self.refusedOnBattery }
    }

    /// The assertions and the file go, without a word to anyone else: for
    /// the app's end, where no dialog can be waited for. Ignore Lid, if on,
    /// stays on and the next opening shows it (`lidStuck`).
    public func releaseNow() {
        guard state.isOn else { return }
        system.release()
        system.writeState(nil)
        var next = state
        next.isOn = false
        next.endsAt = nil
        state = next
    }

    private func change(lid on: Bool) async {
        state.lidBusy = true
        state.note = nil
        let outcome = await system.setSleepDisabled(on)
        let real = await system.sleepDisabled()
        var next = state
        next.lidBusy = false
        // The truth when it can be read; else what the dialog's end implies.
        next.lidIgnored = real ?? (outcome == .done ? on : next.lidIgnored)
        // A dismissed dialog is no error: the switch is back where it was.
        if case .failed(let message) = outcome { next.note = message }
        state = next
    }
}
