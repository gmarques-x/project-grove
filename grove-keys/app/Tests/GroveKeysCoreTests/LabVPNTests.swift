import Foundation
import Testing
@testable import GroveKeysCore

/// `scutil --nc status "grove-lab"`, written by hand (no grove-lab service
/// existed when they were made, and the repo is public): the first line, then
/// the extended status dictionary as scutil prints it. 10.0.0.2 stands in for
/// the tunnel's address; ConnectTime is on the uptime clock.
struct LabVPNTests {
    /// 14:05 UTC on 13 Nov 2026, an hour after the fixture's connection.
    private let now = Date(timeIntervalSince1970: 1_794_578_700)
    private let utc = TimeZone(identifier: "UTC")!

    private func status(_ text: String, uptime: TimeInterval = 90_000) -> LabVPNStatus {
        LabVPNStatus.parse(scutilStatus: text, uptime: uptime, now: now)
    }

    @Test func parsesConnected() throws {
        let parsed = status(try fixture("scutil-connected.txt"))
        // ConnectTime 86400 with 90000 s of uptime: 3600 s ago.
        #expect(parsed == .connected(address: "10.0.0.2", since: now.addingTimeInterval(-3600)))
        #expect(LabVPNStatus.line(for: parsed, timeZone: utc) == "Connected · 10.0.0.2 · since 13:05")
    }

    @Test func parsesDisconnected() throws {
        #expect(status(try fixture("scutil-disconnected.txt")) == .disconnected)
    }

    @Test func connectedWithoutDetails() {
        let parsed = status("Connected\n")
        #expect(parsed == .connected(address: nil, since: nil))
        #expect(LabVPNStatus.line(for: parsed, timeZone: utc) == "Connected")
        #expect(status("Connected") == .connected(address: nil, since: nil))
    }

    @Test(arguments: ["No service\n", "No service", "", "\n", "garbage\nmore", "Invalid\n", "connected\n"])
    func missingServiceIsNotSetUp(_ text: String) {
        #expect(status(text) == .notSetUp)
    }

    @Test func transitional() {
        #expect(status("Connecting\n") == .connecting)
        #expect(status("Disconnecting\nExtended Status <dictionary> {\n  Status : 3\n}\n") == .disconnecting)
        #expect(status("Disconnected\n") == .disconnected)
    }

    @Test func connectTimeOutsideUptimeIsUnknown() throws {
        // A connect time after the uptime (or none that reads) gives no date.
        let text = try fixture("scutil-connected.txt")
        #expect(status(text, uptime: 100) == .connected(address: "10.0.0.2", since: nil))
        let bad = text.replacingOccurrences(of: "ConnectTime : 86400", with: "ConnectTime : soon")
        #expect(status(bad) == .connected(address: "10.0.0.2", since: nil))
        let zero = text.replacingOccurrences(of: "ConnectTime : 86400", with: "ConnectTime : 0")
        #expect(status(zero) == .connected(address: "10.0.0.2", since: nil))
    }

    @Test func onlyTheIPv4AddressCounts() {
        // DestAddresses and other arrays aren't the Mac's address.
        let text = """
            Connected
            Extended Status <dictionary> {
              IPv4 : <dictionary> {
                DestAddresses : <array> {
                  0 : 192.0.2.9
                }
              }
              IPv6 : <dictionary> {
                Addresses : <array> {
                  0 : fd00::2
                }
              }
            }
            """
        #expect(status(text) == .connected(address: nil, since: nil))
    }

    @Test func icons() {
        #expect(LabVPNIcon.icon(for: .notSetUp) == .off)
        #expect(LabVPNIcon.icon(for: .disconnected) == .off)
        #expect(LabVPNIcon.icon(for: .connecting) == .connecting)
        #expect(LabVPNIcon.icon(for: .disconnecting) == .connecting)
        #expect(LabVPNIcon.icon(for: .connected(address: nil, since: nil)) == .on)
        #expect(LabVPNIcon.on.rawValue == "vpn-on")
        #expect(LabVPNIcon.off.rawValue == "vpn-off")
        #expect(LabVPNIcon.connecting.rawValue == "vpn-connecting")
    }

    @Test func lines() {
        let since = now.addingTimeInterval(-3600)
        func line(_ status: LabVPNStatus, _ zone: TimeZone? = nil) -> String {
            LabVPNStatus.line(for: status, timeZone: zone ?? utc)
        }
        #expect(line(.connected(address: "10.0.0.2", since: since)) == "Connected · 10.0.0.2 · since 13:05")
        #expect(line(.connected(address: "10.0.0.2", since: nil)) == "Connected · 10.0.0.2")
        #expect(line(.connected(address: nil, since: since)) == "Connected · since 13:05")
        #expect(line(.connected(address: nil, since: nil)) == "Connected")
        // The Mac's own time zone, 24-hour.
        #expect(line(.connected(address: nil, since: since), TimeZone(identifier: "America/Los_Angeles")!)
                == "Connected · since 05:05")
        #expect(line(.connecting) == "Connecting…")
        #expect(line(.disconnecting) == "Disconnecting…")
        #expect(line(.disconnected) == "Not connected")
        #expect(line(.notSetUp) == "Import warden-air.conf into WireGuard as grove-lab")
    }

    @Test func theSwitch() {
        let connected = LabVPNStatus.connected(address: "10.0.0.2", since: nil)
        // Shown unless there is no service; on while up or coming up.
        #expect(!LabVPNStatus.notSetUp.showsSwitch)
        for status in [connected, .connecting, .disconnecting, .disconnected] { #expect(status.showsSwitch) }
        #expect(connected.switchOn && LabVPNStatus.connecting.switchOn)
        #expect(!LabVPNStatus.disconnected.switchOn && !LabVPNStatus.disconnecting.switchOn)
        #expect(!LabVPNStatus.notSetUp.switchOn)
        // Disabled on the way: a second start or stop would race the first.
        #expect(connected.switchEnabled && LabVPNStatus.disconnected.switchEnabled)
        for status in [LabVPNStatus.connecting, .disconnecting, .notSetUp] { #expect(!status.switchEnabled) }
    }

    @Test func thePendingSwitchWaitsForAReadingAfterTheCommand() {
        var starting = LabVPNPendingSwitch(on: true, from: .disconnected)
        #expect(starting.shown == .connecting)
        #expect(!starting.shown.switchEnabled)
        // While scutil runs, no reading settles it, even a changed one.
        #expect(starting.settle(with: .connecting, reading: 7) == nil)
        starting.changed(afterReading: 7)
        // Reading 7 started before the command returned.
        #expect(starting.settle(with: .connecting, reading: 7) == nil)
        #expect(starting.settle(with: .connecting, reading: 8) == .succeeded)
        #expect(LabVPNPendingSwitch(on: false, from: .connecting).shown == .disconnecting)
    }

    @Test func aReadingStillInTheOldStateDoesNotSettle() {
        // scutil --nc start returns at once: the next reading can still say Disconnected.
        var starting = LabVPNPendingSwitch(on: true, from: .disconnected)
        starting.changed(afterReading: 3)
        #expect(starting.settle(with: .disconnected, reading: 4) == nil)
        #expect(starting.settle(with: .connected(address: "10.0.0.2", since: nil), reading: 5) == .succeeded)
        // Stopping: a connected reading with another connect time is still the old state.
        let up = LabVPNStatus.connected(address: "10.0.0.2", since: Date(timeIntervalSince1970: 1))
        var stopping = LabVPNPendingSwitch(on: false, from: up)
        stopping.changed(afterReading: 0)
        #expect(stopping.settle(with: .connected(address: "10.0.0.2", since: Date(timeIntervalSince1970: 1.001)),
                                reading: 1) == nil)
        #expect(stopping.settle(with: .disconnected, reading: 2) == .succeeded)
    }

    @Test func theCapSettlesAfterThreeReadings() {
        var starting = LabVPNPendingSwitch(on: true, from: .disconnected)
        starting.changed(afterReading: 0)
        #expect(LabVPNPendingSwitch.cap == 3)
        #expect(starting.settle(with: .disconnected, reading: 1) == nil)
        #expect(starting.settle(with: .disconnected, reading: 2) == nil)
        // The third: it didn't start.
        #expect(starting.settle(with: .disconnected, reading: 3) == .failed)
        // A start that ends with no service, or a stop that leaves it up, failed too.
        var gone = LabVPNPendingSwitch(on: true, from: .disconnected)
        gone.changed(afterReading: 0)
        for n in 1...2 { #expect(gone.settle(with: .notSetUp, reading: n) == nil) }
        #expect(gone.settle(with: .notSetUp, reading: 3) == .failed)
        var stopping = LabVPNPendingSwitch(on: false, from: .connected(address: nil, since: nil))
        stopping.changed(afterReading: 0)
        for n in 1...2 { #expect(stopping.settle(with: .connected(address: nil, since: nil), reading: n) == nil) }
        #expect(stopping.settle(with: .connected(address: nil, since: nil), reading: 3) == .failed)
    }

    @Test func theFailureLines() {
        #expect(LabVPNPendingSwitch.failureLine(on: true) == "Didn't start · see WireGuard")
        #expect(LabVPNPendingSwitch.failureLine(on: false) == "Didn't stop · see WireGuard")
    }
}
