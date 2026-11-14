import AppKit
import Combine
import GroveKeysCore
import GroveThemesCore
import GroveUI
import SwiftUI

// The cloud pill's dropdown (spec 2026-11-14-bar-cloud-design): one section
// per provider, iCloud Drive first, then each folder in CloudStorage. Each
// has its name and status line, up to five pending or failed files (a click
// opens Grove Explorer at the file), "Open in Grove Explorer" and, for iCloud
// and OneDrive, "Settings…". The reading is `CloudTracker`'s; what a section
// shows is GroveKeysCore's (`CloudSection`).

/// The cloud panel's state. Live, it follows `CloudTracker.shared`'s summary
/// (throttled there to two a second) while the panel is open; `.sample` is
/// fixed data for `--render-panel` (GROVE_CLOUD_SAMPLE, `CloudSample`) and
/// never reads a folder or presses anything.
@MainActor
final class CloudModel: ObservableObject, BarPanelModel {
    @Published private(set) var summary: CloudSummary
    /// OneDrive's "Settings…" couldn't press through to its settings: the
    /// fallback line, until the opening after the one that showed it.
    @Published private(set) var oneDriveHint = OneDriveSettings.Hint()

    private let live: Bool
    private var watching: AnyCancellable?

    init(_ data: BarPanelData) {
        switch data {
        case .live:
            live = true
            summary = CloudTracker.shared.summary
        case .sample:
            live = false
            // `CloudSample`'s states, and two of OneDrive's Settings… falling
            // back (`nomenu`: nothing found; `noaccess`: no Accessibility).
            let name = ProcessInfo.processInfo.environment["GROVE_CLOUD_SAMPLE"] ?? "synced"
            summary = CloudSample.summary(name)
            if name == "nomenu" { oneDriveHint.set(.notFound) }
            if name == "noaccess" { oneDriveHint.set(.notTrusted) }
        }
    }

    var sections: [CloudSection] { CloudSection.sections(summary) }

    func start() {
        guard live else { return }
        oneDriveHint.opened()
        summary = CloudTracker.shared.summary
        // `$summary` sends the current value first, then each new one, on the
        // main actor (the tracker sets it there).
        watching = CloudTracker.shared.$summary.dropFirst().sink { [weak self] summary in
            MainActor.assumeIsolated {
                guard let self, summary != self.summary else { return }
                self.summary = summary
            }
        }
    }

    func stop() {
        watching = nil
    }

    /// OneDrive's "Settings…": its settings window through its status item
    /// (`close` puts the panel away just before the press). Live only.
    func oneDriveSettings(close: @escaping @MainActor @Sendable () -> Void) {
        guard live else { return }
        oneDriveHint.clear()
        guard let app = OneDriveSettingsOpener.appURL else {
            oneDriveHint.set(.notFound)
            return
        }
        OneDriveSettingsOpener.openSettings(app: app, close: close) { [weak self] outcome in
            guard let self, case .fallback(let reason) = outcome else { return }
            self.oneDriveHint.set(reason)
        }
    }
}

struct CloudPanel: View {
    static let width: CGFloat = 320
    static let registration = BarPanelRegistration("cloud", pill: "pill.cloud", width: width,
                                                   model: CloudModel.init) { CloudPanel(model: $0) }

    @ObservedObject var model: CloudModel
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        let sections = model.sections
        BarPanel(width: Self.width) {
            if sections.isEmpty {
                VStack(alignment: .leading, spacing: GroveSpace.s8) {
                    PanelHeader(.cloudStorage, accent: theme.dim, title: "Cloud storage")
                    Text(CloudWords.noFolders).foregroundStyle(theme.quiet)
                        .padding(.leading, PanelMetrics.iconColumn + GroveSpace.s8)
                }
            }
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 { PanelRule() }
                CloudSectionView(section: section,
                                 hint: section.settings == .oneDrive ? model.oneDriveHint.reason : nil,
                                 settings: { settings(section) })
            }
        }
    }

    /// iCloud: its pane in System Settings (plain System Settings when the
    /// link doesn't open). OneDrive: its settings window through its status
    /// item. Nothing in a render.
    private func settings(_ section: CloudSection) {
        switch section.settings {
        case .iCloud?:
            panel.leave {
                guard !NSWorkspace.shared.open(CloudLinks.iCloudSettings),
                      let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: CloudLinks.systemSettings)
                else { return }
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(),
                                                   completionHandler: nil)
            }
        case .oneDrive?:
            let panel = panel
            model.oneDriveSettings(close: { panel.leave {} })
        case nil:
            break
        }
    }
}

/// One provider: its header (the state's cloud in the bar's colour), the
/// status line, its files, a fallback line, and the buttons.
private struct CloudSectionView: View {
    let section: CloudSection
    /// OneDrive's Settings… fell back: why.
    let hint: OneDriveSettings.Reason?
    let settings: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.barPanel) private var panel

    var body: some View {
        VStack(alignment: .leading, spacing: GroveSpace.s8) {
            VStack(alignment: .leading, spacing: GroveSpace.s4) {
                PanelHeader(icon, accent: accent, title: section.name)
                CloudLine(text: section.line, tone: section.tone)
                    .padding(.leading, PanelMetrics.iconColumn + GroveSpace.s8)
                    .accessibilityLabel("\(section.name): \(section.line)")
            }
            if section.offersFilesPrivacy {
                PanelButton(CloudWords.privacySettings) { panel.open(CloudLinks.filesPrivacy) }
                    .help("Allow Grove Keys to see \(section.name)'s files")
            }
            if !section.rows.isEmpty {
                PanelRows {
                    ForEach(section.rows) { row in
                        CloudFileRow(row: row) { panel.open(row.link) }
                    }
                }
            }
            if let hint {
                VStack(alignment: .leading, spacing: GroveSpace.s4) {
                    theme.marked(hint.line, theme.yellow).fixedSize(horizontal: false, vertical: true)
                    if let permission = hint.permissionLine { theme.marked(permission, theme.yellow) }
                }
                if hint.permissionLine != nil, let url = URL(string: WireGuardMenu.privacyURL) {
                    PanelButton(CloudWords.privacySettings) { panel.open(url) }
                        .help("Allow Grove Keys to use Accessibility")
                }
            }
            HStack(spacing: GroveSpace.s8) {
                PanelButton(CloudWords.openInExplorer) { panel.open(section.opens) }
                    .help("Opens \(section.name)'s folder in Grove Explorer")
                if section.showsSettings {
                    PanelButton(CloudWords.settings, action: settings)
                        .help(section.settings == .iCloud ? "Opens iCloud in System Settings"
                            : "Opens OneDrive's settings")
                }
            }
        }
    }

    private var icon: GroveIcon.Name {
        switch section.mark {
        case .checking: return .cloud
        case .synced: return .cloudSynced
        case .syncing: return .cloudSyncing
        case .problem: return .cloudProblem
        case .unseen: return .cloudUnseen
        }
    }

    /// The bar's colours: green synced, yellow syncing, red a problem, dim
    /// still looking or out of sight.
    private var accent: RGB {
        switch section.mark {
        case .checking, .unseen: return theme.dim
        case .synced: return theme.green
        case .syncing: return theme.yellow
        case .problem: return theme.red
        }
    }
}

/// A line in its tone: quiet, or a sentence marked yellow or red.
private struct CloudLine: View {
    let text: String
    let tone: CloudTone
    @Environment(\.theme) private var theme

    var body: some View {
        switch tone {
        case .quiet: Text(text).foregroundStyle(theme.quiet).lineLimit(1)
        case .warning: theme.marked(text, theme.yellow).fixedSize(horizontal: false, vertical: true)
        case .error: theme.marked(text, theme.red).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A pending or failed file: which way it is going (or a warning), its name,
/// its folder quiet at the right, and the problem under it in yellow or red.
/// A click opens Grove Explorer at the file.
private struct CloudFileRow: View {
    let row: CloudSection.Row
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        PanelRow(action: action) {
            GroveIcon(icon, size: GroveType.body)
                .foregroundStyle(row.tone == .quiet ? theme.quiet : Color(accent))
                .frame(width: PanelMetrics.iconColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: GroveSpace.s2) {
                HStack(alignment: .firstTextBaseline, spacing: GroveSpace.s8) {
                    Text(row.name).truncationMode(.middle).layoutPriority(1)
                    Spacer(minLength: GroveSpace.s4)
                    Text(row.folder).foregroundStyle(theme.quiet).truncationMode(.head)
                }
                if let problem = row.problem { theme.marked(problem, accent) }
            }
        }
        .accessibilityLabel([row.name, "in " + row.folder, row.problem ?? direction].joined(separator: ", "))
        .help(CloudWords.openInExplorer)
    }

    private var icon: GroveIcon.Name {
        switch row.direction {
        case .up: return .up
        case .down: return .down
        case .problem: return .warning
        }
    }

    private var accent: RGB { row.tone == .error ? theme.red : theme.yellow }

    private var direction: String {
        switch row.direction {
        case .up: return "uploading"
        case .down: return "downloading"
        case .problem: return "problem"
        }
    }
}
