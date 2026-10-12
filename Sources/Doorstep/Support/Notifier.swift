import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asked once Gmail is connected, when the reason for notifications is obvious.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts only for the transitions worth an interruption.
    func announce(_ order: Order) {
        let content = UNMutableNotificationContent()
        switch order.status {
        case .outForDelivery:
            content.title = "Out for delivery"
            let by = order.expectedByTime.map { " \($0)" } ?? ""
            content.body = "\(order.title) arrives today\(by)."
        case .delivered:
            content.title = "Delivered"
            content.body = "\(order.title) was delivered."
        case .delayed:
            content.title = "Delivery delayed"
            if let eta = order.expectedDelivery {
                content.body = "\(order.title) is now expected \(eta.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))."
            } else {
                content.body = "\(order.title) is running late."
            }
        default:
            return
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(order.id)-\(order.status.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // A menu bar app is always "frontmost" enough to swallow banners unless we opt in.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
