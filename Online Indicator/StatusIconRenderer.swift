import AppKit

/// Pure, stateless helper that produces a fully-rendered menu bar icon output from
/// a given connection status and the current user icon preferences.
struct StatusIconRenderer {

    struct Output {
        /// The tinted SF Symbol image. Non-nil unless the symbol name is invalid.
        let tintedImage: NSImage
        /// Non-nil when the user has enabled a text label alongside the icon.
        let attributedLabel: NSAttributedString?
        let toolTip: String
        let accessibilityLabel: String
    }

    static func render(
        for status: AppState.ConnectionStatus,
        wifiName: String? = nil
    ) -> Output? {
        let pref = IconPreferences.slot(for: status)

        let symbolName: String
        let color: NSColor

        if NSImage(systemSymbolName: pref.symbolName, accessibilityDescription: nil) != nil {
            symbolName = pref.symbolName
            color      = pref.color
        } else {
            switch status {
            case .connected: symbolName = "wifi";       color = .systemGreen
            case .blocked:   symbolName = "wifi";       color = .systemYellow
            case .noNetwork: symbolName = "wifi.slash"; color = .systemRed
            }
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let tinted = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }

        let toolTip: String
        let a11yLabel: String
        switch status {
        case .connected:
            let network = wifiName.map { " — Wi-Fi: \($0)" } ?? ""
            toolTip   = "Online Indicator: Connected\(network)"
            a11yLabel = "Online Indicator: Connected"
        case .blocked:
            toolTip   = "Online Indicator: Blocked — Network present but no internet access"
            a11yLabel = "Online Indicator: Blocked"
        case .noNetwork:
            toolTip   = "Online Indicator: No Network — No active network interface"
            a11yLabel = "Online Indicator: No Network"
        }

        let rawLabel  = String(pref.menuLabel.prefix(15)).trimmingCharacters(in: .whitespaces)
        let showLabel = pref.menuLabelEnabled && !rawLabel.isEmpty

        var attributedLabel: NSAttributedString?
        if showLabel {
            let font     = NSFont.menuBarFont(ofSize: 12)
            let iconSize = tinted.size

            let attachment = NSTextAttachment()
            attachment.image  = tinted
            attachment.bounds = NSRect(
                x: 0,
                y: (font.capHeight - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )

            let textAttrs: [NSAttributedString.Key: Any] = [
                .font:            font,
                .foregroundColor: NSColor.labelColor,
                .baselineOffset:  0
            ]

            let full = NSMutableAttributedString()
            full.append(NSAttributedString(attachment: attachment))
            full.append(NSAttributedString(string: " " + rawLabel, attributes: textAttrs))
            attributedLabel = full
        }

        return Output(
            tintedImage:        tinted,
            attributedLabel:    attributedLabel,
            toolTip:            toolTip,
            accessibilityLabel: a11yLabel
        )
    }
}
