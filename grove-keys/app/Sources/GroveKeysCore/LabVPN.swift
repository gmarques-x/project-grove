import Foundation

// The grove-lab VPN pill (spec 2026-11-13-bar-vpn-design): the tunnel is a
// macOS VPN configuration named `grove-lab` (made by the WireGuard app), read
// with `scutil --nc status "grove-lab"`.
//
// scutil prints the status word on the first line, then (when the service
// exists) the extended status dictionary (SCNetworkConnectionCopyExtendedStatus)
// in its `<dictionary> { … }` form:
//   Connected
//   Extended Status <dictionary> {
//     IPv4 : <dictionary> {
//       Addresses : <array> {
//         0 : 10.0.0.2
//       }
//       …
//     }
//     …
//     VPN : <dictionary> {
//       ConnectTime : 86400
//       Status : 2
//     }
//   }
// ConnectTime (in the VPN, IPSec or PPP dictionary) is "the time when the
// connection was established", in seconds of the uptime clock (as
// ProcessInfo.systemUptime counts it). A missing service prints `No service`.

/// The tunnel's state, as the bar and its dropdown show it.
public enum LabVPNStatus: Equatable, Sendable {
    /// No `grove-lab` service (`No service`), or output that can't be read.
    case notSetUp
    case disconnected
    case connecting
    /// The tunnel's IPv4 address and when it connected, when scutil says.
    case connected(address: String?, since: Date?)
    case disconnecting

    /// From `scutil --nc status "grove-lab"`, the connect time placed on the
    /// wall clock by this Mac's uptime now.
    public static func parse(scutilStatus text: String) -> LabVPNStatus {
        parse(scutilStatus: text, uptime: ProcessInfo.processInfo.systemUptime, now: Date())
    }

    /// The same, with the clocks given: `uptime` is the uptime clock's
    /// reading at `now`.
    public static func parse(scutilStatus text: String, uptime: TimeInterval, now: Date) -> LabVPNStatus {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let first = lines.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        switch first {
        case "Connected":
            let details = extended(lines.dropFirst())
            let since = details.connectTime.flatMap { time -> Date? in
                guard time > 0, time <= uptime else { return nil }
                return now.addingTimeInterval(time - uptime)
            }
            return .connected(address: details.address, since: since)
        case "Connecting": return .connecting
        case "Disconnecting": return .disconnecting
        case "Disconnected": return .disconnected
        default: return .notSetUp
        }
    }

    /// The first IPv4 address and the first ConnectTime in the extended
    /// status: each `KEY : <dictionary> {` or `<array> {` opens a level, `}`
    /// closes one, `KEY : VALUE` is a value at the current path.
    private static func extended(_ lines: ArraySlice<Substring>) -> (address: String?, connectTime: TimeInterval?) {
        var path: [String] = []
        var address: String?
        var connectTime: TimeInterval?
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "}" {
                _ = path.popLast()
                continue
            }
            if line.hasSuffix("{") {
                // "IPv4 : <dictionary> {", "Extended Status <dictionary> {".
                let key = line.components(separatedBy: " : ")[0]
                path.append(key.components(separatedBy: " <")[0])
                continue
            }
            let parts = line.components(separatedBy: " : ")
            guard parts.count == 2 else { continue }
            let key = parts[0], value = parts[1].trimmingCharacters(in: .whitespaces)
            if address == nil, path.suffix(2) == ["IPv4", "Addresses"], !value.isEmpty {
                address = value
            }
            if connectTime == nil, key == "ConnectTime", let time = TimeInterval(value) {
                connectTime = time
            }
        }
        return (address, connectTime)
    }

    /// The dropdown's status line: "Connected · 10.0.0.2 · since 14:05" (the
    /// address and the time left out when unknown), "Connecting…",
    /// "Disconnecting…", "Not connected", or how to set it up.
    public static func line(for status: LabVPNStatus, timeZone: TimeZone) -> String {
        switch status {
        case .notSetUp: return "Import warden-air.conf into WireGuard as grove-lab"
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .disconnecting: return "Disconnecting…"
        case .connected(let address, let since):
            var parts = ["Connected"]
            if let address { parts.append(address) }
            if let since { parts.append("since \(clock(since, timeZone: timeZone))") }
            return parts.joined(separator: " · ")
        }
    }

    /// HH:MM, 24-hour, whatever the Mac's region.
    private static func clock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The bar's VPN icon; the raw value is the icon's name in
/// config/sketchybar/icons (`vpn-off-dark.png`…), as the bar's `sb_vpn_icon`
/// names it.
public enum LabVPNIcon: String, Sendable {
    case off = "vpn-off", connecting = "vpn-connecting", on = "vpn-on"

    /// On when connected; connecting while it is connecting or
    /// disconnecting; off otherwise (not set up too).
    public static func icon(for status: LabVPNStatus) -> LabVPNIcon {
        switch status {
        case .connected: return .on
        case .connecting, .disconnecting: return .connecting
        case .notSetUp, .disconnected: return .off
        }
    }
}
