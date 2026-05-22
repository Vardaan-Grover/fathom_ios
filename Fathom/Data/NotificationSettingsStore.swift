import Foundation
import UserNotifications

// MARK: - NotificationSettingsStore
//
// Manages the daily reading reminder: a persisted enable flag + time,
// and the underlying UNUserNotificationCenter scheduling.

@MainActor
final class NotificationSettingsStore {
    static let shared = NotificationSettingsStore()

    static let didChangeNotification = Notification.Name("NotificationSettingsStore.didChange")

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults

    private let enabledKey = "fathom.notifications.dailyReadingEnabled"
    private let hourKey    = "fathom.notifications.dailyReadingHour"
    private let minuteKey  = "fathom.notifications.dailyReadingMinute"

    private let identifier = "fathom.dailyReadingReminder"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Default time = 8:00 PM if never set.
        if defaults.object(forKey: hourKey) == nil {
            defaults.set(20, forKey: hourKey)
            defaults.set(0,  forKey: minuteKey)
        }
    }

    // MARK: - State

    /// Whether the daily reminder is enabled.
    var isEnabled: Bool {
        defaults.bool(forKey: enabledKey)
    }

    /// The local time-of-day the reminder fires at.
    var time: DateComponents {
        var comps = DateComponents()
        comps.hour = defaults.integer(forKey: hourKey)
        comps.minute = defaults.integer(forKey: minuteKey)
        return comps
    }

    /// Convenience wrapper as a Date today at `time`.
    var timeAsDate: Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = time.hour
        comps.minute = time.minute
        return cal.date(from: comps) ?? Date()
    }

    // MARK: - Authorization

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            AppLogger.log(tag: "Notifications", "Auth request failed: \(error)")
            return false
        }
    }

    // MARK: - Mutations

    /// Enable / disable the daily reminder. Requests permission if needed.
    /// Returns `true` if the reminder is now active.
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        if on {
            let status = await authorizationStatus()
            if status == .notDetermined {
                let granted = await requestAuthorization()
                if !granted {
                    defaults.set(false, forKey: enabledKey)
                    notifyChange()
                    return false
                }
            } else if status == .denied {
                // Caller should direct the user to Settings; we just record
                // the desired state and skip scheduling.
                defaults.set(false, forKey: enabledKey)
                notifyChange()
                return false
            }
            defaults.set(true, forKey: enabledKey)
            await schedule()
            notifyChange()
            return true
        } else {
            defaults.set(false, forKey: enabledKey)
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            notifyChange()
            return false
        }
    }

    func setTime(hour: Int, minute: Int) async {
        defaults.set(hour, forKey: hourKey)
        defaults.set(minute, forKey: minuteKey)
        if isEnabled {
            await schedule()
        }
        notifyChange()
    }

    // MARK: - Scheduling

    private func schedule() async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Time to Read"
        content.body  = "Pick up where you left off in Fathom."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let req = UNNotificationRequest(identifier: identifier,
                                        content: content,
                                        trigger: trigger)

        do {
            try await center.add(req)
            AppLogger.log(tag: "Notifications", "Daily reminder scheduled at \(time)")
        } catch {
            AppLogger.log(tag: "Notifications", "Schedule failed: \(error)")
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
