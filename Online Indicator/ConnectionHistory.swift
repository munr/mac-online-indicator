import Foundation

/// Remembers the most recent outage (any stretch where the status wasn't `.connected`).
/// ponytail: last outage only and in memory, so it resets on quit; keep a persisted list if a full history view is wanted.
final class ConnectionHistory {

    /// Outages shorter than this are ignored: they're usually the launch race or a flapping link.
    static let minimumOutage: TimeInterval = 10

    private var outageStart: Date?
    private var lastOutage: (start: Date, end: Date)?

    /// Feed every status result; repeated identical statuses are harmless.
    func record(_ status: AppState.ConnectionStatus, at date: Date = Date()) {
        if status == .connected {
            if let start = outageStart, date.timeIntervalSince(start) >= Self.minimumOutage {
                lastOutage = (start, date)
            }
            outageStart = nil
        } else if outageStart == nil {
            outageStart = date
        }
    }

    /// Menu text: "Since 14:02" while offline, "14:02 · 3 min" after recovery, nil if none yet.
    func summary() -> String? {
        if let start = outageStart { return "Since \(Self.time(start))" }
        guard let outage = lastOutage else { return nil }
        return "\(Self.time(outage.start)) · \(Self.duration(outage.end.timeIntervalSince(outage.start)))"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private static func time(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}
