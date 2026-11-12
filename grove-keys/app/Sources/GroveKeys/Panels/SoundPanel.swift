import AppKit
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// Sound (spec 2026-11-12-bar-panels-design §6): the level, the volume
// slider, Mute, the output devices (a click switches), the input device,
// "Sound Settings…". What is a choice and the level's maths are
// `GroveKeysCore`'s (SoundDevices.swift); CoreAudio is SoundCoreAudio.swift.

/// The Sound panel's state. `start()` at each opening reads the Mac's audio
/// and listens to CoreAudio; `stop()` at each closing removes every
/// listener. `.sample` is fixed data for `--render-panel`.
@MainActor
final class SoundModel: ObservableObject, BarPanelModel {
    @Published private(set) var state: SoundState
    /// The output row ↑ and ↓ have lit; Return picks it.
    @Published private(set) var lit: Int?

    /// Nil in a sample: nothing of the Mac is read or changed.
    private let audio: SoundController<CoreAudioSound>?
    /// Every CoreAudio call while the panel is open happens here, in order.
    private let queue = DispatchQueue(label: "grove.keys.sound", qos: .userInitiated)
    private let watcher: SoundWatcher
    private var open = false
    /// Changes sent and not yet answered: a reading taken before the last
    /// one landed would pull the slider back under the pointer.
    private var pending = 0

    init(_ data: BarPanelData) {
        watcher = SoundWatcher(queue: queue)
        switch data {
        case .live:
            audio = SoundController(CoreAudioSound())
            state = SoundState()
        case .sample:
            audio = nil
            // A second state for the render: GROVE_SOUND_SAMPLE=muted, fixed
            // (no volume control), single (one output), inputs (several),
            // lit (a row lit by ↓).
            let name = ProcessInfo.processInfo.environment["GROVE_SOUND_SAMPLE"] ?? ""
            state = Self.sample(name)
            lit = name == "lit" ? 1 : nil
        }
    }

    func start() {
        guard let audio else { return }
        open = true
        lit = nil
        pending = 0
        let watcher = watcher
        // The first reading before the panel is drawn and measured (a few
        // in-process lookups, well under a millisecond per device); every
        // later one arrives from the queue.
        state = queue.sync {
            watcher.start { [weak self] in
                let state = audio.state()
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.took(state) } }
            }
            return audio.state()
        }
    }

    func stop() {
        open = false
        lit = nil
        let watcher = watcher
        queue.async { watcher.stop() }
    }

    // MARK: What the controls ask

    func setVolume(_ level: Double) {
        guard state.volume != nil else { return }
        state.volume = SoundVolume.clamped(level)
        send { $0.setVolume(level) }
    }

    func setMuted(_ muted: Bool) {
        guard state.canMute, state.muted != muted else { return }
        state.muted = muted
        send { $0.setMuted(muted) }
    }

    /// One sixteenth, as a volume key; the sound comes back if it was muted.
    func step(up: Bool) {
        guard let level = state.volume else { return }
        state.volume = SoundVolume.stepped(level, up: up)
        state.muted = false
        send { $0.step(up: up) }
    }

    func selectOutput(_ device: UInt32) {
        guard device != state.output else { return }
        // The level shown is the old device's: the new one's comes with the reading.
        send { $0.selectOutput(device) }
    }

    func selectInput(_ device: UInt32) {
        guard device != state.input else { return }
        send { $0.selectInput(device) }
    }

    /// ← and → move the level a step, ↑ and ↓ light an output row and Return
    /// picks it, M mutes. Keys arrive here before the control with the focus:
    /// on the slider ← and → are these same steps.
    func key(_ key: BarPanelKey) -> Bool {
        switch key {
        case .left, .right:
            guard state.volume != nil else { return false }
            step(up: key == .right)
        case .up, .down:
            guard !state.outputs.isEmpty else { return false }
            lit = SoundList.moved(from: lit, by: key == .down ? 1 : -1, count: state.outputs.count,
                                  current: state.outputIndex)
        case .enter:
            // Without a lit row, Return is the focused control's.
            guard let lit, state.outputs.indices.contains(lit) else { return false }
            selectOutput(state.outputs[lit].id)
            self.lit = nil
        case .character("m"):
            guard state.canMute else { return false }
            setMuted(!state.muted)
        default:
            return false
        }
        return true
    }

    // MARK: Readings

    /// Does `change` on the queue, then reads the state it left.
    private func send(_ change: @escaping @Sendable (SoundController<CoreAudioSound>) -> Void) {
        guard let audio, open else { return }
        pending += 1
        queue.async { [weak self] in
            change(audio)
            let state = audio.state()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pending = max(self.pending - 1, 0)
                    self.took(state)
                }
            }
        }
    }

    private func took(_ reading: SoundState) {
        guard open, pending == 0 else { return }
        if reading != state { state = reading }
        if let lit, lit >= reading.outputs.count { self.lit = nil }
    }

    // MARK: Sample

    /// The mock-ups' devices and level.
    private static func sample(_ name: String) -> SoundState {
        let speakers = SoundDevice(id: 1, name: "MacBook Air Speakers", kind: .speakers)
        let airPods = SoundDevice(id: 2, name: "AirPods Pro", kind: .airPods)
        let display = SoundDevice(id: 3, name: "LG UltraFine", kind: .display)
        let microphone = SoundDevice(id: 4, name: "MacBook Air Microphone", kind: .other)
        var state = SoundState(outputs: [speakers, airPods, display], inputs: [microphone], output: 1, input: 4,
                               volume: 0.62, muted: false, canMute: true)
        switch name {
        case "muted":
            state.muted = true
        case "fixed":
            state.output = 3
            state.volume = nil
            state.canMute = false
        case "single":
            state.outputs = [speakers]
        case "inputs":
            state.inputs += [SoundDevice(id: 5, name: "AirPods Pro", kind: .airPods),
                             SoundDevice(id: 6, name: "Studio Display Microphone", kind: .display)]
        default:
            break
        }
        return state
    }
}

struct SoundPanel: View {
    static let width: CGFloat = 300
    static let registration = BarPanelRegistration("sound", pill: "pill.volume", width: width,
                                                   model: SoundModel.init) { SoundPanel(model: $0) }
    static let settings = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!

    @ObservedObject var model: SoundModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel
    @Environment(\.panelSurface) private var surface

    var body: some View {
        let state = model.state
        BarPanel(width: Self.width) {
            PanelHeader(Self.icon(state.glyph), accent: state.muted ? theme.dim : theme.green, title: "Sound") {
                if let headline = state.headline { PanelValue(headline) }
            }
            volume(state)
            HStack(alignment: .center) {
                Text("Mute").font(GroveFont.mono(GroveType.label))
                Spacer(minLength: GroveSpace.s8)
                PanelSwitch("Mute", isOn: Binding(get: { model.state.muted }, set: model.setMuted))
                    .disabled(!state.canMute)
            }
            .help("M")
            PanelRule()
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                PanelCaption("Output")
                if state.outputs.isEmpty {
                    Text("No output device").foregroundStyle(theme.quiet)
                } else {
                    PanelRows {
                        ForEach(Array(state.outputs.enumerated()), id: \.element.id) { index, device in
                            output(device, current: device.id == state.output, lit: index == model.lit)
                        }
                    }
                }
            }
            PanelRule()
            input(state)
            PanelRule()
            PanelFooter("Sound Settings…") { panel.open(Self.settings) }
        }
    }

    /// The slider between a quiet and a loud speaker. Muted, it is disabled
    /// and keeps its level; a device without a volume control says so.
    @ViewBuilder private func volume(_ state: SoundState) -> some View {
        HStack(spacing: GroveSpace.s8) {
            GroveIcon(.soundLow, size: GroveType.body).foregroundStyle(theme.quiet)
            // Without a control the device plays at its own, full level.
            PanelSlider("Volume", value: Binding(get: { model.state.volume ?? 1 }, set: model.setVolume))
                .accessibilityValue(state.volume.map(SoundVolume.label) ?? "")
                .disabled(state.volume == nil || state.muted)
            GroveIcon(.soundHigh, size: GroveType.body).foregroundStyle(theme.quiet)
        }
        if state.volume == nil, state.output != nil {
            Text("This device has no volume control")
                .font(GroveFont.mono(GroveType.finePrint)).foregroundStyle(theme.quiet)
        }
    }

    /// An output device: its icon, its name, and the tick on the current one.
    private func output(_ device: SoundDevice, current: Bool, lit: Bool) -> some View {
        PanelRow(action: { model.selectOutput(device.id) }) {
            GroveIcon(Self.icon(device.kind), size: GroveType.label).foregroundStyle(theme.quiet)
                .frame(width: PanelMetrics.iconColumn)
            Text(device.name).font(GroveFont.mono(GroveType.label)).truncationMode(.tail)
            Spacer(minLength: GroveSpace.s8)
            if current { GroveIcon(.current, size: GroveType.label).foregroundStyle(Color(theme.green)) }
        }
        // The row ↑ and ↓ lit, filled as under the pointer. `PanelRow` has no
        // such state yet (should move to GroveUI).
        .background {
            if lit {
                RoundedRectangle(cornerRadius: GroveRadius.control).fill(theme.hoverFill(on: surface))
                    .lightOutline(cornerRadius: GroveRadius.control)
                    .padding(.horizontal, -GroveSpace.s8)
            }
        }
        .accessibilityLabel(device.name)
        .accessibilityValue(current ? "Current output" : "")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    /// The current input; with more than one, the row opens a menu of them.
    @ViewBuilder private func input(_ state: SoundState) -> some View {
        let name = state.inputName ?? "None"
        if state.inputs.count > 1 {
            GroveSelect("Input", options: state.inputs.map { GroveSelectOption($0.id, $0.name) }, selection: state.input,
                        onSelect: model.selectInput) {
                HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
                    Text("Input").foregroundStyle(theme.quiet)
                    Spacer(minLength: GroveSpace.s8)
                    Text(name).truncationMode(.tail)
                    GroveIcon(.menu, size: GroveType.finePrint).foregroundStyle(theme.quiet)
                }
                .font(GroveFont.mono(GroveType.body))
                .foregroundStyle(Color(theme.fg))
                .lineLimit(1)
                .contentShape(Rectangle())
            }
        } else {
            PanelDetail("Input", name)
        }
    }

    private static func icon(_ glyph: SoundGlyph) -> GroveIcon.Name {
        switch glyph {
        case .muted: .muted
        case .silent: .soundLow
        case .medium: .sound
        case .loud: .soundHigh
        }
    }

    /// `GroveIcon.Name` has the mock-ups' three (laptop, AirPods, display);
    /// the others take the nearest until it has headphones, AirPlay and USB.
    private static func icon(_ kind: SoundDeviceKind) -> GroveIcon.Name {
        switch kind {
        case .speakers: .laptop
        case .headphones, .airPods: .airpods
        case .display, .airPlay: .display
        case .usb: .ethernet
        case .bluetooth, .other: .soundLow
        }
    }
}
