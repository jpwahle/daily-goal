import AppKit
import UserNotifications

/// Periodic "your goal is still open" nudges, on the interval the user picked.
///
/// Two delivery paths, chosen at fire time:
///  - user is at the Mac (recent keyboard/mouse input) → the pill bounces,
///    glows, and un-dims; no notification clutter.
///  - user has been away for a few minutes → a local notification, so the
///    reminder is waiting in Notification Center when they come back.
///
/// Nothing fires once today's goal is completed, or while the pill is being
/// edited. Reminders about an *empty* day invite setting a goal instead.
final class ReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    static let choices: [(title: String, seconds: TimeInterval)] = [
        ("Off", 0),
        ("Every 30 Minutes", 30 * 60),
        ("Every Hour", 60 * 60),
        ("Every 2 Hours", 2 * 60 * 60),
        ("Every 3 Hours", 3 * 60 * 60),
    ]

    private let store: GoalStore
    private unowned let app: AppDelegate
    private var timer: Timer?
    private var authorizationRequested = false

    /// Idle input time after which the user counts as away. Hidden tunable:
    /// `defaults write org.gipplab.dailygoal reminderAwaySeconds -int 60`.
    private var awayAfter: TimeInterval {
        let configured = UserDefaults.standard.double(forKey: "reminderAwaySeconds")
        return configured > 0 ? configured : 180
    }

    /// UNUserNotificationCenter aborts when the process runs outside an .app
    /// bundle (e.g. bare `swift run`), so gate every use on bundle identity.
    private var notificationsUsable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    init(store: GoalStore, app: AppDelegate) {
        self.store = store
        self.app = app
        super.init()
        if notificationsUsable {
            UNUserNotificationCenter.current().delegate = self
        }
        reschedule()
    }

    /// (Re)starts the countdown. Called when the interval setting changes and
    /// whenever the user meaningfully touches the goal, so a nudge never lands
    /// moments after an interaction.
    func reschedule() {
        timer?.invalidate()
        timer = nil
        clearDelivered() // the user just interacted; a stale reminder can go
        let interval = store.reminderInterval
        guard interval > 0 else { return }
        requestAuthorizationIfNeeded()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fire()
        }
        timer?.tolerance = min(60, interval * 0.05)
    }

    private func fire() {
        guard store.reminderInterval > 0, !store.isCompleted, !store.isEditing else { return }
        let idle = secondsSinceLastInput()
        if idle < awayAfter {
            NSLog("reminder: nudging pill (idle %.0fs)", idle)
            clearDelivered() // user is back — retire the away-notification
            app.nudgePill()
        } else {
            NSLog("reminder: user away (idle %.0fs) — delivering notification", idle)
            deliverNotification()
        }
    }

    /// Seconds since the last keyboard/mouse event anywhere in the session.
    private func secondsSinceLastInput() -> TimeInterval {
        let types: [CGEventType] = [
            .keyDown, .flagsChanged, .mouseMoved, .scrollWheel,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged,
        ]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func requestAuthorizationIfNeeded() {
        guard notificationsUsable, !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("reminder: notification authorization failed: %@", "\(error)") }
            else { NSLog("reminder: notification authorization granted=%d", granted ? 1 : 0) }
        }
    }

    private func deliverNotification() {
        guard notificationsUsable else { return }
        let content = UNMutableNotificationContent()
        if store.goal.isEmpty {
            content.title = "What's your one thing today?"
            content.body = "Ten seconds to pick it — the pill is waiting."
        } else {
            content.title = store.goal
            let hoursLeft = Int(store.secondsLeft() / 3600)
            content.body = hoursLeft >= 2
                ? "Still open — about \(hoursLeft) hours left today."
                : "Still open — the day is almost over."
        }
        content.sound = .default
        // Stable identifier: a fresh reminder replaces the previous one
        // instead of stacking up while the user is away.
        let request = UNNotificationRequest(
            identifier: "org.gipplab.dailygoal.reminder", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("reminder: notification delivery failed: %@", "\(error)") }
        }
    }

    /// Removes the delivered reminder from Notification Center. Doing this
    /// whenever the user is demonstrably back keeps the center tidy and lets
    /// the next absence banner again (re-posting a still-delivered identifier
    /// only updates it silently).
    private func clearDelivered() {
        guard notificationsUsable else { return }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["org.gipplab.dailygoal.reminder"])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Clicking the notification surfaces the pill (and starts editing when
    /// there is no goal yet).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.store.goal.isEmpty ? self.app.beginEditing() : self.app.showPanel()
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
