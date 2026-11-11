import AppKit
import Combine
import Foundation
import GroveKeysCore
import GroveThemesCore
import os

/// The app's one model: keys.toml as last applied, the save path, the Hyper
/// engine and the Caps Lock mapping. The mapping is on only while both
/// permissions are granted, the tap runs, and Hyper is enabled and not paused.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private static let log = Logger(subsystem: "com.projectgrove.keys", category: "app")

    @Published private(set) var keys: KeysFile
    @Published private(set) var layers: [Layer] = []
    @Published private(set) var paused = false
    @Published private(set) var permissions = PermissionStatus(accessibility: false, inputMonitoring: false)
    @Published private(set) var colors = ThemeColors.fallback
    /// The Caps Lock → F18 mapping is set right now.
    @Published private(set) var mapping = false
    /// From the last save run (keys.toml or AeroSpace).
    @Published private var saveLine: String?
    /// From the engine (the tap kept stopping, or can't be created).
    @Published private var engineLine: String?

    /// The red line under the tabs and in the menu.
    var redLine: String? { engineLine ?? saveLine }
    /// `edit` would be applied: keys.toml has been read and has no error.
    var canEdit: Bool { loaded && !keysInvalid }
    /// The menu glyph turns orange.
    var needsAttention: Bool { !permissions.granted || redLine != nil }

    /// This Mac's LocalHostName, for the window's header.
    let host: String
    private let paths: KeysPaths
    private let pipeline: SavePipeline
    private let themes: GroveThemesClient
    private let stateURL: URL
    private let themeStateURL: URL
    private var engine: HyperEngine!
    private var watcher: FileWatcher?
    private var themeWatcher: FileWatcher?
    private var keyboards: KeyboardWatcher?
    private var saving: Task<Void, Never>?
    private var pollTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []
    private var started = false
    /// The first save run has answered; until then the engine stays off.
    @Published private var loaded = false
    /// What the running engine was given, so unrelated edits don't reset it mid-hold.
    private var engineSettings: HyperSettings?
    private var engineLaunchKeys: Set<String> = []
    private var lastState: KeysState?
    /// The last keys.toml the save path accepted (the defaults until then).
    private var lastGood: KeysFile
    /// keys.toml on disk has an error with a line number: edits are refused.
    @Published private var keysInvalid = false
    /// The newest edit, and how many edits are still saving.
    private var pendingKeys: KeysFile?
    private var pendingEdits = 0

    private init() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths = KeysPaths.standard(home: home, environment: environment)
        host = localHostName()
        pipeline = SavePipeline(paths: paths, host: host, aerospace: AeroSpaceCLI())
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/bin/grove-themes")
        themes = GroveThemesClient(runner: ProcessRunner(path: cli))
        stateURL = KeysState.url(environment: environment, home: home)
        themeStateURL = StatePath.url(environment: environment, home: home)
        let defaults = try! KeysFile(text: "")  // until the first run answers
        keys = defaults
        lastGood = defaults
        engine = HyperEngine(
            onEffect: { effect in AppModel.shared.perform(effect) },
            onFailure: { AppModel.shared.tapKeptStopping() })
    }

    // MARK: Life cycle

    func start() {
        guard !started else { return }
        started = true
        // A mapping left by a crash would make Caps Lock dead until the tap runs.
        HIDMapping.clear()
        installSignalHandlers()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppModel.shared.reapplyMapping() }
        }

        permissions = Permissions.current()
        if !permissions.granted { Permissions.request(permissions) }
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { AppModel.shared.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        themeWatcher = FileWatcher(file: themeStateURL) {
            Task { @MainActor in AppModel.shared.refreshColors() }
        }
        themeWatcher?.start()
        refreshColors()

        enqueue(edit: false) { [pipeline] in await pipeline.run() }
        writeState()
    }

    /// Every exit path: mapping off first, then the tap. Safe to call twice.
    func shutdown() {
        HIDMapping.clear()
        mapping = false
        stopEngine()
        pollTimer?.invalidate()
        watcher?.stop()
        writeState()
    }

    func quit() {
        shutdown()
        NSApp.terminate(nil)
    }

    func togglePause() {
        paused.toggle()
        if !paused { engineLine = nil }
        reconcile()
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { AppModel.shared.shutdown() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Editing and the file

    /// Mutate, write keys.toml, run the save path, publish the result. The
    /// change shows at once; edits made while earlier ones are still saving
    /// build on them. Refused while keys.toml on disk is invalid, and checked
    /// again just before writing, so a broken hand edit is never overwritten
    /// (the red line stays up).
    func edit(_ change: (inout KeysFile) -> Void) {
        // Not before the first run has read the file (an edit would write the
        // defaults), and not over a keys.toml with an error.
        guard loaded, !keysInvalid else { return }
        let base = pendingKeys ?? keys
        var next = base
        change(&next)
        guard next != base else { return }
        pendingKeys = next
        pendingEdits += 1
        publish(next)
        watcher?.ignoreNextChange(contents: Data(next.document.serialized().utf8))
        enqueue(edit: true) { [pipeline, next] in
            if let error = await pipeline.writeOverValid(next) { return .keysInvalid(error) }
            return await pipeline.run()
        }
    }

    /// Runs one after another, in the order asked.
    private func enqueue(edit: Bool, _ work: @escaping @Sendable () async -> SaveResult) {
        let previous = saving
        saving = Task {
            await previous?.value
            let result = await work()
            apply(result, edit: edit)
        }
    }

    private func apply(_ result: SaveResult, edit: Bool) {
        if edit { pendingEdits -= 1 }
        switch result {
        case .applied(let k), .unchanged(let k), .aerospaceRejected(let k, _):
            lastGood = k
            keysInvalid = false
        case .keysInvalid(let error):
            // A line number means keys.toml itself is broken; a missing file or a
            // failed write does not block edits.
            keysInvalid = error.line > 0
        }
        // While edits are still saving, the screen keeps showing the newest one.
        if pendingEdits == 0 {
            pendingKeys = nil
            publish(lastGood)
        }
        saveLine = result.redLine
        if !loaded {
            loaded = true
            let watcher = FileWatcher(file: paths.keys) {
                Task { @MainActor in AppModel.shared.fileChanged() }
            }
            watcher.start()
            self.watcher = watcher
        }
        reconcile()
    }

    private func publish(_ new: KeysFile) {
        if new != keys { keys = new }
        layers = Layers.build(from: keys) { Launcher.appName(bundleID: $0) }
    }

    private func fileChanged() {
        enqueue(edit: false) { [pipeline] in await pipeline.run() }
    }

    private func refreshColors() {
        Task { [themes] in
            guard let list = try? await themes.list() else { return }
            colors = list.palettes[list.current].flatMap(ThemeColors.init(palette:)) ?? .fallback
        }
    }

    // MARK: Engine and mapping

    private var launchKeys: Set<String> { Set(keys.launch.map(\.key)) }

    /// Brings the tap and the mapping in line with the permissions, the file and Pause.
    private func reconcile() {
        let want = loaded && permissions.granted && keys.hyper.enabled && !paused
        if want {
            if engine.isRunning {
                if engineSettings != keys.hyper || engineLaunchKeys != launchKeys {
                    engine.update(settings: keys.hyper, launchKeys: launchKeys)
                    engineSettings = keys.hyper
                    engineLaunchKeys = launchKeys
                }
            } else if engine.start(settings: keys.hyper, launchKeys: launchKeys) {
                engineSettings = keys.hyper
                engineLaunchKeys = launchKeys
                if engineLine == Self.cannotStart { engineLine = nil }
            } else {
                engineLine = Self.cannotStart
            }
            if engine.isRunning, !mapping {
                if keyboards == nil {
                    keyboards = KeyboardWatcher { AppModel.shared.reapplyMapping() }
                }
                mapping = HIDMapping.set()
            }
        } else {
            if mapping || engine.isRunning {
                HIDMapping.clear()
                mapping = false
            }
            stopEngine()
            if engineLine == Self.cannotStart { engineLine = nil }
        }
        writeState()
    }

    private func stopEngine() {
        guard engine.isRunning else { return }
        engine.stop()
        engineSettings = nil
    }

    /// On wake and when a keyboard is connected.
    private func reapplyMapping() {
        guard mapping, engine.isRunning else { return }
        mapping = HIDMapping.set()
        writeState()
    }

    private func poll() {
        permissions = Permissions.current()  // a drop stops the tap in reconcile
        reconcile()
    }

    static let cannotStart = "Grove Keys can't watch the keyboard yet · quit and reopen it after granting the permissions"

    private func tapKeptStopping() {
        HIDMapping.clear()
        mapping = false
        stopEngine()
        paused = true
        engineLine = "macOS kept stopping the key tap, so Hyper is off · Resume Hyper to try again"
        writeState()
    }

    private func perform(_ effect: HyperEffect) {
        switch effect {
        case .launch(let key):
            if let bundleID = keys.launch.first(where: { $0.key == key })?.bundleID {
                _ = Launcher.open(bundleID: bundleID)
            }
        case .showCheatSheet: showCheatSheet()
        case .hideCheatSheet: hideCheatSheet()
        case .postEscape: break  // posted on the tap thread
        }
    }

    /// The cheat sheet panel (Task 10).
    func showCheatSheet() {}
    func hideCheatSheet() {}

    // MARK: State file

    private func writeState() {
        let state = KeysState(accessibility: permissions.accessibility,
                              inputMonitoring: permissions.inputMonitoring, mapping: mapping)
        guard state != lastState else { return }
        do {
            try state.write(to: stateURL)
            lastState = state
        } catch {
            Self.log.error("cannot write \(self.stateURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
