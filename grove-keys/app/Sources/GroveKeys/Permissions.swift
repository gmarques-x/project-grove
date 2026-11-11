import ApplicationServices
import CoreGraphics
import Foundation

struct PermissionStatus: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
    var granted: Bool { accessibility && inputMonitoring }
}

enum Permissions {
    static let accessibilitySettings =
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
    static let inputMonitoringSettings =
        URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent")!

    static func current() -> PermissionStatus {
        PermissionStatus(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess())
    }

    /// Asks macOS once, which also lists the app in both Privacy panes.
    static func request(_ status: PermissionStatus) {
        if !status.inputMonitoring { _ = CGRequestListenEventAccess() }
        if !status.accessibility {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }
}
