import AppKit
import Combine
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// Bluetooth, under Wi-Fi in its dropdown (spec 2026-11-13-bar-wifi-bluetooth-design):
// a header with the on/off switch, the connected devices (kind, name,
// battery), and a line when there are none, the power is off or permission
// was refused. The reading is `BluetoothWriter`'s; what the section shows
// is decided in GroveKeysCore (`BluetoothSectionContent`).

/// The Bluetooth section's state, kept by the Wi-Fi panel's model. Live, it
/// follows `BluetoothWriter.shared` while the panel is open and asks it for
/// a reading at each opening; `.sample` is fixed data for `--render-panel`
/// (`BarPanelSamples.bluetooth`), and never reads or switches anything.
@MainActor
final class BluetoothSectionModel: ObservableObject {
    @Published private(set) var state: BluetoothState?
    @Published private(set) var permission: BluetoothPermission
    /// The switch's value while the power is being changed, until the next
    /// reading (or 5 s).
    @Published private(set) var pending: Bool?

    private let live: Bool
    private var watching: AnyCancellable?
    /// Counts the switch's changes, to tell a late time-out of an earlier one.
    private var change = 0
    private let switching = DispatchQueue(label: "com.projectgrove.keys.bluetooth-switch", qos: .userInitiated)

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            live = true
            state = BluetoothWriter.shared.state
            permission = BluetoothPower.permission
        case .sample:
            live = false
            let sample = BarPanelSamples.bluetooth(ProcessInfo.processInfo.environment["GROVE_BLUETOOTH_SAMPLE"] ?? "on")
            state = sample.state
            permission = sample.permission
        }
    }

    var content: BluetoothSectionContent { BluetoothSectionContent(state: state, permission: permission) }
    var switchOn: Bool { pending ?? content.switchOn }

    /// The panel opened: the last reading at once, a fresh one asked for.
    /// The first opening while macOS hasn't been asked yet asks (once, for
    /// the app's life); its answer refreshes the section.
    func start() {
        guard live else { return }
        permission = BluetoothPower.permission
        BluetoothPermissionAsker.shared.askIfUndetermined { [weak self] in
            guard let self else { return }
            let permission = BluetoothPower.permission
            guard permission != self.permission else { return }
            self.permission = permission
            BluetoothWriter.shared.refresh(force: true)
        }
        state = BluetoothWriter.shared.state
        pending = nil
        // `$state` sends the current value first, then each new one (before
        // it is stored: the value is the sent one).
        // The writer publishes on the main actor.
        watching = BluetoothWriter.shared.$state.dropFirst().sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.state = state
                self?.pending = nil
            }
        }
        BluetoothWriter.shared.refresh()
    }

    func stop() {
        watching = nil
    }

    /// The switch: the power through IOBluetooth, off the main thread, then a
    /// fresh reading. When that can't be done, `openSettings` (Bluetooth
    /// Settings). Nothing when permission is refused or the power is unknown.
    func setPower(_ on: Bool, orElse openSettings: @escaping @MainActor () -> Void) {
        guard live, content.switchEnabled, on != switchOn else { return }
        pending = on
        change += 1
        let change = change
        switching.async { [weak self] in
            let done = BluetoothPower.set(on)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.permission = BluetoothPower.permission
                    guard done else {
                        self.pending = nil
                        openSettings()
                        return
                    }
                    BluetoothWriter.shared.refresh(force: true)
                    // A reading that changes nothing isn't sent: the switch
                    // goes back to the last reading after 5 s at the latest.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        MainActor.assumeIsolated {
                            guard let self, self.change == change else { return }
                            self.pending = nil
                        }
                    }
                }
            }
        }
    }
}

/// The section's views, after the Wi-Fi panel's orange line.
struct BluetoothSection: View {
    @ObservedObject var model: BluetoothSectionModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        let content = model.content
        PanelHeader(title: "Bluetooth") {
            if content.showsSwitch {
                PanelSwitch("Bluetooth", isOn: Binding(
                    get: { model.switchOn },
                    set: { model.setPower($0, orElse: { open(BluetoothPower.settingsURL) }) }))
                    .disabled(!content.switchEnabled)
            }
        }
        // The title on the Wi-Fi title's column (and the device names'):
        // SF Symbols has no Bluetooth symbol to fill the icon column.
        .padding(.leading, PanelMetrics.iconColumn + GroveSpace.s8)
        switch content {
        case .refused:
            // A warning in the battery panel's yellow: orange is the lines'.
            VStack(alignment: .leading, spacing: GroveSpace.s8) {
                theme.marked(content.line ?? "", theme.yellow)
                PanelButton("Privacy Settings…") { open(BluetoothPower.privacyURL) }
                    .help("Allow Grove Keys to use Bluetooth")
            }
            devices(content.devices)
        case .devices(let devices) where !devices.isEmpty:
            self.devices(devices)
        default:
            if let line = content.line { Text(line).foregroundStyle(theme.quiet) }
        }
        PanelRule()
        PanelFooter("Bluetooth Settings…") { open(BluetoothPower.settingsURL) }
    }

    @ViewBuilder private func devices(_ devices: [BluetoothDevice]) -> some View {
        if !devices.isEmpty {
            VStack(alignment: .leading, spacing: GroveSpace.s4) {
                ForEach(devices) { BluetoothDeviceRow(device: $0) }
            }
        }
    }

    private func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        panel.open(url)
    }
}

/// A connected device: its kind's icon, its name, and its battery quiet at
/// the right when it reports one. Not clickable (pairing is System Settings').
private struct BluetoothDeviceRow: View {
    let device: BluetoothDevice
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
            GroveIcon(icon, size: GroveType.body)
                .frame(width: PanelMetrics.iconColumn, alignment: .leading)
            Text(device.name).truncationMode(.tail)
            Spacer(minLength: GroveSpace.s4)
            if let battery = device.batteryText { Text(battery).foregroundStyle(theme.quiet) }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(device.batteryText.map { "\(device.name), battery \($0)" } ?? device.name)
    }

    private var icon: GroveIcon.Name {
        switch device.kind {
        case .headphones: return .headphones
        case .keyboard: return .keys
        case .mouse: return .mouse
        case .trackpad: return .trackpad
        case .speaker: return .speaker
        case .other: return .wireless
        }
    }
}
