import AppKit
import UserNotifications

/// Posts a banner when a session finishes or starts waiting. Clicking it opens the session.
@MainActor
enum Notifier {
    static func setUp() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            log.info("notifications: granted=\(granted)")
            Task { @MainActor in refresh() }
        }
    }

    /// Updates `Store.notificationsAllowed`, so the popover can say when banners are off.
    static func refresh() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let allowed = status == .authorized || status == .provisional
            log.info("notifications: status=\(status.rawValue)")
            Task { @MainActor in Store.shared.notificationsAllowed = allowed }
        }
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=dev.lookout.Lookout")!)
    }

    static func waiting(_ session: Session) {
        guard UserDefaults.standard.bool(forKey: Keys.notifyWaiting) else { return }
        post(session, title: "\(session.agent.name) needs you")
    }

    /// `turn` is how long it ran, when Lookout saw it start.
    static func done(_ session: Session, turn: TimeInterval?) {
        guard UserDefaults.standard.bool(forKey: Keys.notifyDone), session.detail != "Went quiet" else { return }
        if let turn, turn < Double(UserDefaults.standard.integer(forKey: Keys.minTurn)) { return }
        let verb = switch session.detail {
        case "Stopped": "stopped"
        case "Error": "hit an error"
        default: "is done"
        }
        post(session, title: "\(session.agent.name) \(verb)")
    }

    private static func post(_ session: Session, title: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = [session.project, session.phase == .waiting ? session.detail : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        content.body = session.title
        content.userInfo = ["session": session.id]
        // One banner per session: a newer one replaces the last.
        content.threadIdentifier = session.id
        if UserDefaults.standard.bool(forKey: Keys.sound) { content.sound = .default }
        let request = UNNotificationRequest(identifier: session.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationDelegate()

    /// Lookout is always "active" as a menu bar app, so ask for the banner explicitly.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["session"] as? String
        Task { @MainActor in
            if let id { Store.shared.open(id) }
        }
        completionHandler()
    }
}
