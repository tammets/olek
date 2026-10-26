import Foundation
import OlekCore
import UserNotifications

/// Posts reminder notifications with actions and routes the chosen action back to the controller.
@MainActor
final class NotificationService: NSObject {
    enum Action: String {
        case continueWorking, stopNow, stopAtIdleStart, remindLater
        case startNow, startAtActiveStart, startAtTypedTime, notWorking
    }

    private enum Category {
        static let idle = "olek.idle"
        static let active = "olek.active"
    }

    private let center = UNUserNotificationCenter.current()
    var onAction: ((Action, String?) -> Void)?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        center.delegate = self
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        // Only the status enum leaves the callback; older SDKs mark the settings object
        // as non-Sendable, so it must not cross into the main actor.
        authorization = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        guard authorization == .notDetermined else { return }
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
    }

    func show(_ reminder: Reminder) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch reminder {
        case let .idleWhileTracking(since):
            let time = TimeFormat.hourMinute(since)
            content.title = String(localized: "Still working?")
            content.body = String(localized: "You haven't used your Mac since \(time). Tracking is still running.")
            content.categoryIdentifier = Category.idle
            registerCategories(idleStart: time, activeStart: nil)
        case let .activeWhileStopped(since):
            let time = TimeFormat.hourMinute(since)
            content.title = String(localized: "Start tracking?")
            content.body = String(localized: "You've been using your Mac since \(time) while tracking is stopped.")
            content.categoryIdentifier = Category.active
            registerCategories(idleStart: nil, activeStart: time)
        }
        let request = UNNotificationRequest(identifier: identifier(reminder.kind), content: content, trigger: nil)
        center.add(request)
    }

    func clear(_ kind: ReminderEngine.Kind) {
        center.removeDeliveredNotifications(withIdentifiers: [identifier(kind)])
    }

    private func identifier(_ kind: ReminderEngine.Kind) -> String {
        kind == .idle ? Category.idle : Category.active
    }

    // Action titles are fixed per category, so categories are re-registered with the
    // concrete time before each notification ("Stop at 10:15").
    private var lastIdleStart = "--:--"
    private var lastActiveStart = "--:--"

    private func registerCategories(idleStart: String?, activeStart: String?) {
        if let idleStart { lastIdleStart = idleStart }
        if let activeStart { lastActiveStart = activeStart }
        let idle = UNNotificationCategory(
            identifier: Category.idle,
            actions: [
                UNNotificationAction(identifier: Action.continueWorking.rawValue, title: String(localized: "Continue Working")),
                UNNotificationAction(identifier: Action.stopAtIdleStart.rawValue, title: String(localized: "Stop at \(lastIdleStart)")),
                UNNotificationAction(identifier: Action.stopNow.rawValue, title: String(localized: "Stop Now")),
                UNNotificationAction(identifier: Action.remindLater.rawValue, title: String(localized: "Remind Me Later")),
            ],
            intentIdentifiers: []
        )
        let active = UNNotificationCategory(
            identifier: Category.active,
            actions: [
                UNNotificationAction(identifier: Action.startAtActiveStart.rawValue, title: String(localized: "Start at \(lastActiveStart)")),
                UNNotificationAction(identifier: Action.startNow.rawValue, title: String(localized: "Start Now")),
                UNTextInputNotificationAction(
                    identifier: Action.startAtTypedTime.rawValue,
                    title: String(localized: "Choose Time…"),
                    textInputButtonTitle: String(localized: "Start"),
                    textInputPlaceholder: String(localized: "e.g. 9:15")
                ),
                UNNotificationAction(identifier: Action.notWorking.rawValue, title: String(localized: "Not Working")),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([idle, active])
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Olek has no foreground window most of the time; show banners regardless.
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await MainActor.run {
            guard let action = Action(rawValue: identifier) else { return }
            onAction?(action, text)
        }
    }
}
