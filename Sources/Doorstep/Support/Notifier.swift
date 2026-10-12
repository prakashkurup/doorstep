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
            if order.signatureRequired == true { content.body += " Signature required." }
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

    /// One reminder per order, 3 days before its return window closes (10 AM).
    func scheduleReturnReminders(for orders: [Order]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("return-") })
            let cal = Calendar.current
            for order in orders {
                guard let returnBy = order.returnBy,
                      let remindDay = cal.date(byAdding: .day, value: -3, to: returnBy),
                      let fireDate = cal.date(bySettingHour: 10, minute: 0, second: 0, of: remindDay),
                      fireDate > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Return window closing"
                let estimate = order.returnByEstimated == true ? " (estimated)" : ""
                content.body = "Last day to return \(order.title) is \(returnBy.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))\(estimate)."
                let trigger = UNCalendarNotificationTrigger(dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate), repeats: false)
                center.add(UNNotificationRequest(identifier: "return-\(order.id)", content: content, trigger: trigger))
            }
        }
    }

    // A menu bar app is always "frontmost" enough to swallow banners unless we opt in.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
