import AppKit
import CoreWLAN

/// Builds and manages the status bar NSMenu, including dynamic IP address rows
/// and the Known Networks panel. Menu item actions are handled here as @objc
/// targets; higher-level actions (open settings, quit, show popover) are
/// forwarded via callbacks set by AppDelegate.
final class MenuBuilder: NSObject {

    private(set) var menu: NSMenu!

    private var wifiMenuItem:     NSMenuItem?
    private var ipv4MenuItem:     NSMenuItem?
    private var ipv6MenuItem:     NSMenuItem?
    private var gatewayMenuItem:  NSMenuItem?
    private var externalIPMenuItem: NSMenuItem?
    private var pingMenuItem:        NSMenuItem?
    private var speedMenuItem:       NSMenuItem?
    private var pingItemView:        ClickableMenuItemView?
    private var speedItemView:       ClickableMenuItemView?

    private let dnsTag = 800

    private(set) var lastIPv4:       String?
    private(set) var lastIPv6:       String?
    private(set) var lastGateway:    String?
    private(set) var lastDNSServers: [String] = []
    private(set) var lastExternalIP: String?

    private let knownNetworksTag = 900

    
    private var shouldShowKnownNetworks: Bool {
        UserDefaults.standard.bool(for: .showKnownNetworks, default: true)
    }

    private var shouldShowExternalIP: Bool {
        UserDefaults.standard.bool(for: .showExternalIP, default: true)
    }

    // MARK: - Callbacks (set by AppDelegate after init)

    var onCopyIPv4:      ((String) -> Void)?
    var onCopyIPv6:      ((String) -> Void)?
    var onCopyGateway:   ((String) -> Void)?
    var onCopyDNS:       ((String) -> Void)?
    var onCopyExternalIP: ((String) -> Void)?
    var onRefreshPing:   (() -> Void)?
    var onRefreshSpeed:  (() -> Void)?
    var onOpenSettings:  (() -> Void)?
    var onQuit:          (() -> Void)?

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

        let extIPItem = NSMenuItem(title: "", action: #selector(copyExternalIP), keyEquivalent: "")
        extIPItem.target          = self
        extIPItem.toolTip         = "Click to copy"
        extIPItem.attributedTitle = ipAttributedString(label: "EXT ", value: "Loading…", available: false)
        extIPItem.isHidden        = !shouldShowExternalIP
        externalIPMenuItem = extIPItem
        m.addItem(extIPItem)

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
        dnsItem.tag             = dnsTag
        m.addItem(dnsItem)

        m.addItem(.separator())

        let pingView = ClickableMenuItemView(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        pingView.setAttributedString(ipAttributedString(label: "PING", value: "—", available: false))
        pingView.onRefresh = { [weak self] in self?.refreshPing() }
        pingItemView = pingView
        let pingItem = NSMenuItem()
        pingItem.toolTip = "Click to refresh"
        pingItem.view    = pingView
        pingMenuItem = pingItem
        m.addItem(pingItem)

        let speedView = ClickableMenuItemView(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        speedView.setAttributedString(combinedSpeedAttributedString(download: nil, upload: nil, updating: false))
        speedView.onRefresh = { [weak self] in self?.refreshSpeed() }
        speedItemView = speedView
        let speedItem = NSMenuItem()
        speedItem.toolTip = "Click to refresh"
        speedItem.view    = speedView
        speedMenuItem = speedItem
        m.addItem(speedItem)

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
        refreshDNSItems(servers: addresses.dnsServers)

        refreshKnownNetworks(currentSSID: addresses.wifiName)
    }

    private func refreshDNSItems(servers: [String]) {
        guard let menu else { return }

        // Find the index of the first existing DNS item
        guard let firstIndex = menu.items.firstIndex(where: { $0.tag == dnsTag }) else { return }

        // Remove all current DNS items
        while let old = menu.items.first(where: { $0.tag == dnsTag }) {
            menu.removeItem(old)
        }

        // Insert one item per server (or a single "Unavailable" item)
        if servers.isEmpty {
            let item = NSMenuItem(title: "", action: #selector(copyDNS), keyEquivalent: "")
            item.target          = self
            item.toolTip         = "Click to copy"
            item.attributedTitle = ipAttributedString(label: "DNS ", value: "Unavailable", available: false)
            item.tag             = dnsTag
            menu.insertItem(item, at: firstIndex)
        } else {
            for (i, server) in servers.enumerated() {
                let label = i == 0 ? "DNS " : "    "
                let item = NSMenuItem(title: "", action: #selector(copyDNS), keyEquivalent: "")
                item.target          = self
                item.toolTip         = "Click to copy"
                item.attributedTitle = ipAttributedString(label: label, value: server, available: true)
                item.tag             = dnsTag
                menu.insertItem(item, at: firstIndex + i)
            }
        }
    }

    // MARK: - Speed Reset

    func clearSpeedSnapshot() {
        pingItemView?.setAttributedString(ipAttributedString(label: "PING", value: "—", available: false))
        speedItemView?.setAttributedString(combinedSpeedAttributedString(download: nil, upload: nil, updating: false))
    }

    // MARK: - Speed Measuring State

    private var isMeasuringSpeed = false

    func setSpeedMeasuring(_ measuring: Bool) {
        isMeasuringSpeed = measuring
        guard measuring else { return }
        speedItemView?.setAttributedString(combinedSpeedAttributedString(download: nil, upload: nil, updating: true))
    }

    // MARK: - Speed Snapshot Update

    func updateSpeedSnapshot(_ snapshot: NetworkSpeedMonitor.Snapshot) {
        // Ping is independent — update it immediately whenever it arrives.
        pingItemView?.setAttributedString(ipAttributedString(
            label: "PING",
            value: snapshot.pingMs.map { String(format: "%.0f ms", $0) } ?? "—",
            available: snapshot.pingMs != nil
        ))
        // Skip speed row while a test is in flight to keep "Updating…" visible.
        guard !isMeasuringSpeed else { return }
        speedItemView?.setAttributedString(combinedSpeedAttributedString(
            download: snapshot.downloadMbps,
            upload:   snapshot.uploadMbps,
            updating: false
        ))
    }

    private func combinedSpeedAttributedString(download: Double?, upload: Double?, updating: Bool) -> NSAttributedString {
        if updating {
            return ipAttributedString(label: "SPEED", value: "Updating…", available: false, spacer: "  ")
        }
        guard let dl = download, let ul = upload else {
            return ipAttributedString(label: "SPEED", value: "—", available: false, spacer: "  ")
        }
        return ipAttributedString(label: "SPEED", value: "↓ \(formatSpeed(dl))  ↑ \(formatSpeed(ul))", available: true, spacer: "  ")
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 100 { return String(format: "%.0f Mbps", mbps) }
        if mbps >= 10  { return String(format: "%.1f Mbps", mbps) }
        if mbps >= 1   { return String(format: "%.2f Mbps", mbps) }
        return String(format: "%.0f Kbps", mbps * 1000)
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

    @objc private func copyExternalIP() {
        guard let ip = lastExternalIP else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
        onCopyExternalIP?(ip)
    }

    func updateExternalIP(_ ip: String?) {
        lastExternalIP = ip
        externalIPMenuItem?.isHidden = !shouldShowExternalIP
        guard shouldShowExternalIP else { return }
        externalIPMenuItem?.attributedTitle = ipAttributedString(
            label: "EXT ",
            value: ip ?? "Unavailable",
            available: ip != nil
        )
    }

    @objc private func refreshPing() {
        pingItemView?.setAttributedString(ipAttributedString(label: "PING", value: "Updating…", available: false))
        onRefreshPing?()
    }

    @objc private func refreshSpeed() {
        speedItemView?.setAttributedString(combinedSpeedAttributedString(download: nil, upload: nil, updating: true))
        onRefreshSpeed?()
    }

    @objc private func handleSettings() { onOpenSettings?() }
    @objc private func handleQuit()     { onQuit?() }

    // MARK: - IP attributed string

    private func ipAttributedString(label: String, value: String, available: Bool, labelFontSize: CGFloat = 11, spacer: String = "   ") -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: label, attributes: [
            .font:            NSFont.monospacedSystemFont(ofSize: labelFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        result.append(NSAttributedString(string: spacer, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ]))
        result.append(NSAttributedString(string: value, attributes: [
            .font:            NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: available ? NSColor.labelColor : NSColor.secondaryLabelColor
        ]))
        return result
    }
}

// MARK: - Clickable Menu Item View

/// A menu item view that handles clicks in-place without dismissing the menu.
/// AppKit only closes the menu when `NSMenu.cancelTracking()` is called or the
/// user clicks outside; custom views receive events without triggering that.
final class ClickableMenuItemView: NSView {

    var onRefresh: (() -> Void)?

    private let textField = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable   = false
        textField.isBordered   = false
        textField.drawsBackground = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setAttributedString(_ str: NSAttributedString) {
        textField.attributedStringValue = str
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true }
    override func mouseExited(with event: NSEvent)  { isHighlighted = false }

    override func mouseDown(with event: NSEvent) {
        onRefresh?()
        // Intentionally not calling super — keeps the menu open.
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedMenuItemColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
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
