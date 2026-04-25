import Foundation
import UserNotifications
import os.log

final class AutoDisconnectNotificationManager {
    static let shared = AutoDisconnectNotificationManager()
    private init() {}

    var appName: String = "VPN"
    var expiredMessage: String = "Free time expired - VPN disconnected"

    private enum NotificationID {
        static let autoDisconnectExpiry = "auto_disconnect_expiry"
    }

    func configure(appName: String, expiredMessage: String) {
        self.appName = appName
        self.expiredMessage = expiredMessage
    }

    func showExpiryNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            guard let self = self else { return }

            if let error = error {
                os_log("Notification permission error: %{public}@", type: .error, error.localizedDescription)
                return
            }

            if granted {
                self.sendNotification()
            } else {
                os_log("Notification permission not granted", type: .info)
            }
        }
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = appName
        content.body = expiredMessage
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: NotificationID.autoDisconnectExpiry,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                os_log("Error showing auto-disconnect notification: %{public}@", type: .error, error.localizedDescription)
            }
        }
    }
}
