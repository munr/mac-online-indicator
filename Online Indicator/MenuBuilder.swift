import AppKit

/// Builds and manages the status bar NSMenu, including dynamic IP address rows.
/// Menu item actions are handled here as @objc targets; higher-level actions
/// (open settings, quit, show popover) are forwarded via callbacks set by AppDelegate.
final class MenuBuilder: NSObject {

    private(set) var menu: NSMenu!

    private var wifiMenuItem:     NSMenuItem?
    private var ipv4MenuItem:     NSMenuItem?
    private var ipv6MenuItem:     NSMenuItem?
    private var gatewayMenuItem:  NSMenuItem?
    private var externalIPMenuItem: NSMenuItem?
    private var ispMenuItem:         NSMenuItem?
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
    private var lastISP: String?
    private var isVPNActive: Bool = false

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
        wifiItem.attributedTitle = ipAttributedString(label: "WIFI  ", value: "Loading…", available: false)
        wifiMenuItem = wifiItem
        m.addItem(wifiItem)

        externalIPMenuItem = makeIPRow(label: "EXT   ", action: #selector(copyExternalIP))
        m.addItem(externalIPMenuItem!)

        ispMenuItem = makeIPRow(label: "ISP   ", action: #selector(copyISP))
        m.addItem(ispMenuItem!)

        m.addItem(.separator())

        ipv4MenuItem = makeIPRow(label: "INT-V4", action: #selector(copyIPv4))
        m.addItem(ipv4MenuItem!)

        ipv6MenuItem = makeIPRow(label: "INT-V6", action: #selector(copyIPv6))
        m.addItem(ipv6MenuItem!)

        m.addItem(.separator())

        gatewayMenuItem = makeIPRow(label: "GW    ", action: #selector(copyGateway))
        m.addItem(gatewayMenuItem!)

        let dnsItem = makeIPRow(label: "DNS   ", action: #selector(copyDNS))
        dnsItem.tag  = dnsTag
        m.addItem(dnsItem)

        m.addItem(.separator())

        let pingView = ClickableMenuItemView(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        pingView.setAttributedString(ipAttributedString(label: "PING  ", value: "—", available: false))
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

    // MARK: - Menu item factory

    private func makeIPRow(label: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.target          = self
        item.toolTip         = "Click to copy"
        item.attributedTitle = ipAttributedString(label: label, value: "Loading…", available: false)
        return item
    }

    // MARK: - Dynamic Address Update

    func updateAddresses(_ addresses: IPAddressProvider.Addresses) {
        lastIPv4       = addresses.ipv4
        lastIPv6       = addresses.ipv6
        lastGateway    = addresses.gateway
        lastDNSServers = addresses.dnsServers

        let showStrength = UserDefaults.standard.bool(for: .showWiFiStrength, default: true)
        let wifiValue: String
        if let ssid = addresses.wifiName {
            if showStrength, let rssi = addresses.wifiRSSI {
                wifiValue = "\(ssid)  \(rssiBarString(rssi))"
            } else {
                wifiValue = ssid
            }
        } else {
            wifiValue = "Unavailable"
        }
        wifiMenuItem?.attributedTitle = ipAttributedString(
            label: "WIFI  ",
            value: wifiValue,
            available: addresses.wifiName != nil
        )
        ipv4MenuItem?.attributedTitle = ipAttributedString(
            label: "INT-V4",
            value: addresses.ipv4 ?? "Unavailable",
            available: addresses.ipv4 != nil
        )
        ipv6MenuItem?.attributedTitle = ipAttributedString(
            label: "INT-V6",
            value: addresses.ipv6 ?? "Unavailable",
            available: addresses.ipv6 != nil
        )
        gatewayMenuItem?.attributedTitle = ipAttributedString(
            label: "GW    ",
            value: addresses.gateway ?? "Unavailable",
            available: addresses.gateway != nil
        )
        refreshDNSItems(servers: addresses.dnsServers)

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
            item.attributedTitle = ipAttributedString(label: "DNS   ", value: "Unavailable", available: false)
            item.tag             = dnsTag
            menu.insertItem(item, at: firstIndex)
        } else {
            for (i, server) in servers.enumerated() {
                let label = i == 0 ? "DNS   " : "      "
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
        pingItemView?.setAttributedString(ipAttributedString(label: "PING  ", value: "—", available: false))
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
            label: "PING  ",
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
            return ipAttributedString(label: "SPEED ", value: "Updating…", available: false)
        }
        guard let dl = download, let ul = upload else {
            return ipAttributedString(label: "SPEED ", value: "—", available: false)
        }
        return ipAttributedString(label: "SPEED ", value: "↓ \(formatSpeed(dl))  ↑ \(formatSpeed(ul))", available: true)
    }

    private func formatSpeed(_ mbps: Double) -> String {
        if mbps >= 100 { return String(format: "%.0f Mbps", mbps) }
        if mbps >= 10  { return String(format: "%.1f Mbps", mbps) }
        if mbps >= 1   { return String(format: "%.2f Mbps", mbps) }
        return String(format: "%.0f Kbps", mbps * 1000)
    }

    // MARK: - Actions

    @objc private func openWiFiSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
    }

    @objc private func copyIPv4()      { copyToPasteboard(lastIPv4,       callback: onCopyIPv4) }
    @objc private func copyIPv6()      { copyToPasteboard(lastIPv6,       callback: onCopyIPv6) }
    @objc private func copyGateway()   { copyToPasteboard(lastGateway,    callback: onCopyGateway) }
    @objc private func copyExternalIP(){ copyToPasteboard(lastExternalIP, callback: onCopyExternalIP) }
    @objc private func copyISP()       { copyToPasteboard(lastISP) }

    @objc private func copyDNS() {
        guard !lastDNSServers.isEmpty else { return }
        copyToPasteboard(lastDNSServers.joined(separator: "\n"), callback: onCopyDNS)
    }

    private func copyToPasteboard(_ value: String?, callback: ((String) -> Void)? = nil) {
        guard let value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        callback?(value)
    }

    func updateExternalIP(_ ip: String?) {
        lastExternalIP = ip
        refreshExternalIPRow()
    }

    func updateISP(_ isp: String?) {
        lastISP = isp
        ispMenuItem?.attributedTitle = ipAttributedString(
            label: "ISP   ",
            value: isp ?? "Unavailable",
            available: isp != nil
        )
    }

    func updateVPNState(_ active: Bool) {
        isVPNActive = active
        refreshExternalIPRow()
    }

    private func refreshExternalIPRow() {
        let ip = lastExternalIP
        let str = NSMutableAttributedString(
            attributedString: ipAttributedString(
                label: "EXT   ",
                value: ip ?? "Unavailable",
                available: ip != nil
            )
        )
        if isVPNActive && ip != nil {
            str.append(NSAttributedString(string: "  "))
            str.append(vpnPillString())
        }
        externalIPMenuItem?.attributedTitle = str
    }

    @objc private func refreshPing() {
        pingItemView?.setAttributedString(ipAttributedString(label: "PING  ", value: "Updating…", available: false))
        onRefreshPing?()
    }

    @objc private func refreshSpeed() {
        speedItemView?.setAttributedString(combinedSpeedAttributedString(download: nil, upload: nil, updating: true))
        onRefreshSpeed?()
    }

    @objc private func handleSettings() { onOpenSettings?() }
    @objc private func handleQuit()     { onQuit?() }

    // MARK: - VPN pill

    private func vpnPillString() -> NSAttributedString {
        let text = " VPN "
        let font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let pillSize = NSSize(width: size.width + 2, height: size.height + 1)

        let image = NSImage(size: pillSize, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: rect.height / 2,
                                    yRadius: rect.height / 2)
            NSColor.systemBlue.withAlphaComponent(0.18).setFill()
            path.fill()
            NSColor.systemBlue.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            let textAttrs: [NSAttributedString.Key: Any] = [
                .font:            font,
                .foregroundColor: NSColor.systemBlue
            ]
            let textSize = (text as NSString).size(withAttributes: textAttrs)
            let textOrigin = NSPoint(x: (rect.width - textSize.width) / 2,
                                     y: (rect.height - textSize.height) / 2)
            (text as NSString).draw(at: textOrigin, withAttributes: textAttrs)
            return true
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: pillSize.width, height: pillSize.height)
        return NSAttributedString(attachment: attachment)
    }

    // MARK: - WiFi Signal Strength

    private func rssiBarString(_ rssi: Int) -> String {
        let filled: Int
        switch rssi {
        case (-50)...:   filled = 4
        case (-60)...:   filled = 3
        case (-70)...:   filled = 2
        case (-80)...:   filled = 1
        default:         filled = 0
        }
        let bar: Character   = "█"
        let empty: Character = "░"
        return String(repeating: bar, count: filled) + String(repeating: empty, count: 4 - filled)
    }

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

    private let highlightView: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material         = .selection
        v.state            = .active
        v.isEmphasized     = true
        v.wantsLayer       = true
        v.layer?.cornerRadius = 4
        v.isHidden         = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width]

        addSubview(highlightView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable      = false
        textField.isBordered      = false
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

    override func mouseEntered(with event: NSEvent) { highlightView.isHidden = false }
    override func mouseExited(with event: NSEvent)  { highlightView.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        onRefresh?()
        // Intentionally not calling super — keeps the menu open.
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
        autoresizingMask = .width
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
