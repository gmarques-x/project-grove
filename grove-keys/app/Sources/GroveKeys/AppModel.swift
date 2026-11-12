import AppKit
import Combine
import Foundation
import GroveKeysCore
import GroveThemesCore
import GroveUI
import os

/// The app's one model: keys.toml and this Mac's monitors.toml as last
/// applied, the save path, the Hyper engine and the Caps Lock mapping. The
/// mapping is on only while both permissions are granted, the tap runs, and
/// Hyper is enabled and not paused. (The tap also runs with Hyper off or
/// paused, for the right Option's characters and the launcher's key.)
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private static let log = Logger(subsystem: "com.projectgrove.keys", category: "app")

    @Published private(set) var keys: KeysFile
    /// This Mac's monitors.toml (no assignments when there is no file).
    @Published private(set) var monitors = MonitorsFile()
    @Published private(set) var layers: [Layer] = []
    @Published private(set) var paused = false
    /// Opens the window from outside SwiftUI (the pointer menu); set by the
    /// menu bar label, which SwiftUI always keeps alive.
    var openMainWindow: (() -> Void)?
    @Published private(set) var permissions = PermissionStatus(accessibility: false, inputMonitoring: false)
    @Published private(set) var colors = ThemeColors.fallback
    /// The Caps Lock → F18 mapping is set right now.
    @Published private(set) var mapping = false
    /// From the last save run (keys.toml, monitors.toml or AeroSpace).
    @Published private var saveLine: String?
    /// From the engine (the tap kept stopping, or can't be created).
    @Published private var engineLine: String?

    /// The red line under the tabs and in the menu.
    var redLine: String? { engineLine ?? saveLine }
    /// `edit` would be applied: the first run has answered, and keys.toml has
    /// no error and is readable (or doesn't exist yet).
    var canEdit: Bool { loaded && !keysInvalid }
    /// `editMonitors` would be applied: monitors.toml has been read (or isn't
    /// there) and has no error. Not while keys.toml has one either: nothing
    /// is rendered then, so the change could not be shown to have worked.
    var canEditMonitors: Bool { canEdit && monitorsKnown && !monitorsInvalid }
    /// The menu bar glyph turns orange.
    var needsAttention: Bool { !permissions.granted || redLine != nil }
    /// The menus show "Restart Grove Keys": a permission is missing or the
    /// engine is in trouble, the two states a new process can fix (macOS may
    /// only let a process started after the grant watch the keyboard). Not for
    /// a keys.toml error, which a restart wouldn't change.
    var offersRestart: Bool { !permissions.granted || engineLine != nil }
    /// Grove Keys' own menu as the pointer menus and the launcher show it.
    var keysMenuItems: [KeysMenuItem] {
        KeysMenuItem.items(accessibility: permissions.accessibility, inputMonitoring: permissions.inputMonitoring,
                           redLine: redLine, offersRestart: offersRestart, paused: paused)
    }

    private let paths: KeysPaths
    private let pipeline: SavePipeline
    private let themes: GroveThemesClient
    private let stateURL: URL
    private let themeStateURL: URL
    private var engine: HyperEngine!
    private var watcher: FileWatcher?
    /// monitors.toml: a hand edit (or the file appearing) re-renders too.
    private var monitorsWatcher: FileWatcher?
    /// aerospace.base.toml: a change there re-renders as a keys.toml change does.
    private var baseWatcher: FileWatcher?
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
    /// macOS kept stopping the tap: it stays off (with Hyper paused) until Resume Hyper.
    private var tapGaveUp = false
    private var lastState: KeysState?
    /// The last keys.toml the save path accepted (the defaults until then).
    private var lastGood: KeysFile
    /// keys.toml has been parsed once, or isn't there at all (the defaults
    /// stand in). Until then the engine and the mapping stay off, so a broken
    /// file at launch never runs the defaults (Hyper on against `enabled = false`).
    @Published private var keysKnown = false
    /// keys.toml on disk has an error on a line, or is there but can't be
    /// read: edits are refused (see `SaveResult.blocksEdits`).
    @Published private var keysInvalid = false
    /// The newest edit, and how many edits are still saving.
    private var pendingKeys: KeysFile?
    private var pendingEdits = 0
    /// The same for monitors.toml. A run reads it only after keys.toml
    /// parses, so until one has, `monitorsKnown` is false: an edit would
    /// write over a file the app has never seen.
    private var lastGoodMonitors = MonitorsFile()
    @Published private var monitorsKnown = false
    @Published private var monitorsInvalid = false
    private var pendingMonitors: MonitorsFile?
    private var pendingMonitorEdits = 0

    private init() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        paths = KeysPaths.standard(home: home, environment: environment)
        pipeline = SavePipeline(paths: paths, aerospace: AeroSpaceCLI())
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

        // The first run reloads AeroSpace even if the render is current:
        // grove install may have rendered it without AeroSpace reloading.
        enqueue { [pipeline] in await pipeline.run(forceReload: true) }
        writeState()
        // The Wi-Fi name for the Grove bar; optional, apart from the rest.
        WifiNameWriter.shared.start()
        // The apps for the Grove Launcher, so its first opening has them.
        LauncherPanel.shared.refreshApps()
        // The window borders, hidden while Mission Control is up.
        BordersWatcher.shared.start()
    }

    /// Every exit path: mapping off first, then the tap. Safe to call twice.
    func shutdown() {
        HIDMapping.clear()
        mapping = false
        stopEngine()
        pollTimer?.invalidate()
        watcher?.stop()
        monitorsWatcher?.stop()
        baseWatcher?.stop()
        writeState()
        WifiNameWriter.shared.stop()
        // Borders hidden for an overview come back before the app goes.
        BordersWatcher.shared.shutdown()
    }

    func quit() {
        shutdown()
        NSApp.terminate(nil)
    }

    /// The same cleanup as `quit` (the mapping off, then the tap), then a
    /// failure exit: the LaunchAgent keeps Grove Keys alive after any exit
    /// that isn't a success, so launchd starts it again. Run without the
    /// LaunchAgent (bare from .build), this only quits.
    func restart() {
        shutdown()
        exit(1)
    }

    func togglePause() {
        paused.toggle()
        if !paused {
            engineLine = nil
            tapGaveUp = false
        }
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
        enqueue(edit: .keys) { [pipeline, next] in
            if let error = await pipeline.writeOverValid(next) { return .keysInvalid(error) }
            return await pipeline.run()
        }
    }

    /// `edit` for monitors.toml (the Monitors panel): the same rules, and the
    /// first change creates the file.
    func editMonitors(_ change: (inout MonitorsFile) -> Void) {
        guard canEditMonitors else { return }
        let base = pendingMonitors ?? monitors
        var next = base
        change(&next)
        guard next != base else { return }
        pendingMonitors = next
        pendingMonitorEdits += 1
        monitors = next
        monitorsWatcher?.ignoreNextChange(contents: Data(next.document.serialized().utf8))
        enqueue(edit: .monitors) { [pipeline, next] in await pipeline.save(next) }
    }

    /// Which file a save run follows an edit of, if any.
    private enum Edited { case keys, monitors }

    /// Runs one after another, in the order asked.
    private func enqueue(edit: Edited? = nil, _ work: @escaping @Sendable () async -> SaveResult) {
        let previous = saving
        saving = Task {
            await previous?.value
            let result = await work()
            apply(result, edit: edit)
        }
    }

    private func apply(_ result: SaveResult, edit: Edited?) {
        if edit == .keys { pendingEdits -= 1 }
        if edit == .monitors { pendingMonitorEdits -= 1 }
        if let k = result.keys {
            lastGood = k
            keysKnown = true
        } else if result.keysMissing {
            keysKnown = true  // no file at all: the defaults are right
        }
        // An error on a line, or a file that is there but can't be read, blocks
        // edits; a missing file or a failed write does not.
        keysInvalid = result.blocksEdits
        // A run that stopped at keys.toml says nothing about monitors.toml.
        if let m = result.monitors {
            lastGoodMonitors = m
            monitorsKnown = true
            monitorsInvalid = false
        } else if result.blocksMonitorEdits {
            monitorsInvalid = true
        }
        // While edits are still saving, the screen keeps showing the newest one.
        if pendingEdits == 0 {
            pendingKeys = nil
            publish(lastGood)
        }
        if pendingMonitorEdits == 0 {
            pendingMonitors = nil
            if monitors != lastGoodMonitors { monitors = lastGoodMonitors }
        }
        saveLine = result.redLine
        if !loaded {
            loaded = true
            let watcher = FileWatcher(file: paths.keys) {
                Task { @MainActor in AppModel.shared.fileChanged() }
            }
            watcher.start()
            self.watcher = watcher
            let monitorsWatcher = FileWatcher(file: paths.monitors) {
                Task { @MainActor in AppModel.shared.fileChanged() }
            }
            monitorsWatcher.start()
            self.monitorsWatcher = monitorsWatcher
            let baseWatcher = FileWatcher(file: paths.base) {
                Task { @MainActor in AppModel.shared.fileChanged() }
            }
            baseWatcher.start()
            self.baseWatcher = baseWatcher
        }
        reconcile()
    }

    private func publish(_ new: KeysFile) {
        if new != keys { keys = new }
        layers = Layers.build(from: keys) { Launcher.appName(bundleID: $0) }
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

    /// What the tap is given: the file's settings, with Hyper off while paused.
    private var tapSettings: HyperSettings {
        var settings = keys.hyper
        if paused { settings.enabled = false }
        return settings
    }

    /// Brings the tap and the mapping in line with the permissions, the file
    /// and Pause. The tap runs for Hyper, for the right Option's characters or
    /// for the launcher's key (Pause Hyper stops Hyper, not those); the Caps Lock mapping only for Hyper.
    private func reconcile() {
        let settings = tapSettings
        let ready = loaded && keysKnown && permissions.granted && !tapGaveUp
        let want = ready && (settings.enabled || settings.rightOption == .characters || settings.launcher != .none)
        let wantMapping = want && settings.enabled
        if want {
            // Hyper off or paused while the tap stays: the mapping goes first,
            // so Caps Lock is never F18 with no machine to take it.
            if mapping, !wantMapping {
                HIDMapping.clear()
                mapping = false
            }
            if engine.isRunning {
                if engineSettings != settings || engineLaunchKeys != launchKeys {
                    engine.update(settings: settings, launchKeys: launchKeys)
                    engineSettings = settings
                    engineLaunchKeys = launchKeys
                }
            } else if engine.start(settings: settings, launchKeys: launchKeys) {
                engineSettings = settings
                engineLaunchKeys = launchKeys
                if engineLine == Self.cannotStart { engineLine = nil }
            } else {
                engineLine = Self.cannotStart
            }
            if engine.isRunning, wantMapping, !mapping {
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
        // Once Accessibility is granted, and again if the Dock restarted.
        BordersWatcher.shared.ensure()
    }

    static let cannotStart = "Grove Keys can't watch the keyboard yet · grant the permissions, then choose Restart Grove Keys in its menu"

    private func tapKeptStopping() {
        HIDMapping.clear()
        mapping = false
        stopEngine()
        paused = true
        tapGaveUp = true
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
        case .toggleLauncher: LauncherPanel.shared.toggle()
        case .postEscape: break  // posted on the tap thread
        }
    }

    /// The Hyper layer over the screen while Caps Lock is held (spec §7).
    func showCheatSheet() { cheatSheet.show() }
    func hideCheatSheet() { cheatSheet.hide() }
    private lazy var cheatSheet = CheatSheetPanel(model: self)

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
