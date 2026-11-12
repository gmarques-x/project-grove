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
        #expect(Borders.enterNotifications.count == 3)
        #expect(Borders.exitNotification == "AXExposeExit")
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
}
