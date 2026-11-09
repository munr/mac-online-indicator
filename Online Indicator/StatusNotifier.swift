import UserNotifications

/// Posts a local notification when connectivity or VPN state changes.
/// Opt-in via `UserDefaults.Key.notifyOnStatusChange`.
enum StatusNotifier {

    static var isEnabled: Bool { UserDefaults.standard.bool(for: .notifyOnStatusChange) }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func statusChanged(to status: AppState.ConnectionStatus) {
        switch status {
        case .connected: post("Back online", "Internet connection restored.")
        case .blocked:   post("No internet access", "Connected to a network, but outbound requests are failing.")
        case .noNetwork: post("Network lost", "No network connection.")
        }
    }

    static func vpnDropped() {
        post("VPN disconnected", "Your traffic is no longer going through the VPN.")
    }

    private static func post(_ title: String, _ body: String) {
        guard isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

/// Tells real status changes from repeats. The first result after launch is a baseline, not a change.
struct StatusChangeTracker {

    private var last: AppState.ConnectionStatus?

    mutating func isChange(to status: AppState.ConnectionStatus) -> Bool {
        defer { last = status }
        guard let last else { return false }
        return last != status
    }
}
