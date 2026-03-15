import AppKit
import CoreWLAN

/// Builds and manages the status bar NSMenu, including dynamic IP address rows
/// and the Known Networks panel. Menu item actions are handled here as @objc
/// targets; higher-level actions (open settings, quit, show popover) are
/// forwarded via callbacks set by AppDelegate.
final class MenuBuilder: NSObject {

    private(set) var menu: NSMenu!

    private var wifiMenuItem:    NSMenuItem?
    private var ipv4MenuItem:    NSMenuItem?
    private var ipv6MenuItem:    NSMenuItem?
    private var gatewayMenuItem: NSMenuItem?
    private var dnsMenuItem:     NSMenuItem?

    private(set) var lastIPv4:       String?
    private(set) var lastIPv6:       String?
    private(set) var lastGateway:    String?
    private(set) var lastDNSServers: [String] = []

    private let knownNetworksTag = 900
    
    private var shouldShowKnownNetworks: Bool {
        UserDefaults.standard.bool(for: .showKnownNetworks, default: true)
    }

    // MARK: - Callbacks (set by AppDelegate after init)

    var onCopyIPv4:    ((String) -> Void)?
    var onCopyIPv6:    ((String) -> Void)?
    var onCopyGateway: ((String) -> Void)?
    var onCopyDNS:     ((String) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    // MARK: - Build

    func build() -> NSMenu {
        let m = NSMenu()
        m.minimumWidth = 260
        m.delegate     = nil  // NSMenuDelegate is handled by AppDelegate

        let header = MenuHeaderView(frame: NSRect(x: 0, y: 0, width: 260, height: 28))
        let headerItem = NSMenuItem()
        headerItem.view      = header
        headerItem.isEnabled = false
        m.addItem(headerItem)

        m.addItem(.separator())

        let wifiItem = NSMenuItem(title: "", action: #selector(openWiFiSettings), keyEquivalent: "")
        wifiItem.target          = self
        wifiItem.toolTip         = "Click to open Wi-Fi Settings"
        wifiItem.attributedTitle = ipAttributedString(label: "WiFi", value: "Loading…", available: false)
        wifiMenuItem = wifiItem
        m.addItem(wifiItem)

        let ipv4Item = NSMenuItem(title: "", action: #selector(copyIPv4), keyEquivalent: "")
        ipv4Item.target          = self
        ipv4Item.toolTip         = "Click to copy"
        ipv4Item.attributedTitle = ipAttributedString(label: "IPv4", value: "Loading…", available: false)
        ipv4MenuItem = ipv4Item
        m.addItem(ipv4Item)

        let ipv6Item = NSMenuItem(title: "", action: #selector(copyIPv6), keyEquivalent: "")
        ipv6Item.target          = self
        ipv6Item.toolTip         = "Click to copy"
        ipv6Item.attributedTitle = ipAttributedString(label: "IPv6", value: "Loading…", available: false)
        ipv6MenuItem = ipv6Item
        m.addItem(ipv6Item)

        m.addItem(.separator())

        let gatewayItem = NSMenuItem(title: "", action: #selector(copyGateway), keyEquivalent: "")
        gatewayItem.target          = self
        gatewayItem.toolTip         = "Click to copy"
        gatewayItem.attributedTitle = ipAttributedString(label: "GW  ", value: "Loading…", available: false)
        gatewayMenuItem = gatewayItem
        m.addItem(gatewayItem)

        let dnsItem = NSMenuItem(title: "", action: #selector(copyDNS), keyEquivalent: "")
        dnsItem.target          = self
        dnsItem.toolTip         = "Click to copy"
        dnsItem.attributedTitle = ipAttributedString(label: "DNS ", value: "Loading…", available: false)
        dnsMenuItem = dnsItem
        m.addItem(dnsItem)

        m.addItem(.separator())

        // Known Networks items are inserted dynamically here on each menu open.
        // A tagged separator marks the insertion anchor.
        let anchor = NSMenuItem.separator()
        anchor.tag = knownNetworksTag
        m.addItem(anchor)

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(handleSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsItem.image  = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        m.addItem(settingsItem)

        m.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(AppInfo.appName)", action: #selector(handleQuit), keyEquivalent: "")
        quitItem.target = self
        quitItem.image  = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        m.addItem(quitItem)

        menu = m
        return m
    }

    // MARK: - Dynamic Address Update

    func updateAddresses(_ addresses: IPAddressProvider.Addresses) {
        lastIPv4       = addresses.ipv4
        lastIPv6       = addresses.ipv6
        lastGateway    = addresses.gateway
        lastDNSServers = addresses.dnsServers

        wifiMenuItem?.attributedTitle = ipAttributedString(
            label: "WiFi",
            value: addresses.wifiName ?? "Unavailable",
            available: addresses.wifiName != nil
        )
        ipv4MenuItem?.attributedTitle = ipAttributedString(
            label: "IPv4",
            value: addresses.ipv4 ?? "Unavailable",
            available: addresses.ipv4 != nil
        )
        ipv6MenuItem?.attributedTitle = ipAttributedString(
            label: "IPv6",
            value: addresses.ipv6 ?? "Unavailable",
            available: addresses.ipv6 != nil
        )
        gatewayMenuItem?.attributedTitle = ipAttributedString(
            label: "GW  ",
            value: addresses.gateway ?? "Unavailable",
            available: addresses.gateway != nil
        )
        let dnsValue = addresses.dnsServers.isEmpty ? "Unavailable" : addresses.dnsServers.joined(separator: ", ")
        dnsMenuItem?.attributedTitle = ipAttributedString(
            label: "DNS ",
            value: dnsValue,
            available: !addresses.dnsServers.isEmpty
        )

        refreshKnownNetworks(currentSSID: addresses.wifiName)
    }

    // MARK: - Known Networks

    private func refreshKnownNetworks(currentSSID: String?) {
        guard let menu else { return }

        // Remove previously inserted dynamic items (identified by tag)
        while let old = menu.items.first(where: { $0.tag == knownNetworksTag + 1 }) {
            menu.removeItem(old)
        }
        
        guard shouldShowKnownNetworks else { return }

        guard let anchorIndex = menu.items.firstIndex(where: { $0.tag == knownNetworksTag }) else { return }

        guard let iface    = CWWiFiClient.shared().interface(),
              let config   = iface.configuration(),
              let profiles = config.networkProfiles.array as? [CWNetworkProfile],
              !profiles.isEmpty else { return }

        let nearbySSIDs: Set<String>
        if let cached = iface.cachedScanResults() {
            nearbySSIDs = Set(cached.compactMap { $0.ssid })
        } else {
            nearbySSIDs = []
        }

        let visibleProfiles = profiles.filter { profile in
            guard let ssid = profile.ssid else { return false }
            if let currentSSID, ssid == currentSSID { return true }
            return nearbySSIDs.contains(ssid)
        }

        guard !visibleProfiles.isEmpty else { return }

        var insertionIndex = anchorIndex

        let headerLabel = NSTextField(labelWithString: "Known Networks")
        headerLabel.font      = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.sizeToFit()
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: headerLabel.frame.height + 8))
        headerLabel.frame.origin = NSPoint(x: 14, y: 4)
        headerView.addSubview(headerLabel)
        let headerItem = NSMenuItem()
        headerItem.view      = headerView
        headerItem.isEnabled = false
        headerItem.tag       = knownNetworksTag + 1
        menu.insertItem(headerItem, at: insertionIndex)
        insertionIndex += 1

        for profile in visibleProfiles {
            guard let ssid = profile.ssid else { continue }

            let isConnected = currentSSID != nil && ssid == currentSSID
            let isSecured   = profile.security != .none

            let item = NSMenuItem(title: ssid, action: #selector(openWiFiSettings), keyEquivalent: "")
            item.target = self
            item.tag    = knownNetworksTag + 1

            let wifiSymbol = isConnected ? "wifi.circle.fill" : "wifi"
            let wifiConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
                .applying(.init(paletteColors: isConnected ? [.white, .systemBlue] : [.secondaryLabelColor]))
            item.image = NSImage(systemSymbolName: wifiSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(wifiConfig)

            // Omitting .foregroundColor lets AppKit handle white-on-selection automatically.
            let nameFont = NSFont.systemFont(ofSize: 13, weight: isConnected ? .semibold : .regular)
            let title = NSMutableAttributedString()

            if isSecured {
                // Right-align the lock badge by tabbing to the far end of the title area.
                let paraStyle = NSMutableParagraphStyle()
                paraStyle.tabStops = [NSTextTab(textAlignment: .right, location: 195)]

                title.append(NSAttributedString(string: ssid + "\t",
                                                attributes: [.font: nameFont,
                                                             .paragraphStyle: paraStyle]))

                let lockConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
                let lockImage  = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secured")?
                    .withSymbolConfiguration(lockConfig)
                lockImage?.isTemplate = true  // renders in the current text color, turns white on selection
                let lockAttachment = NSTextAttachment()
                lockAttachment.image = lockImage
                // Center the icon to the font's cap height so it sits level with the text.
                let lockH: CGFloat = 10
                let lockY = ((nameFont.capHeight - lockH) / 2).rounded(.towardZero)
                lockAttachment.bounds = CGRect(x: 0, y: lockY, width: lockH, height: lockH)
                let lockStr = NSMutableAttributedString(attachment: lockAttachment)
                lockStr.addAttribute(.paragraphStyle, value: paraStyle,
                                     range: NSRange(location: 0, length: lockStr.length))
                title.append(lockStr)
            } else {
                title.append(NSAttributedString(string: ssid, attributes: [.font: nameFont]))
            }

            item.attributedTitle = title
            menu.insertItem(item, at: insertionIndex)
            insertionIndex += 1
        }

        let trailingSep = NSMenuItem.separator()
        trailingSep.tag = knownNetworksTag + 1
        menu.insertItem(trailingSep, at: insertionIndex)
    }

    // MARK: - Actions

    @objc private func openWiFiSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
    }

    @objc private func copyIPv4() {
        guard let ip = lastIPv4 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        onCopyIPv4?(ip)
    }

    @objc private func copyIPv6() {
        guard let ip = lastIPv6 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        onCopyIPv6?(ip)
    }

    @objc private func copyGateway() {
        guard let gw = lastGateway else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(gw, forType: .string)
        onCopyGateway?(gw)
    }

    @objc private func copyDNS() {
        guard !lastDNSServers.isEmpty else { return }
        let value = lastDNSServers.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        onCopyDNS?(value)
    }

    @objc private func handleSettings() { onOpenSettings?() }
    @objc private func handleQuit()     { onQuit?() }

    // MARK: - IP attributed string

    private func ipAttributedString(label: String, value: String, available: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: label, attributes: [
            .font:            NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]))
        result.append(NSAttributedString(string: "   ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]))
        result.append(NSAttributedString(string: value, attributes: [
            .font:            NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: available ? NSColor.labelColor : NSColor.tertiaryLabelColor
        ]))
        return result
    }
}

// MARK: - Menu Header View

/// A compact, non-interactive header showing the app name and version.
final class MenuHeaderView: NSView {

    private let nameLabel    = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        nameLabel.stringValue    = AppInfo.appName
        versionLabel.stringValue = AppInfo.fullVersionString

        nameLabel.font      = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = .labelColor
        addSubview(nameLabel)

        versionLabel.font      = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        addSubview(versionLabel)
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 14
        let midY: CGFloat = (bounds.height - 14) / 2

        nameLabel.frame = NSRect(x: pad, y: midY, width: bounds.width * 0.6, height: 14)

        versionLabel.sizeToFit()
        versionLabel.frame = NSRect(
            x: bounds.width - pad - versionLabel.frame.width,
            y: midY + 0.5,
            width: versionLabel.frame.width,
            height: 13
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
