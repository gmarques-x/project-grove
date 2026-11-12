import Foundation
import GroveKeysCore
import UserNotifications

/// Says a `MenuFailure` where it can be seen: a notification ("Grove", one
/// line), since these happen with no Grove window in front (macOS has no
/// toast; outside the app the skill's answer is UserNotifications). Always
/// logged too.
///
/// Permission is asked for at the first failure, never at launch; if it is
/// refused, the log is all there is. Run bare from `.build` there is no
/// bundle, and the notification centre can't be used at all.
enum FailureNotice {
    static func show(_ failure: MenuFailure) {
        let body = failure.body
        NSLog("Grove Keys: %@", body)
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = Presenter.shared
        // Asks the first time only; afterwards it answers with what was chosen.
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = MenuFailure.title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Shown as a banner even when Grove Keys is the app in front (its
    /// launcher panel was just used): by default macOS shows none then.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
        static let shared = Presenter()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler:
                                        @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner, .list])
        }
    }
}
