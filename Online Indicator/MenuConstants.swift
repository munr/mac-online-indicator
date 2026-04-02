import AppKit

// Placeholder strings used throughout the menu for missing / not-yet-loaded values.
let menuNoValue     = "—"
let menuUnavailable = "Unavailable"

enum MenuLayout {
    static let menuWidth:              CGFloat = 300
    static let heroIconSize:           CGFloat = 56
    static let heroLeadingPadding:     CGFloat = 16
    static let ringStrokeWidth:        CGFloat = 2.5
    static let highlightCornerRadius:  CGFloat = 4
    static let rowHeight:              CGFloat = 30
}

/// RSSI thresholds (dBm) and mapping constants for the WiFi strength ring.
/// Ring fraction = (rssi + rssiOffset) / rssiRange, clamped to 0…1.
/// Maps −90 dBm (unusable) → 0.0 and −50 dBm (excellent) → 1.0.
enum WiFiThreshold {
    static let excellent:   Int    = -60
    static let good:        Int    = -70
    static let fair:        Int    = -80
    static let rssiOffset:  Double = 90
    static let rssiRange:   Double = 40
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
