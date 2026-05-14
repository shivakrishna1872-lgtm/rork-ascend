import Foundation
import UserNotifications
import UIKit

/// Lightweight wrapper around `UNUserNotificationCenter` for Ascend Life.
/// Handles permission, foreground presentation, badging, and daily reminders.
@MainActor
final class NotificationService: NSObject {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    private let dailyReminderId = "ascend.dailyReminder"
    private let streakReminderId = "ascend.streakReminder"

    override private init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    /// Returns true if the user granted (or has previously granted) authorization.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await UIApplication.shared.registerForRemoteNotifications()
            if granted { scheduleDefaults() }
            return granted
        } catch {
            return false
        }
    }

    var currentStatus: UNAuthorizationStatus {
        get async {
            await center.notificationSettings().authorizationStatus
        }
    }

    // MARK: - Scheduling

    /// Schedules the default daily check-in (8:30am) + evening streak nudge (9:00pm).
    func scheduleDefaults() {
        scheduleDailyReminder(hour: 8, minute: 30,
                              title: "Ready to optimize",
                              body: "Run a quick check-in to keep your streak alive.",
                              id: dailyReminderId)
        scheduleDailyReminder(hour: 21, minute: 0,
                              title: "Close today strong",
                              body: "Log your last meal or capture tonight's scan.",
                              id: streakReminderId)
    }

    func scheduleDailyReminder(hour: Int, minute: Int, title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "ascend.daily"
        content.interruptionLevel = .timeSensitive

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.add(request)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Badge

    func updateBadge(_ count: Int) {
        center.setBadgeCount(max(0, count))
    }
}

extension NotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    /// Show notifications in-app while the user is using Ascend Life.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    /// Forward taps to the rest of the app via NotificationCenter so we can deep-link.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        await MainActor.run {
            NotificationCenter.default.post(name: .ascendNotificationTapped, object: id)
        }
    }
}

extension Notification.Name {
    static let ascendNotificationTapped = Notification.Name("ascend.notificationTapped")
}
