import Foundation
import Testing
@testable import GroveKeysCore

@Suite struct BordersTests {
    @Test func enterHidesAndExitRestores() {
        var machine = BordersMachine()
        #expect(machine.handle(.entered) == .hide)
        #expect(machine.hidden)
        #expect(machine.handle(.exited) == .restore)
        #expect(!machine.hidden)
    }

    @Test func aSecondEnterHidesNothingAgain() {
        var machine = BordersMachine()
        #expect(machine.handle(.entered) == .hide)
        #expect(machine.handle(.entered) == nil)
        #expect(machine.enters == 2)
        #expect(machine.handle(.exited) == .restore)
    }

    /// Grove Keys started mid-overview, or an enter was missed: restoring is harmless.
    @Test func anExitWithoutAnEnterStillRestores() {
        var machine = BordersMachine()
        #expect(machine.handle(.exited) == .restore)
        #expect(!machine.hidden)
    }

    @Test func startingRestoresWhateverAnEarlierRunLeft() {
        var machine = BordersMachine()
        #expect(machine.handle(.started) == .restore)
    }

    @Test func theLastResortRestoresOnlyForTheEnterItWasSetFor() {
        var machine = BordersMachine()
        #expect(machine.handle(.entered) == .hide)
        #expect(machine.handle(.entered) == nil)
        #expect(machine.handle(.timedOut(enter: 1)) == nil)       // a later enter restarted the clock
        #expect(machine.hidden)
        #expect(machine.handle(.timedOut(enter: 2)) == .restore)
        #expect(!machine.hidden)
        // After an exit, the timeout of that enter has nothing to do.
        #expect(machine.handle(.entered) == .hide)
        #expect(machine.handle(.exited) == .restore)
        #expect(machine.handle(.timedOut(enter: 3)) == nil)
    }

    @Test func quittingOrADockRestartRestoresOnlyWhenHidden() {
        var machine = BordersMachine()
        #expect(machine.handle(.shuttingDown) == nil)
        #expect(machine.handle(.dockRestarted) == nil)
        #expect(machine.handle(.entered) == .hide)
        #expect(machine.handle(.shuttingDown) == .restore)
        #expect(machine.handle(.entered) == .hide)
        #expect(machine.handle(.dockRestarted) == .restore)
        #expect(!machine.hidden)
    }

    /// A quick swipe in and out: hide, restore, in that order; the app runs the last.
    @Test func aQuickInAndOutEndsRestored() {
        var machine = BordersMachine()
        let commands = [BordersMachine.Event.entered, .exited, .entered, .exited].compactMap { machine.handle($0) }
        #expect(commands == [.hide, .restore, .hide, .restore])
        #expect(!machine.hidden)
    }

    @Test func hidingChangesTheColoursOnly() {
        #expect(Borders.hideArguments == ["active_color=0x00000000", "inactive_color=0x00000000"])
        #expect(Borders.triggerNotifications.contains("AXSelectedChildrenChanged"))
        #expect(Borders.triggerApps == ["com.apple.dock", "com.apple.WindowManager"])
    }

    @Test func theConfigAndTheBinaryAreFound() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(Borders.config(home: home, environment: [:]).path == "/Users/x/.config/borders/bordersrc")
        #expect(Borders.config(home: home, environment: ["XDG_CONFIG_HOME": "/tmp/c"]).path == "/tmp/c/borders/bordersrc")
        #expect(Borders.binary(environment: ["PATH": "/usr/bin:/usr/local/bin"]) { _ in true } == "/opt/homebrew/bin/borders")
        #expect(Borders.binary(environment: ["PATH": "/usr/bin:/usr/local/bin"]) { $0.hasPrefix("/usr/local") }
                == "/usr/local/bin/borders")
        #expect(Borders.binary(environment: [:]) { _ in false } == nil)
    }

    @Test func anOverviewIsWindowManagersWindowInItsOverviewLayers() {
        // As macOS 27 lists them at rest…
        let rest: [(owner: String, layer: Int)] = [
            ("WindowManager", -2147483603), ("WindowManager", -2147483624), ("borders", 0), ("Dock", 20), ("sketchybar", 25),
        ]
        #expect(!Borders.overviewIsUp(windows: rest))
        // …and with Mission Control up: the Spaces bar, app icons, the shield.
        #expect(Borders.overviewIsUp(windows: rest + [("WindowManager", 14), ("WindowManager", 17), ("WindowManager", 19)]))
        #expect(Borders.overviewIsUp(windows: [("WindowManager", 19)]))
        // Its highlight overlay at layer 0 alone isn't one, nor another app's window there.
        #expect(!Borders.overviewIsUp(windows: [("WindowManager", 0), ("Finder", 19)]))
        #expect(!Borders.overviewIsUp(windows: []))
    }

    @Test func theProbesAreWindowManagersParkedIconWindows() {
        // As macOS 27 lists every window at rest (names left out, as without
        // Screen Recording): parked icon windows are 0 by 0.
        let rest = [
            Borders.Window(id: 11, owner: "WindowManager", layer: -2147483624, onScreen: true, width: 1920, height: 1243),
            Borders.Window(id: 8416, owner: "WindowManager", layer: -2147483603, onScreen: true, width: 1920, height: 1243),
            Borders.Window(id: 29, owner: "WindowManager", layer: 0, onScreen: false, width: 0, height: 0),
            Borders.Window(id: 42, owner: "WindowManager", layer: 0, onScreen: false, width: 0, height: 0),
            Borders.Window(id: 8426, owner: "WindowManager", layer: 0, onScreen: false, width: 0, height: 0),
            Borders.Window(id: 49, owner: "WindowManager", layer: 17, onScreen: false, width: 0, height: 0),
            Borders.Window(id: 8379, owner: "WindowManager", layer: 17, onScreen: false, width: 0, height: 0),
            Borders.Window(id: 8406, owner: "WindowManager", layer: 17, onScreen: false, width: 0, height: 0),
            Borders.Window(id: 8233, owner: "WindowManager", layer: 19, onScreen: false, width: 1920, height: 1243),  // an old shield
            Borders.Window(id: 8224, owner: "WindowManager", layer: 0, onScreen: false, width: 320, height: 24),      // a label
            Borders.Window(id: 900, owner: "sketchybar", layer: 25, onScreen: true, width: 66, height: 82),
        ]
        // Layer 17 first, newest first.
        #expect(Borders.probes(in: rest) == [8406, 8379])
        #expect(Borders.probes(in: []) == [])
        // Only layer 0 ones parked: those.
        #expect(Borders.probes(in: rest.filter { $0.layer != 17 }) == [8426, 42])
        // With an overview up they are on screen: nothing to pick then.
        #expect(Borders.probes(in: rest.map { var w = $0; w.onScreen = true; return w }) == [])
    }
}
