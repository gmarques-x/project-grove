import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// Connect to Server… (⌘K, File ▸ Connect to Server…, the LOCATIONS header's +):
/// a share's address, mounted, then saved and opened (shared-folders spec).
/// What the address is wrong in is said under the field before anything is
/// mounted; while it connects, a spinner by Connect and Cancel gives the
/// mount up (the sheet stays, the address kept); a failure is said under the
/// field, the address kept to be corrected; success closes the sheet.
///
/// Keys: Return is Connect, Escape is Cancel.
struct ConnectSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    // `State` used directly: no SwiftUI macros here.
    private var text: State<String>
    /// The sentence under the field; nil (or empty) says nothing.
    private var problem: State<String?>
    private var connecting: State<Bool>

    /// The sheet's width: room for a share's address and its sentences.
    private static let width: CGFloat = 400

    /// A render passes the state to draw; the app opens it empty.
    init(model: AppModel, text: String = "", problem: String? = nil, connecting: Bool = false) {
        self.model = model
        self.text = State(initialValue: text)
        self.problem = State(initialValue: problem)
        self.connecting = State(initialValue: connecting)
    }

    var body: some View {
        let problem = problem.wrappedValue.flatMap { $0.isEmpty ? nil : $0 }
        let connecting = connecting.wrappedValue
        VStack(alignment: .leading, spacing: GroveSpace.s16) {
            Text(verbatim: "Connect to Server")
                .font(GroveFont.mono(GroveType.heading, .semibold))
                .foregroundStyle(Color(theme.fg))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: GroveSpace.s4) {
                Text(verbatim: "Server address")
                    .font(GroveFont.mono(GroveType.body))
                    .foregroundStyle(theme.quiet)
                    .accessibilityHidden(true)
                TextField("Server address", text: text.projectedValue, prompt: Text(verbatim: "smb://grove-lab/share"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .font(GroveFont.mono(GroveType.label))
                    .lineLimit(1)
                    .focused($focused)
                    .onSubmit(connect)
                    // What was said of the address goes as it is corrected.
                    .onChange(of: text.wrappedValue) { _, _ in
                        if self.problem.wrappedValue != nil { self.problem.wrappedValue = nil }
                    }
                    .disabled(connecting)
                    .padding(.horizontal, GroveSpace.s8).padding(.vertical, GroveSpace.s4)
                    .background(Color(theme.bg0), in: RoundedRectangle(cornerRadius: GroveRadius.control))
                    // Red while what was typed can't be connected to, green while it has the keyboard.
                    .overlay(
                        RoundedRectangle(cornerRadius: GroveRadius.control).strokeBorder(
                            problem != nil ? Color(theme.red) : focused ? Color(theme.green) : theme.line, lineWidth: 1))
                    .accessibilityLabel("Server address")
                if let problem {
                    theme.marked(problem, theme.red, size: GroveType.body)
                        .font(GroveFont.mono(GroveType.body))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: GroveSpace.s8) {
                Spacer()
                PanelButton("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                if connecting {
                    ProgressView().controlSize(.mini)
                        .accessibilityLabel("Connecting")
                }
                PanelButton("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(connecting)
            }
        }
        .padding(GroveSpace.s16)
        .frame(width: Self.width)
        .background(Color(theme.bg0))
        .onAppear { focused = model.live }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connect to Server")
    }

    /// Mounts what is typed: the sheet closes on success (the model does
    /// that); otherwise its sentence goes under the field, the text kept.
    private func connect() {
        guard !connecting.wrappedValue else { return }
        // A mistake in the address is said at once, before anything mounts.
        if case .failure(let mistake) = SharedAddress.parse(text.wrappedValue) {
            problem.wrappedValue = mistake.sentence
            return
        }
        problem.wrappedValue = nil
        connecting.wrappedValue = true
        let typed = text.wrappedValue
        Task { @MainActor in
            let sentence = await model.connectNew(typed)
            connecting.wrappedValue = false
            problem.wrappedValue = sentence
            if sentence != nil { focused = true }
        }
    }

    /// While it connects, the mount is given up and the sheet stays (the
    /// mount's own answer, `.quiet`, says nothing); otherwise it closes.
    private func cancel() {
        if connecting.wrappedValue {
            model.cancelConnectNew()
        } else {
            model.showsConnectSheet = false
        }
    }
}
