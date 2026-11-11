import AppKit
import GroveKeysCore

/// Does what a row of the Grove menu says, for the pine's menu, the palette
/// and `grovekeys://menu/<id>` alike.
@MainActor
enum MenuRunner {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func run(_ action: GroveMenuAction, title: String) {
        if let command = action.shellCommand(title: title) {
            MenuShell.spawn(command)
            return
        }
        let model = AppModel.shared
        switch action {
        case .run, .present:
            break  // shell commands, run above
        case .open(let text):
            switch OpenTarget(text, home: home) {
            case .link(let link): Links.answer(link)
            case .url(let url): NSWorkspace.shared.open(url)
            case nil: NSLog("Grove Keys: nothing to open in \"%@\"", text)
            }
        case .builtin(.lock): ScreenLock.lock()
        case .builtin(.keys): PointerMenu.shared.show()
        case .builtin(.globalMenu): PointerMenu.shared.showAppMenu()
        case .keys(.accessibility): NSWorkspace.shared.open(Permissions.accessibilitySettings)
        case .keys(.inputMonitoring): NSWorkspace.shared.open(Permissions.inputMonitoringSettings)
        case .keys(.restart): model.restart()
        case .keys(.open):
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        case .keys(.cheatSheet): CheatSearchPanel.shared.toggle()
        case .keys(.pause): model.togglePause()
        }
    }
}

extension MenuShell {
    /// `/bin/zsh -lc <command>`: the login profile gives Homebrew and
    /// `~/.local/bin` (and `environment` gives them when it fails). Nothing
    /// is read from it or shown.
    static func process(_ command: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.environment = environment(
            from: ProcessInfo.processInfo.environment, home: FileManager.default.homeDirectoryForCurrentUser)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }

    /// Starts the command and doesn't wait for it.
    static func spawn(_ command: String) {
        do { try process(command).run() } catch {
            NSLog("Grove Keys: cannot run \"%@\": %@", command, error.localizedDescription)
        }
    }
}

/// The rows' `checked` tests. All run at once, off the main thread, which
/// never waits for them: a ✓ is reported when (and if) its test succeeds.
enum CheckedTests {
    /// A test still running after this long is stopped and counts as failed.
    static let limit: TimeInterval = 0.5

    /// `passed` gets the id of each test that exits 0 in time, on the main
    /// thread, in every run loop mode: an open menu is in its own.
    static func run(_ tests: [(id: String, command: String)], passed: @escaping @MainActor (String) -> Void) {
        for test in tests {
            let id = test.id
            let process = MenuShell.process(test.command)
            process.terminationHandler = { process in
                guard process.terminationReason == .exit, process.terminationStatus == 0 else { return }
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    MainActor.assumeIsolated { passed(id) }
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }
            guard (try? process.run()) != nil else { continue }
            DispatchQueue.global().asyncAfter(deadline: .now() + limit) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// The Lock row: the lock screen at once, as ⌃⌘Q.
enum ScreenLock {
    /// `SACLockScreenImmediate` is private (login.framework), so it is looked
    /// up at run time; without it, or when it fails, the display sleeps
    /// instead, which locks when a password is required on wake.
    static func lock() {
        typealias LockNow = @convention(c) () -> Int32
        let framework = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(framework, RTLD_LAZY), let symbol = dlsym(handle, "SACLockScreenImmediate"),
           unsafeBitCast(symbol, to: LockNow.self)() == 0 {
            return
        }
        let pmset = Process()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["displaysleepnow"]
        do { try pmset.run() } catch {
            NSLog("Grove Keys: cannot lock the screen: %@", error.localizedDescription)
        }
    }
}
