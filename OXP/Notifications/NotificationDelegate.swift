import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    var onOpenTrack: (@MainActor (Int) -> Void)?
    var onDropTrack: (@MainActor (Int) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let trackID = info["trackId"] as? Int
        guard let trackID else { return }
        let skipped = response.actionIdentifier == TalkReminders.cantMakeItAction
        let open = onOpenTrack
        let drop = onDropTrack
        await MainActor.run {
            if skipped {
                drop?(trackID)
            } else {
                open?(trackID)
            }
        }
    }
}
