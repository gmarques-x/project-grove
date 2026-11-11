import AppKit
import Combine
import Foundation
import GroveKeysCore
import GroveThemesCore

/// The app's one model: keys.toml as last applied, the save path, the Hyper
/// engine and the Caps Lock mapping. The mapping is on only while both
/// permissions are granted, the tap runs, and Hyper is enabled and not paused.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

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
    /// The menu glyph turns orange.
    var needsAttention: Bool { !permissions.granted || redLine != nil }

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
    private var loaded = false
    /// What the running engine was given, so unrelated edits don't reset it mid-hold.
    private var engineSettings: HyperSettings?
    private var engineLaunchKeys: Set<String> = []
    private var lastState: KeysState?

    private init() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths = KeysPaths.standard(home: home, environment: environment)
        pipeline = SavePipeline(paths: paths, host: localHostName(), aerospace: AeroSpaceCLI())
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/bin/grove-themes")
        themes = GroveThemesClient(runner: ProcessRunner(path: cli))
        stateURL = KeysState.url(environment: environment, home: home)
        themeStateURL = StatePath.url(environment: environment, home: home)
        keys = try! KeysFile(text: "")  // the defaults, until the first run answers
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

        enqueue { [pipeline] in await pipeline.run() }
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

    /// Mutate, write keys.toml, run the save path, publish the result.
    func edit(_ change: (inout KeysFile) -> Void) {
        var next = keys
        change(&next)
        guard next != keys else { return }
        watcher?.ignoreNextChange(contents: Data(next.document.serialized().utf8))
        enqueue { [pipeline, next] in
            do { try await pipeline.write(next) } catch {
                return .keysInvalid(TomlError(line: 0, message: "cannot write keys.toml: \(error.localizedDescription)"))
            }
            return await pipeline.run()
        }
    }

    /// Runs one after another, in the order asked.
    private func enqueue(_ work: @escaping @Sendable () async -> SaveResult) {
        let previous = saving
        saving = Task {
            await previous?.value
            let result = await work()
            apply(result)
        }
    }

    private func apply(_ result: SaveResult) {
        switch result {
        case .applied(let k), .unchanged(let k), .aerospaceRejected(let k, _):
            keys = k
        case .keysInvalid:
            break  // the last good config keeps running
        }
        saveLine = result.redLine
        layers = Layers.build(from: keys) { Launcher.appName(bundleID: $0) }
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

    private func fileChanged() {
        enqueue { [pipeline] in await pipeline.run() }
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
        } catch {}
    }
}
