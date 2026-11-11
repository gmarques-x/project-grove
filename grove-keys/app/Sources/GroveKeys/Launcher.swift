import AppKit

@MainActor
enum Launcher {
    /// Opens the app, or brings it forward. False when no app has this bundle ID.
    static func open(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        return true
    }

    /// "Ghostty" for com.mitchellh.ghostty; nil when it isn't installed.
    static func appName(bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?
            .deletingPathExtension().lastPathComponent
    }
}
