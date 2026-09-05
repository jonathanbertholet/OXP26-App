import Foundation
import UserNotifications

enum TalkReminders {
    static let categoryID = "OXP_TALK"
    static let cantMakeItAction = "OXP_CANT_MAKE_IT"

    static func registerCategories() {
        let skip = UNNotificationAction(
            identifier: cantMakeItAction,
            title: "Can't make it",
            options: .destructive
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [skip],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    @MainActor
    static func requestAccess() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func schedule(track: Track, minutesBefore: Int) async {
        guard let startsAt = track.startsAt else { return }
        let fire = startsAt.addingTimeInterval(TimeInterval(-minutesBefore * 60))
        guard fire > .now else { return }

        guard await requestAccess() else { return }

        let content = UNMutableNotificationContent()
        content.title = track.name
        let whereWhen = [track.location, track.timeRangeLabel].compactMap { $0 }.joined(separator: " · ")
        content.body = "Starts in \(minutesBefore) min" + (whereWhen.isEmpty ? "" : " · \(whereWhen)")
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "oxp-talks"
        content.userInfo = ["trackId": track.id]
        content.interruptionLevel = .timeSensitive

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fire
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: track.id),
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel(trackID: Int) {
        let id = identifier(for: trackID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func identifier(for trackID: Int) -> String {
        "oxp.talk.\(trackID)"
    }
}
