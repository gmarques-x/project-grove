import Foundation

/// How the Mac is online, as the Wi-Fi panel's header says it.
public enum WifiLink: Equatable, Sendable {
    /// Through Wi-Fi; the name is nil when macOS doesn't give it (Location
    /// not allowed).
    case wifi(name: String?)
    case ethernet
    /// Through a tunnel; its service's name when known.
    case vpn(name: String?)
    case offline(wifiOn: Bool)

    /// What the Mac reports, read by the panel's model.
    public struct Facts: Equatable, Sendable {
        /// The interface the default route goes through; nil when offline.
        public var primaryInterface: String?
        /// The Wi-Fi interface ("en0"); nil on a Mac without Wi-Fi.
        public var wifiInterface: String?
        public var wifiOn: Bool
        public var wifiName: String?
        /// The primary service's name (a tunnel's: "Grove VPN").
        public var serviceName: String?

        public init(primaryInterface: String?, wifiInterface: String?, wifiOn: Bool, wifiName: String?,
                    serviceName: String?) {
            self.primaryInterface = primaryInterface
            self.wifiInterface = wifiInterface
            self.wifiOn = wifiOn
            self.wifiName = wifiName
            self.serviceName = serviceName
        }
    }

    public init(_ facts: Facts) {
        guard let primary = facts.primaryInterface, !primary.isEmpty else {
            self = .offline(wifiOn: facts.wifiOn)
            return
        }
        if Self.isTunnel(primary) {
            self = .vpn(name: Self.clean(facts.serviceName))
        } else if primary == facts.wifiInterface {
            self = .wifi(name: Self.clean(facts.wifiName))
        } else {
            self = .ethernet
        }
    }

    /// A tunnel's interface: utun3, ipsec0, ppp0 (and tun/tap devices).
    public static func isTunnel(_ interface: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap"].contains { prefix in
            interface.hasPrefix(prefix) && interface.dropFirst(prefix.count).allSatisfy(\.isNumber)
                && interface.count > prefix.count
        }
    }

    private static func clean(_ name: String?) -> String? {
        WifiName.sanitize(name)
    }

    /// The header's title.
    public var title: String {
        switch self {
        case .wifi(let name): return name ?? "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn(let name): return name.map { "VPN · \($0)" } ?? "VPN"
        case .offline: return "Offline"
        }
    }

    /// Under the title when offline.
    public var note: String? {
        guard case .offline(let wifiOn) = self else { return nil }
        return wifiOn ? "Not connected" : "Wi-Fi is off"
    }

    public var isOnline: Bool {
        if case .offline = self { return false }
        return true
    }

    /// The footer: Wi-Fi's own pane, or Network's for a cable or a tunnel.
    public var settings: (title: String, url: String) {
        switch self {
        case .wifi, .offline:
            return ("Wi-Fi Settings…", "x-apple.systempreferences:com.apple.wifi-settings-extension")
        case .ethernet, .vpn:
            return ("Network Settings…", "x-apple.systempreferences:com.apple.Network-Settings.extension")
        }
    }

    /// Which network this is, for "a speed test's result belongs to the
    /// network it was measured on": the kind, the name and the router.
    public func identity(router: String?) -> String {
        let kind: String
        switch self {
        case .wifi(let name): kind = "wifi:\(name ?? "")"
        case .ethernet: kind = "ethernet"
        case .vpn(let name): kind = "vpn:\(name ?? "")"
        case .offline: return "offline"
        }
        return kind + "|" + (router ?? "")
    }
}

/// An address row of the Wi-Fi panel (IP, Router, DNS): what it shows and
/// what a click copies.
public struct WifiAddress: Equatable, Sendable {
    /// "192.0.2.1", or the first of several.
    public var shown: String
    /// "+2" when there are more.
    public var more: String?
    /// Every value, one a line.
    public var copied: String

    /// Nil when there is no value. Repeats are dropped (macOS lists a DNS
    /// server once per resolver), the order kept.
    public init?(_ values: [String]) {
        var seen = Set<String>()
        let unique = values.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard let first = unique.first else { return nil }
        shown = first
        more = unique.count > 1 ? "+\(unique.count - 1)" : nil
        copied = unique.joined(separator: "\n")
    }
}
