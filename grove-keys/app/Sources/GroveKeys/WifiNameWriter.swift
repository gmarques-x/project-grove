import AppKit
import CoreLocation
import CoreWLAN
import GroveKeysCore
import os

/// Keeps `$GROVE_STATE/wifi-name` current for the Grove bar's Wi-Fi popup
/// (see `WifiName`). macOS hides the network's name from command-line tools
/// and gives it only to an app allowed Location, so this asks for Location
/// once and, when allowed, writes the name on every Wi-Fi change. Location is
/// optional: without it there is no file and the bar says "Wi-Fi". The Mac's
/// position is never asked for.
///
/// Reading the name is a call to another process, so it runs on a queue of
/// its own and never holds up start-up or the main thread. CoreWLAN's events
/// arrive on a thread of its choosing; they only queue a rewrite.
final class WifiNameWriter: NSObject, CLLocationManagerDelegate, CWEventDelegate, @unchecked Sendable {
    static let shared = WifiNameWriter()
    private static let log = Logger(subsystem: "com.projectgrove.keys", category: "wifi-name")

    private let url: URL
    private let queue = DispatchQueue(label: "com.projectgrove.keys.wifi-name", qos: .utility)
    /// Main thread only: made in `start`, where its callbacks then arrive.
    private var location: CLLocationManager?
    /// On `queue` only.
    private var client: CWWiFiClient?
    private var authorized = false
    /// Guards `stopped` and the file, so a rewrite still on the queue can't
    /// put the name back after `stop` removed it.
    private let lock = NSLock()
    private var stopped = false

    private override init() {
        url = WifiName.url(environment: ProcessInfo.processInfo.environment,
                           home: FileManager.default.homeDirectoryForCurrentUser)
        super.init()
    }

    /// Call once, on the main thread. Asks for Location if macOS has never
    /// asked for this app; a name left by a crash is removed until allowed.
    @MainActor
    func start() {
        guard location == nil else { return }
        let manager = CLLocationManager()
        location = manager
        manager.delegate = self  // macOS answers with the current authorization
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        let allowed = Self.allows(manager.authorizationStatus)

        // Events can be missed over sleep; the network is often rejoined a
        // few seconds after waking, hence the second look.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            WifiNameWriter.shared.refresh()
            WifiNameWriter.shared.refresh(after: 10)
        }

        queue.async { [self] in
            let client = CWWiFiClient.shared()
            client.delegate = self
            for event in [CWEventType.ssidDidChange, .linkDidChange, .powerDidChange] {
                do {
                    try client.startMonitoringEvent(with: event)
                } catch {
                    Self.log.error("cannot watch Wi-Fi event \(event.rawValue): \(error.localizedDescription, privacy: .public)")
                }
            }
            self.client = client
            authorized = allowed
            rewrite()
        }
    }

    /// Every exit path: the file goes, so the bar never shows a stale name.
    /// Doesn't wait for the queue (a slow Wi-Fi read must not hold up quitting).
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        try? WifiName.write(nil, to: url)
    }

    private func refresh(after seconds: Double = 0) {
        queue.asyncAfter(deadline: .now() + seconds) { [self] in rewrite() }
    }

    /// macOS reports an allowed app as `.authorizedAlways` (`.authorized` is
    /// its old name). `.authorizedWhenInUse` (4) is iOS's and can't be named
    /// in a macOS build; it is accepted by number in case macOS ever sends it.
    private static func allows(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedAlways || status.rawValue == 4
    }

    /// On `queue`: reads the name (nil when Wi-Fi is off or not joined, or
    /// CoreWLAN has no interface) and writes or removes the file.
    private func rewrite() {
        let ssid = authorized ? client?.interface()?.ssid() : nil
        let contents = WifiName.contents(authorized: authorized, ssid: ssid)
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return }
        do {
            try WifiName.write(contents, to: url)
        } catch {
            Self.log.error("cannot write \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: CLLocationManagerDelegate

    /// On the main thread (where the manager was made): at start, and when
    /// the owner answers the prompt or changes the switch in System Settings.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let allowed = Self.allows(manager.authorizationStatus)
        queue.async { [self] in
            authorized = allowed
            rewrite()
        }
    }

    // MARK: CWEventDelegate (not on the main thread)

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { refresh() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { refresh() }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { refresh() }
}
