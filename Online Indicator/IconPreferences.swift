import AppKit

struct IconPreferences {

    // MARK: - Slot

    struct Slot {
        var symbolName: String
        var color: NSColor
        var menuLabel: String
        var menuLabelEnabled: Bool

        static let defaultConnected = Slot(symbolName: "wifi", color: .systemGreen,  menuLabel: "", menuLabelEnabled: false)
        static let defaultBlocked   = Slot(symbolName: "wifi", color: .systemYellow, menuLabel: "", menuLabelEnabled: false)
        static let defaultNoNetwork = Slot(symbolName: "wifi.slash",       color: .systemRed,    menuLabel: "", menuLabelEnabled: false)
    }

    // MARK: - Read

    static func slot(for status: AppState.ConnectionStatus) -> Slot {
        load(key: storageSuffix(for: status), fallback: defaultSlot(for: status))
    }

    static func defaultSlot(for status: AppState.ConnectionStatus) -> Slot {
        switch status {
        case .connected: return .defaultConnected
        case .blocked:   return .defaultBlocked
        case .noNetwork: return .defaultNoNetwork
        }
    }

    // MARK: - Write

    static func save(_ slot: Slot, for status: AppState.ConnectionStatus) {
        let suffix = storageSuffix(for: status)
        UserDefaults.standard.set(slot.symbolName,       forKey: compositeKey(.iconSymbolPrefix,       suffix: suffix))
        UserDefaults.standard.set(slot.menuLabel,        forKey: compositeKey(.iconLabelPrefix,        suffix: suffix))
        UserDefaults.standard.set(slot.menuLabelEnabled, forKey: compositeKey(.iconLabelEnabledPrefix, suffix: suffix))
        saveColor(slot.color, forKey: compositeKey(.iconColorPrefix, suffix: suffix))

        NotificationCenter.default.post(name: .iconPreferencesChanged, object: nil)
    }

    // MARK: - Reset

    static func resetAll() {
        for status in [AppState.ConnectionStatus.connected, .blocked, .noNetwork] {
            let suffix = storageSuffix(for: status)
            UserDefaults.standard.removeObject(forKey: compositeKey(.iconSymbolPrefix,       suffix: suffix))
            UserDefaults.standard.removeObject(forKey: compositeKey(.iconColorPrefix,        suffix: suffix))
            UserDefaults.standard.removeObject(forKey: compositeKey(.iconLabelPrefix,        suffix: suffix))
            UserDefaults.standard.removeObject(forKey: compositeKey(.iconLabelEnabledPrefix, suffix: suffix))
        }
        NotificationCenter.default.post(name: .iconPreferencesChanged, object: nil)
    }

    // MARK: - Helpers

    /// Builds a composite key from a registered prefix and a per-status suffix.
    private static func compositeKey(_ prefix: UserDefaults.Key, suffix: String) -> String {
        "\(prefix.rawValue).\(suffix)"
    }

    private static func storageSuffix(for status: AppState.ConnectionStatus) -> String {
        switch status {
        case .connected: return "connected"
        case .blocked:   return "blocked"
        case .noNetwork: return "noNetwork"
        }
    }

    private static func load(key: String, fallback: Slot) -> Slot {
        let symbol  = UserDefaults.standard.string(forKey: compositeKey(.iconSymbolPrefix,       suffix: key)) ?? fallback.symbolName
        let label   = UserDefaults.standard.string(forKey: compositeKey(.iconLabelPrefix,        suffix: key)) ?? fallback.menuLabel
        let color   = loadColor(forKey:             compositeKey(.iconColorPrefix,               suffix: key)) ?? fallback.color

        let enabledKey = compositeKey(.iconLabelEnabledPrefix, suffix: key)
        let enabled = UserDefaults.standard.object(forKey: enabledKey) != nil
                      ? UserDefaults.standard.bool(forKey: enabledKey)
                      : fallback.menuLabelEnabled
        return Slot(symbolName: symbol, color: color, menuLabel: label, menuLabelEnabled: enabled)
    }

    private static func saveColor(_ color: NSColor, forKey key: String) {
        let c = color.usingColorSpace(.sRGB) ?? color
        UserDefaults.standard.set(
            [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent],
            forKey: key
        )
    }

    private static func loadColor(forKey key: String) -> NSColor? {
        guard let arr = UserDefaults.standard.array(forKey: key) as? [Double],
              arr.count == 4 else { return nil }
        return NSColor(srgbRed: arr[0], green: arr[1], blue: arr[2], alpha: arr[3])
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let iconPreferencesChanged    = Notification.Name("iconPreferencesChanged")
    static let settingsWindowDidBecomeKey = Notification.Name("settingsWindowDidBecomeKey")
}
