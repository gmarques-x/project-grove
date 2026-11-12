import Foundation
import Testing
@testable import GroveKeysCore

/// A Mac's audio that is only a table: the tests never touch the real one.
final class FakeSound: SoundSystem {
    var list: [SoundDeviceInfo]
    var output: UInt32?
    var input: UInt32?
    var levels: [UInt32: Double]
    var mutes: [UInt32: Bool]
    /// What was asked, in order.
    var log: [String] = []

    init(list: [SoundDeviceInfo], output: UInt32?, input: UInt32?, levels: [UInt32: Double] = [:],
         mutes: [UInt32: Bool] = [:]) {
        self.list = list
        self.output = output
        self.input = input
        self.levels = levels
        self.mutes = mutes
    }

    func devices() -> [SoundDeviceInfo] { list }
    func defaultOutput() -> UInt32? { output }
    func defaultInput() -> UInt32? { input }
    func volume(of device: UInt32) -> Double? { levels[device] }
    func muted(of device: UInt32) -> Bool? { mutes[device] }

    func setVolume(_ level: Double, of device: UInt32) {
        levels[device] = level
        log.append("volume \(device) \(level)")
    }

    func setMuted(_ muted: Bool, of device: UInt32) {
        mutes[device] = muted
        log.append("mute \(device) \(muted)")
    }

    func setDefaultOutput(_ device: UInt32) {
        output = device
        log.append("output \(device)")
    }

    func setDefaultInput(_ device: UInt32) {
        input = device
        log.append("input \(device)")
    }
}

enum SoundFixture {
    static func code(_ text: String) -> UInt32 { SoundTransport.code(text) }

    // As read from this MacBook Air on 2026-11-12 (IDs, names, UIDs, transport
    // "bltn", the speakers' data source "ispk", level 0.0625, not muted).
    static let microphone = SoundDeviceInfo(id: 77, name: "MacBook Air Microphone", uid: "BuiltInMicrophoneDevice",
                                            transport: .builtIn, hasInput: true, canBeDefaultOutput: false)
    static let speakers = SoundDeviceInfo(id: 70, name: "MacBook Air Speakers", uid: "BuiltInSpeakerDevice",
                                          transport: .builtIn, hasOutput: true, canBeDefaultInput: false,
                                          outputSource: code("ispk"))
    // Devices this Mac didn't have attached, as CoreAudio describes their kind.
    static let airPods = SoundDeviceInfo(id: 91, name: "AirPods Pro", uid: "AA-BB-CC-DD-EE-FF:output",
                                         transport: .bluetooth, hasOutput: true)
    static let airPodsMic = SoundDeviceInfo(id: 92, name: "AirPods Pro", uid: "AA-BB-CC-DD-EE-FF:input",
                                            transport: .bluetooth, hasInput: true)
    static let display = SoundDeviceInfo(id: 95, name: "LG UltraFine", uid: "AppleGFXHDAEngineOutputDP:0",
                                         transport: .displayPort, hasOutput: true)
    static let systemAggregate = SoundDeviceInfo(id: 120, name: "CADefaultDeviceAggregate-4312-0",
                                                 uid: "CADefaultDeviceAggregate-4312-0", transport: .aggregate,
                                                 hasOutput: true, hasInput: true)

    static let all = [microphone, speakers, airPods, airPodsMic, display, systemAggregate]

    static func system(output: UInt32? = 70) -> FakeSound {
        FakeSound(list: all, output: output, input: 77, levels: [70: 0.0625, 91: 0.5], mutes: [70: false, 91: false])
    }
}

@Suite struct SoundDevicesTests {
    @Test func transportsAreReadFromTheirCodes() {
        #expect(SoundTransport.code("bltn") == 0x626C_746E)
        let codes: [(String, SoundTransport)] = [
            ("bltn", .builtIn), ("blue", .bluetooth), ("blea", .bluetooth), ("usb ", .usb), ("hdmi", .hdmi),
            ("dprt", .displayPort), ("airp", .airPlay), ("thun", .thunderbolt), ("virt", .virtual),
            ("grup", .aggregate), ("ccwd", .continuity), ("ccwl", .continuity), ("1394", .other),
        ]
        for (code, transport) in codes { #expect(SoundTransport(code: SoundTransport.code(code)) == transport) }
        #expect(SoundTransport(code: 0) == .other)
    }

    @Test func theKindComesFromTheTransportAndTheName() {
        func kind(_ transport: SoundTransport, _ name: String, source: String? = nil) -> SoundDeviceKind {
            SoundDeviceKind(transport: transport, name: name, outputSource: source.map(SoundTransport.code))
        }
        #expect(kind(.builtIn, "MacBook Air Speakers", source: "ispk") == .speakers)
        #expect(kind(.builtIn, "Built-in Output", source: "hdpn") == .headphones)       // Intel: one device, two sources
        #expect(kind(.builtIn, "External Headphones") == .headphones)                   // Apple silicon: its own device
        #expect(kind(.bluetooth, "AirPods Pro") == .airPods)
        #expect(kind(.bluetooth, "Ana's AirPods Max") == .airPods)
        #expect(kind(.bluetooth, "WH-1000XM5 Headphones") == .headphones)
        #expect(kind(.bluetooth, "JBL Flip 6") == .bluetooth)
        #expect(kind(.hdmi, "DELL U2720Q") == .display)
        #expect(kind(.displayPort, "LG UltraFine") == .display)
        #expect(kind(.airPlay, "Living Room") == .airPlay)
        #expect(kind(.usb, "Scarlett 2i2 USB") == .usb)
        #expect(kind(.usb, "Studio Display Speakers") == .display)
        #expect(kind(.usb, "Jabra Headset") == .headphones)
        #expect(kind(.thunderbolt, "LG UltraFine Display Audio") == .display)
        #expect(kind(.thunderbolt, "Apollo Twin") == .other)
        #expect(kind(.virtual, "BlackHole 2ch") == .other)
        #expect(kind(.aggregate, "Multi-Output Device") == .other)
    }

    @Test func outputsAndInputsKeepTheSystemsOrder() {
        #expect(SoundList.outputs(SoundFixture.all) == [
            SoundDevice(id: 70, name: "MacBook Air Speakers", kind: .speakers),
            SoundDevice(id: 91, name: "AirPods Pro", kind: .airPods),
            SoundDevice(id: 95, name: "LG UltraFine", kind: .display),
        ])
        #expect(SoundList.inputs(SoundFixture.all).map(\.id) == [77, 92])
        #expect(SoundList.outputs(SoundFixture.all.reversed()).map(\.id) == [95, 91, 70])
    }

    @Test func devicesThatAreNotChoicesAreLeftOut() {
        func listed(_ change: (inout SoundDeviceInfo) -> Void) -> Bool {
            var device = SoundFixture.airPods
            change(&device)
            return !SoundList.outputs([device]).isEmpty
        }
        #expect(listed { _ in })
        #expect(!listed { $0.hasOutput = false })
        #expect(!listed { $0.canBeDefaultOutput = false })
        #expect(!listed { $0.hidden = true })
        #expect(!listed { $0.name = "CADefaultDeviceAggregate-812-1" })
        #expect(!listed { $0.uid = "CADefaultDeviceAggregate-812-1" })
        // What can't be the input is still an output.
        #expect(listed { $0.canBeDefaultInput = false })
        // The user's own aggregate and a virtual device are choices, as in Sound Settings.
        #expect(listed { $0.transport = .aggregate; $0.name = "Multi-Output Device" })
        #expect(listed { $0.transport = .virtual; $0.name = "BlackHole 2ch" })
        #expect(SoundList.inputs([SoundFixture.speakers]).isEmpty)
    }

    @Test func aNamelessDeviceStillHasARow() {
        let device = SoundDeviceInfo(id: 5, name: "  ", transport: .usb, hasOutput: true)
        #expect(SoundList.outputs([device]) == [SoundDevice(id: 5, name: "Audio device", kind: .usb)])
    }

    @Test func arrowsMoveFromTheCurrentRowAndStopAtTheEnds() {
        #expect(SoundList.moved(from: nil, by: 1, count: 3, current: 0) == 1)
        #expect(SoundList.moved(from: nil, by: -1, count: 3, current: 0) == 0)
        #expect(SoundList.moved(from: nil, by: -1, count: 3, current: 2) == 1)
        #expect(SoundList.moved(from: 1, by: 1, count: 3, current: 0) == 2)
        #expect(SoundList.moved(from: 2, by: 1, count: 3, current: 0) == 2)
        #expect(SoundList.moved(from: 0, by: -1, count: 3, current: 2) == 0)
        // No current row (the output is not a listed device): from the nearer end.
        #expect(SoundList.moved(from: nil, by: 1, count: 3, current: nil) == 0)
        #expect(SoundList.moved(from: nil, by: -1, count: 3, current: nil) == 2)
        #expect(SoundList.moved(from: nil, by: 1, count: 1, current: 0) == 0)
        #expect(SoundList.moved(from: nil, by: 1, count: 0, current: nil) == nil)
        // A row lit before a device went away.
        #expect(SoundList.moved(from: 5, by: 1, count: 2, current: 0) == 1)
    }
}

@Suite struct SoundVolumeTests {
    @Test func percentagesRoundAndStayInRange() {
        #expect(SoundVolume.percent(0.62) == 62)
        #expect(SoundVolume.percent(0.0625) == 6)
        #expect(SoundVolume.percent(0.625) == 63)
        #expect(SoundVolume.percent(0.004) == 0)
        #expect(SoundVolume.percent(1) == 100)
        #expect(SoundVolume.percent(1.2) == 100)
        #expect(SoundVolume.percent(-0.1) == 0)
        #expect(SoundVolume.percent(.nan) == 0)
        #expect(SoundVolume.label(0.62) == "62%")
        #expect(SoundVolume.label(1) == "100%")
    }

    @Test func aStepIsASixteenth() {
        #expect(SoundVolume.stepped(0.5, up: true) == 0.5625)
        #expect(SoundVolume.stepped(0.5, up: false) == 0.4375)
        #expect(SoundVolume.stepped(0, up: false) == 0)
        #expect(SoundVolume.stepped(1, up: true) == 1)
        #expect(SoundVolume.stepped(0.0625, up: false) == 0)
        #expect(SoundVolume.stepped(0.9375, up: true) == 1)
    }

    @Test func aLevelBetweenStepsLandsOnTheNextOne() {
        // 0.62 is between 9/16 (0.5625) and 10/16 (0.625).
        #expect(SoundVolume.stepped(0.62, up: true) == 0.625)
        #expect(SoundVolume.stepped(0.62, up: false) == 0.5625)
        #expect(SoundVolume.stepped(0.01, up: false) == 0)
        #expect(SoundVolume.stepped(0.99, up: true) == 1)
    }

    @Test func floatNoiseOnAStepIsStillThatStep() {
        // CoreAudio's level is a Float32: 0.3125 may come back a hair off.
        #expect(SoundVolume.stepped(Double(Float32(0.3125)) + 1e-7, up: true) == 0.375)
        #expect(SoundVolume.stepped(Double(Float32(0.3125)) - 1e-7, up: true) == 0.375)
        #expect(SoundVolume.stepped(Double(Float32(0.3125)) + 1e-7, up: false) == 0.25)
    }

    @Test func sixteenStepsCrossTheRange() {
        var level = 0.0
        for _ in 0..<SoundVolume.steps { level = SoundVolume.stepped(level, up: true) }
        #expect(level == 1)
        for _ in 0..<SoundVolume.steps { level = SoundVolume.stepped(level, up: false) }
        #expect(level == 0)
    }

    @Test func theBarsTenthsAreTheBarsOwn() {
        // sb_vol_level in grove-dotfiles/config/sketchybar/lib.sh.
        let expected = [0: 0, 1: 1, 9: 1, 10: 1, 14: 1, 15: 2, 44: 4, 45: 5, 62: 6, 65: 7, 94: 9, 95: 10, 99: 10,
                        100: 10, 140: 10, -3: 0]
        for (percent, level) in expected { #expect(SoundVolume.barLevel(percent: percent) == level) }
    }

    @Test func theHeadersSpeakerFollowsTheLevelAndMute() {
        #expect(SoundVolume.glyph(level: 0.62, muted: false) == .medium)
        #expect(SoundVolume.glyph(level: 0.62, muted: true) == .muted)
        #expect(SoundVolume.glyph(level: 0, muted: false) == .silent)
        #expect(SoundVolume.glyph(level: 0.01, muted: false) == .medium)
        #expect(SoundVolume.glyph(level: 0.64, muted: false) == .medium)
        #expect(SoundVolume.glyph(level: 0.65, muted: false) == .loud)
        #expect(SoundVolume.glyph(level: 1, muted: false) == .loud)
        #expect(SoundVolume.glyph(level: nil, muted: false) == .medium)
        #expect(SoundVolume.glyph(level: nil, muted: true) == .muted)
    }
}

@Suite struct SoundControllerTests {
    @Test func theStateIsReadFromTheSystem() {
        let state = SoundController(SoundFixture.system()).state()
        #expect(state.outputs.map(\.name) == ["MacBook Air Speakers", "AirPods Pro", "LG UltraFine"])
        #expect(state.inputs.map(\.id) == [77, 92])
        #expect(state.output == 70)
        #expect(state.outputIndex == 0)
        #expect(state.inputName == "MacBook Air Microphone")
        #expect(state.volume == 0.0625)
        #expect(!state.muted)
        #expect(state.canMute)
        #expect(state.headline == "6%")
        #expect(state.glyph == .medium)
    }

    @Test func mutedSaysMuted() {
        let system = SoundFixture.system()
        system.mutes[70] = true
        let state = SoundController(system).state()
        #expect(state.muted)
        #expect(state.headline == "Muted")
        #expect(state.glyph == .muted)
        #expect(state.volume == 0.0625)      // the level is kept
    }

    @Test func aDeviceWithoutVolumeControlHasNoLevel() {
        let system = SoundFixture.system(output: 95)
        let controller = SoundController(system)
        let state = controller.state()
        #expect(state.volume == nil)
        #expect(!state.canMute)
        #expect(state.headline == nil)
        #expect(state.outputIndex == 2)
        controller.setVolume(0.5)
        controller.step(up: true)
        controller.toggleMute()
        controller.setMuted(true)
        #expect(system.log.isEmpty)
    }

    @Test func noOutputAtAll() {
        let system = FakeSound(list: [SoundFixture.microphone], output: nil, input: 77)
        let controller = SoundController(system)
        #expect(controller.state() == SoundState(inputs: [SoundDevice(id: 77, name: "MacBook Air Microphone", kind: .speakers)],
                                                 input: 77))
        controller.setVolume(0.5)
        controller.step(up: false)
        controller.toggleMute()
        #expect(system.log.isEmpty)
    }

    @Test func theSliderSetsTheLevelOfTheCurrentOutput() {
        let system = SoundFixture.system()
        let controller = SoundController(system)
        controller.setVolume(0.4)
        controller.setVolume(1.7)
        controller.setVolume(-1)
        #expect(system.log == ["volume 70 0.4", "volume 70 1.0", "volume 70 0.0"])
        #expect(system.levels[91] == 0.5)
    }

    @Test func aStepMovesASixteenthAndBringsTheSoundBack() {
        let system = SoundFixture.system()
        let controller = SoundController(system)
        controller.step(up: true)
        #expect(system.log == ["volume 70 0.125"])
        system.mutes[70] = true
        controller.step(up: false)
        #expect(system.log == ["volume 70 0.125", "volume 70 0.0625", "mute 70 false"])
    }

    @Test func muteIsSetOnlyWhenItChanges() {
        let system = SoundFixture.system()
        let controller = SoundController(system)
        controller.setMuted(false)
        #expect(system.log.isEmpty)
        controller.setMuted(true)
        controller.toggleMute()
        controller.toggleMute()
        #expect(system.log == ["mute 70 true", "mute 70 false", "mute 70 true"])
    }

    @Test func aClickSwitchesToAListedDeviceOnly() {
        let system = SoundFixture.system()
        let controller = SoundController(system)
        controller.selectOutput(70)       // already the output
        controller.selectOutput(120)      // the system's aggregate
        controller.selectOutput(77)       // an input
        controller.selectOutput(999)      // gone
        #expect(system.log.isEmpty)
        controller.selectOutput(91)
        #expect(system.log == ["output 91"])
        #expect(controller.state().volume == 0.5)
        controller.selectInput(77)
        controller.selectInput(70)
        controller.selectInput(92)
        #expect(system.log == ["output 91", "input 92"])
        #expect(controller.state().inputName == "AirPods Pro")
    }
}
