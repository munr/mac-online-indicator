import AppKit

// Placeholder strings used throughout the menu for missing / not-yet-loaded values.
private let noValue      = "—"
private let unavailable  = "Unavailable"

private enum MenuLayout {
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
private enum WiFiThreshold {
    static let excellent:   Int    = -60
    static let good:        Int    = -70
    static let fair:        Int    = -80
    static let rssiOffset:  Double = 90
    static let rssiRange:   Double = 40
}

/// Builds and manages the status bar NSMenu.
/// The menu uses a card-style layout with a hero header, stats bar, sectioned
/// network info rows, and a two-button footer. Menu item actions are handled
/// here as @objc targets; higher-level actions are forwarded via callbacks set
/// by AppDelegate.
final class MenuBuilder: NSObject {

    private(set) var menu: NSMenu!

    private var heroHeaderView: MenuHeroHeaderView?
    private var statsBarView:   MenuStatsBarView?
    private var ipv4RowView:    MenuInfoRowView?
    private var ipv6RowView:    MenuInfoRowView?
    private var gatewayRowView: MenuInfoRowView?

    private let dnsTag = 800

    private(set) var lastIPv4:       String?
    private(set) var lastIPv6:       String?
    private(set) var lastGateway:    String?
    private(set) var lastDNSServers: [String] = []
    private(set) var lastExternalIP: String?
    private var lastISP:             String?
    private var lastWifiName:        String?
    private var isVPNActive:         Bool = false
    private var currentStatus:       AppState.ConnectionStatus = .noNetwork

    private var renderedDNSServers: [String] = []

    // MARK: - Callbacks

    var onCopyIPv4:       ((String) -> Void)?
    var onCopyIPv6:       ((String) -> Void)?
    var onCopyGateway:    ((String) -> Void)?
    var onCopyDNS:        ((String) -> Void)?
    var onCopyExternalIP: ((String) -> Void)?
    var onRefreshPing:    (() -> Void)?
    var onRefreshSpeed:   (() -> Void)?
    var onOpenSettings:   (() -> Void)?
    var onQuit:           (() -> Void)?

    // MARK: - Build

    func build() -> NSMenu {
        let m = NSMenu()
        m.minimumWidth = MenuLayout.menuWidth

        // 1. Hero header
        let hero = MenuHeroHeaderView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: 100))
        hero.onOpenWiFiSettings = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        }
        heroHeaderView = hero
        let heroItem = NSMenuItem()
        heroItem.view      = hero
        heroItem.isEnabled = false
        m.addItem(heroItem)

        // 2. Stats bar
        let stats = MenuStatsBarView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: 80))
        stats.onRefresh = { [weak self] in
            self?.onRefreshPing?()
            self?.onRefreshSpeed?()
        }
        statsBarView = stats
        let statsItem = NSMenuItem()
        statsItem.view = stats
        m.addItem(statsItem)

        // 3. NETWORK section
        m.addItem(.separator())
        m.addItem(makeSectionItem(title: "NETWORK"))

        let ipv4Row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        ipv4Row.configure(label: "Internal IPv4", value: noValue, available: false)
        ipv4Row.onCopy = { [weak self] in
            guard let self, let v = self.lastIPv4 else { return }
            self.copyToPasteboard(v, callback: self.onCopyIPv4)
        }
        ipv4RowView = ipv4Row
        let ipv4Item = NSMenuItem()
        ipv4Item.view = ipv4Row
        m.addItem(ipv4Item)

        let ipv6Row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        ipv6Row.configure(label: "Internal IPv6", value: noValue, available: false)
        ipv6Row.onCopy = { [weak self] in
            guard let self, let v = self.lastIPv6 else { return }
            self.copyToPasteboard(v, callback: self.onCopyIPv6)
        }
        ipv6RowView = ipv6Row
        let ipv6Item = NSMenuItem()
        ipv6Item.view = ipv6Row
        m.addItem(ipv6Item)

        // 4. ROUTER section
        m.addItem(.separator())
        m.addItem(makeSectionItem(title: "ROUTER"))

        let gwRow = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        gwRow.configure(label: "Gateway", value: noValue, available: false)
        gwRow.onCopy = { [weak self] in
            guard let self, let v = self.lastGateway else { return }
            self.copyToPasteboard(v, callback: self.onCopyGateway)
        }
        gatewayRowView = gwRow
        let gwItem = NSMenuItem()
        gwItem.view = gwRow
        m.addItem(gwItem)

        // DNS placeholder row — replaced dynamically; tag = dnsTag
        let dnsRow = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        dnsRow.configure(label: "DNS", value: noValue, available: false)
        dnsRow.onCopy = { [weak self] in
            guard let self, !self.lastDNSServers.isEmpty else { return }
            self.copyToPasteboard(self.lastDNSServers.joined(separator: "\n"), callback: self.onCopyDNS)
        }
        let dnsItem = NSMenuItem()
        dnsItem.view = dnsRow
        dnsItem.tag  = dnsTag
        m.addItem(dnsItem)

        // 5. Footer
        let footer = MenuFooterView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: 54))
        footer.onSettings = { [weak self] in self?.onOpenSettings?() }
        footer.onQuit     = { [weak self] in self?.onQuit?() }
        let footerItem = NSMenuItem()
        footerItem.view = footer
        m.addItem(footerItem)

        menu = m
        return m
    }

    // MARK: - Section item factory

    private func makeSectionItem(title: String) -> NSMenuItem {
        let view = MenuSectionLabelView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: 28))
        view.configure(title: title)
        let item = NSMenuItem()
        item.view      = view
        item.isEnabled = false
        return item
    }

    // MARK: - Dynamic Address Update

    func updateAddresses(_ addresses: IPAddressProvider.Addresses) {
        lastIPv4       = addresses.ipv4
        lastIPv6       = addresses.ipv6
        lastGateway    = addresses.gateway
        lastDNSServers = addresses.dnsServers
        lastWifiName   = addresses.wifiName

        ipv4RowView?.configure(
            label: "Internal IPv4",
            value: addresses.ipv4 ?? unavailable,
            available: addresses.ipv4 != nil
        )
        ipv6RowView?.configure(
            label: "Internal IPv6",
            value: addresses.ipv6 ?? unavailable,
            available: addresses.ipv6 != nil
        )
        gatewayRowView?.configure(
            label: "Gateway",
            value: addresses.gateway ?? unavailable,
            available: addresses.gateway != nil
        )
        refreshDNSItems(servers: addresses.dnsServers)
        heroHeaderView?.updateNetwork(name: addresses.wifiName)
        heroHeaderView?.updateWiFiStrength(addresses.wifiRSSI)
    }

    private func refreshDNSItems(servers: [String]) {
        guard let menu else { return }
        guard servers != renderedDNSServers else { return }
        guard let firstIndex = menu.items.firstIndex(where: { $0.tag == dnsTag }) else { return }

        while let old = menu.items.first(where: { $0.tag == dnsTag }) {
            menu.removeItem(old)
        }

        let copyBlock: () -> Void = { [weak self] in
            guard let self, !self.lastDNSServers.isEmpty else { return }
            self.copyToPasteboard(self.lastDNSServers.joined(separator: "\n"), callback: self.onCopyDNS)
        }

        if servers.isEmpty {
            let row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
            row.configure(label: "DNS", value: unavailable, available: false)
            row.onCopy = copyBlock
            let item = NSMenuItem()
            item.view = row
            item.tag  = dnsTag
            menu.insertItem(item, at: firstIndex)
        } else {
            for (i, server) in servers.enumerated() {
                let row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
                row.configure(label: i == 0 ? "DNS" : "", value: server, available: true)
                row.onCopy = copyBlock
                let item = NSMenuItem()
                item.view = row
                item.tag  = dnsTag
                menu.insertItem(item, at: firstIndex + i)
            }
        }

        renderedDNSServers = servers
    }

    // MARK: - Connection Status

    func updateConnectionStatus(_ status: AppState.ConnectionStatus) {
        currentStatus = status
        heroHeaderView?.updateStatus(status)
    }

    // MARK: - External IP / ISP / VPN

    func updateExternalIP(_ ip: String?) {
        lastExternalIP = ip
        heroHeaderView?.updateExternalIP(ip, isVPN: isVPNActive)
    }

    func updateISP(_ isp: String?) {
        lastISP = isp
        heroHeaderView?.updateISP(isp)
    }

    func updateVPNState(_ active: Bool) {
        isVPNActive = active
        heroHeaderView?.updateExternalIP(lastExternalIP, isVPN: active)
    }

    // MARK: - Speed / Ping

    func clearSpeedSnapshot() {
        statsBarView?.reset()
    }

    private var isMeasuringSpeed = false

    func setSpeedMeasuring(_ measuring: Bool) {
        isMeasuringSpeed = measuring
        if measuring { statsBarView?.setUpdating() }
    }

    func updateSpeedSnapshot(_ snapshot: NetworkSpeedMonitor.Snapshot) {
        statsBarView?.updatePing(snapshot.pingMs)
        guard !isMeasuringSpeed else { return }
        statsBarView?.updateSpeed(download: snapshot.downloadMbps, upload: snapshot.uploadMbps)
    }

    // MARK: - Pasteboard helper

    private func copyToPasteboard(_ value: String, callback: ((String) -> Void)? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        callback?(value)
    }
}

// MARK: - MenuHeroHeaderView

/// Card-style hero header: circular icon on the left; network name + status dot,
/// ISP, and external IP stacked on the right.
final class MenuHeroHeaderView: NSView {

    var onOpenWiFiSettings: (() -> Void)?

    private let nameLabel    = NSTextField(labelWithString: "")
    private let ispLabel     = NSTextField(labelWithString: "")
    private let extIPLabel   = NSTextField(labelWithString: "")
    private let vpnBadgeView = VPNBadgeView()
    private weak var statusDotView: NSView?
    private weak var iconBgView: NSView?
    private var ringLayer: CAShapeLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        // ── Circular icon ──────────────────────────────────────────────────
        let iconSize = MenuLayout.heroIconSize
        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.layer?.cornerRadius    = iconSize / 2
        iconBg.layer?.masksToBounds   = true
        iconBg.layer?.backgroundColor = NSColor(
            calibratedRed: 0.10, green: 0.24, blue: 0.22, alpha: 1
        ).cgColor
        addSubview(iconBg)
        iconBgView = iconBg

        // Partial-arc ring layer drawn on top of iconBg, parented to self.layer
        // so it isn't clipped by iconBg's masksToBounds.
        // Path is set/updated in layout() once Auto Layout has resolved iconBg.frame.
        let ring = CAShapeLayer()
        ring.fillColor   = nil
        ring.strokeColor = NSColor.systemGreen.cgColor
        ring.lineWidth   = MenuLayout.ringStrokeWidth
        ring.lineCap     = .round
        ring.strokeStart = 0
        ring.strokeEnd   = 0
        // Disable all implicit animations on this layer
        ring.actions = ["strokeEnd": NSNull(), "strokeColor": NSNull(), "path": NSNull()]
        ringLayer = ring

        let iconImageView = NSImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling  = .scaleProportionallyDown
        let symConfig = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        iconImageView.image         = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                                              accessibilityDescription: nil)?
                                        .withSymbolConfiguration(symConfig)
        iconImageView.contentTintColor = NSColor(calibratedRed: 0.27, green: 0.76, blue: 0.60, alpha: 1)
        iconBg.addSubview(iconImageView)

        // ── Status dot ─────────────────────────────────────────────────────
        let dot = NSView()
        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer?.cornerRadius  = 5
        dot.layer?.masksToBounds = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor  // set properly on first status update
        addSubview(dot)
        statusDotView = dot

        // ── Text labels ────────────────────────────────────────────────────
        nameLabel.font      = .systemFont(ofSize: 15, weight: .bold)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        ispLabel.font      = .systemFont(ofSize: 12, weight: .regular)
        ispLabel.textColor = .secondaryLabelColor
        ispLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ispLabel)

        extIPLabel.font      = .systemFont(ofSize: 12, weight: .regular)
        extIPLabel.textColor = .secondaryLabelColor
        extIPLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(extIPLabel)

        vpnBadgeView.isHidden = true
        vpnBadgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vpnBadgeView)

        // ── Layout ─────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.heroLeadingPadding),
            iconBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: iconSize),
            iconBg.heightAnchor.constraint(equalToConstant: iconSize),

            iconImageView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),

            // Name + dot sit on the same baseline
            nameLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: iconBg.topAnchor, constant: 6),

            dot.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor, constant: -1),
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),

            ispLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            ispLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),

            extIPLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            extIPLabel.topAnchor.constraint(equalTo: ispLabel.bottomAnchor, constant: 3),

            vpnBadgeView.leadingAnchor.constraint(equalTo: extIPLabel.trailingAnchor, constant: 6),
            vpnBadgeView.centerYAnchor.constraint(equalTo: extIPLabel.centerYAnchor),
        ])

        nameLabel.stringValue  = Host.current().localizedName ?? "Mac"
        ispLabel.stringValue   = noValue
        extIPLabel.stringValue = noValue

        // Add ring as sublayer of self after wantsLayer = true ensures self.layer exists
        if let ring = ringLayer { layer?.addSublayer(ring) }
    }

    override func layout() {
        super.layout()
        updateRingPath()
    }

    private func updateRingPath() {
        guard let ring = ringLayer, let iconBg = iconBgView else { return }
        // Slightly outside the circle so the stroke doesn't overlap the icon background
        let radius = iconBg.frame.width / 2 + MenuLayout.ringStrokeWidth
        let center = CGPoint(x: iconBg.frame.midX, y: iconBg.frame.midY)
        let path   = CGMutablePath()
        // Start at 12 o'clock (π/2 in macOS Y-up coords) and go clockwise
        path.addArc(center: center, radius: radius,
                    startAngle: .pi / 2,
                    endAngle:   .pi / 2 - 2 * .pi,
                    clockwise:  true)
        ring.path = path
    }

    // MARK: - Updates

    func updateStatus(_ status: AppState.ConnectionStatus) {
        let color: NSColor
        switch status {
        case .connected:  color = .systemGreen
        case .blocked:    color = .systemOrange
        case .noNetwork:  color = .systemRed
        }
        statusDotView?.layer?.backgroundColor = color.cgColor
    }

    func updateNetwork(name: String?) {
        nameLabel.stringValue = name ?? Host.current().localizedName ?? "Mac"
    }

    func updateISP(_ isp: String?) {
        ispLabel.stringValue = isp ?? noValue
    }

    func updateExternalIP(_ ip: String?, isVPN: Bool) {
        extIPLabel.stringValue = ip ?? noValue
        vpnBadgeView.isHidden = !isVPN || ip == nil
    }

    func updateWiFiStrength(_ rssi: Int?) {
        guard let ring = ringLayer else { return }
        if let rssi {
            // Map RSSI to a 0–1 coverage fraction.
            // -50 dBm (excellent) → 1.0, -90 dBm (unusable) → 0.0
            let fraction = CGFloat((Double(rssi) + WiFiThreshold.rssiOffset) / WiFiThreshold.rssiRange).clamped(to: 0...1)
            let color: NSColor
            switch rssi {
            case WiFiThreshold.excellent...: color = .systemGreen
            case WiFiThreshold.good...:      color = .systemYellow
            case WiFiThreshold.fair...:      color = .systemOrange
            default:                         color = .systemRed
            }
            ring.strokeColor = color.cgColor
            ring.strokeEnd   = fraction
        } else {
            ring.strokeEnd = 0
        }
    }

    // MARK: - Click → open WiFi settings

    override func mouseDown(with event: NSEvent) {
        onOpenWiFiSettings?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

// MARK: - MenuHoverView

/// Base class for interactive menu rows that show a selection highlight on hover.
/// Subclasses inherit the highlight view, tracking area management, and enter/exit
/// handlers — they only need to add `highlightView` to their layout and handle `mouseDown`.
private class MenuHoverView: NSView {

    let highlightView: NSVisualEffectView = {
        let v = NSVisualEffectView()
        v.material         = .selection
        v.state            = .active
        v.isEmphasized     = true
        v.wantsLayer       = true
        v.layer?.cornerRadius = MenuLayout.highlightCornerRadius
        v.isHidden         = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { highlightView.isHidden = false }
    override func mouseExited(with event: NSEvent)  { highlightView.isHidden = true }
}

// MARK: - MenuStatsBarView

/// Three-column stats bar: DOWN | UP | PING, with fractional auto-layout columns.
/// Clicking anywhere refreshes speed and ping.
final class MenuStatsBarView: MenuHoverView {

    var onRefresh: (() -> Void)?

    private let downValueLabel = NSTextField(labelWithString: noValue)
    private let downUnitLabel  = NSTextField(labelWithString: "")
    private let upValueLabel   = NSTextField(labelWithString: noValue)
    private let upUnitLabel    = NSTextField(labelWithString: "")
    private let pingValueLabel = NSTextField(labelWithString: noValue)
    private let pingUnitLabel  = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        addSubview(highlightView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        // Top separator
        let sep = makeSeparator()
        addSubview(sep)

        // Configure value and unit labels
        configure(downValueLabel,  font: .systemFont(ofSize: 22, weight: .semibold))
        configure(upValueLabel,    font: .systemFont(ofSize: 22, weight: .semibold))
        configure(pingValueLabel,  font: .systemFont(ofSize: 22, weight: .semibold))
        configure(downUnitLabel,   font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        configure(upUnitLabel,     font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        configure(pingUnitLabel,   font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)

        // Each column is a vertical stack: header, value, unit — centered horizontally.
        let col1 = makeColumnStack(header: "DOWN", value: downValueLabel, unit: downUnitLabel)
        let col2 = makeColumnStack(header: "UP",   value: upValueLabel,   unit: upUnitLabel)
        let col3 = makeColumnStack(header: "PING", value: pingValueLabel, unit: pingUnitLabel)

        let div1 = makeSeparator(vertical: true)
        let div2 = makeSeparator(vertical: true)

        [col1, col2, col3, div1, div2].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            // Top separator
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            // Three equal columns
            col1.leadingAnchor.constraint(equalTo: leadingAnchor),
            col1.topAnchor.constraint(equalTo: sep.bottomAnchor),
            col1.bottomAnchor.constraint(equalTo: bottomAnchor),
            col1.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1.0 / 3.0),

            col2.leadingAnchor.constraint(equalTo: col1.trailingAnchor),
            col2.topAnchor.constraint(equalTo: col1.topAnchor),
            col2.bottomAnchor.constraint(equalTo: col1.bottomAnchor),
            col2.widthAnchor.constraint(equalTo: col1.widthAnchor),

            col3.leadingAnchor.constraint(equalTo: col2.trailingAnchor),
            col3.topAnchor.constraint(equalTo: col1.topAnchor),
            col3.bottomAnchor.constraint(equalTo: col1.bottomAnchor),
            col3.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Vertical dividers
            div1.leadingAnchor.constraint(equalTo: col1.trailingAnchor),
            div1.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 10),
            div1.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            div1.widthAnchor.constraint(equalToConstant: 1),

            div2.leadingAnchor.constraint(equalTo: col2.trailingAnchor),
            div2.topAnchor.constraint(equalTo: div1.topAnchor),
            div2.bottomAnchor.constraint(equalTo: div1.bottomAnchor),
            div2.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    /// Returns a vertical NSStackView with the header, value, and unit labels centered.
    private func makeColumnStack(header: String, value: NSTextField, unit: NSTextField) -> NSStackView {
        let headerLabel = NSTextField(labelWithString: header)
        headerLabel.font      = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.alignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let col = NSStackView(views: [headerLabel, value, unit])
        col.orientation  = .vertical
        col.alignment    = .centerX
        col.spacing      = 2
        col.edgeInsets   = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        col.translatesAutoresizingMaskIntoConstraints = false
        return col
    }

    private func configure(_ field: NSTextField,
                            font: NSFont,
                            color: NSColor = .labelColor) {
        field.font      = font
        field.textColor = color
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeSeparator(vertical: Bool = false) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    // MARK: - Updates

    func reset() {
        downValueLabel.stringValue = noValue; downUnitLabel.stringValue = ""
        upValueLabel.stringValue   = noValue; upUnitLabel.stringValue   = ""
        pingValueLabel.stringValue = noValue; pingUnitLabel.stringValue = ""
    }

    func setUpdating() {
        downValueLabel.stringValue = "…"; downUnitLabel.stringValue = ""
        upValueLabel.stringValue   = "…"; upUnitLabel.stringValue   = ""
    }

    func updatePing(_ ms: Double?) {
        if let ms {
            pingValueLabel.stringValue = String(format: "%.0f", ms)
            pingUnitLabel.stringValue  = "ms"
        } else {
            pingValueLabel.stringValue = noValue
            pingUnitLabel.stringValue  = ""
        }
    }

    func updateSpeed(download: Double?, upload: Double?) {
        if let dl = download {
            let (v, u) = formatSpeed(dl)
            downValueLabel.stringValue = v; downUnitLabel.stringValue = u
        } else {
            downValueLabel.stringValue = noValue; downUnitLabel.stringValue = ""
        }
        if let ul = upload {
            let (v, u) = formatSpeed(ul)
            upValueLabel.stringValue = v; upUnitLabel.stringValue = u
        } else {
            upValueLabel.stringValue = noValue; upUnitLabel.stringValue = ""
        }
    }

    private func formatSpeed(_ mbps: Double) -> (String, String) {
        switch mbps {
        case 100...:  return (String(format: "%.0f", mbps), "Mbps")
        case 10...:   return (String(format: "%.1f", mbps), "Mbps")
        case 1...:    return (String(format: "%.2f", mbps), "Mbps")
        default:      return (String(format: "%.0f", mbps * 1000), "Kbps")
        }
    }

    override func mouseDown(with event: NSEvent) { onRefresh?() }
}

// MARK: - MenuSectionLabelView

/// Non-interactive section header — e.g. "NETWORK" or "ROUTER".
final class MenuSectionLabelView: NSView {

    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = .width
        label.font      = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.heroLeadingPadding),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) { label.stringValue = title }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - MenuInfoRowView

/// A menu row: left-aligned label (secondary color) + right-aligned monospace
/// value (primary color). Highlights on hover and fires `onCopy` on click.
final class MenuInfoRowView: MenuHoverView {

    var onCopy: (() -> Void)?

    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        autoresizingMask = .width

        addSubview(highlightView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        // Label: secondary (gray) — matches the mockup's dimmed left-side labels
        labelField.font      = .systemFont(ofSize: 13, weight: .regular)
        labelField.textColor = .secondaryLabelColor
        labelField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelField)

        // Value: primary (bright) monospace
        valueField.font      = .monospacedSystemFont(ofSize: 13, weight: .regular)
        valueField.textColor = .labelColor
        valueField.alignment = .right
        valueField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueField)

        NSLayoutConstraint.activate([
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.heroLeadingPadding),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: valueField.leadingAnchor, constant: -8),

            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.heroLeadingPadding),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.60),
        ])
    }

    func configure(label: String, value: String, available: Bool) {
        labelField.stringValue = label
        valueField.stringValue = value
        valueField.textColor   = available ? .labelColor : .tertiaryLabelColor
    }

    override func mouseDown(with event: NSEvent) { onCopy?() }
}

// MARK: - MenuFooterView

/// Two-button footer: "Settings" on the left, "Quit" on the right.
/// Each button is a custom clickable view so we can precisely center
/// the icon + label pair — NSButton's built-in layout doesn't reliably
/// center icon+title within wide bounds.
final class MenuFooterView: NSView {

    var onSettings: (() -> Void)?
    var onQuit:     (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        // Top separator
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        let settingsBtn = makeFooterButton(
            symbolName: "sun.min",
            title: "Settings",
            tintColor: .labelColor,
            action: { [weak self] in self?.onSettings?() }
        )

        let quitBtn = makeFooterButton(
            symbolName: "rectangle.portrait.and.arrow.right",
            title: "Quit",
            tintColor: .systemRed,
            action: { [weak self] in self?.onQuit?() }
        )

        // Vertical divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            sep.heightAnchor.constraint(equalToConstant: 1),

            settingsBtn.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsBtn.topAnchor.constraint(equalTo: sep.bottomAnchor),
            settingsBtn.bottomAnchor.constraint(equalTo: bottomAnchor),
            settingsBtn.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),

            divider.leadingAnchor.constraint(equalTo: settingsBtn.trailingAnchor),
            divider.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 8),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            divider.widthAnchor.constraint(equalToConstant: 1),

            quitBtn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            quitBtn.trailingAnchor.constraint(equalTo: trailingAnchor),
            quitBtn.topAnchor.constraint(equalTo: sep.bottomAnchor),
            quitBtn.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Returns a fully laid-out, clickable button view with the icon immediately
    /// beside the label, the pair centered within the button area.
    private func makeFooterButton(symbolName: String,
                                   title: String,
                                   tintColor: NSColor,
                                   action: @escaping () -> Void) -> MenuFooterButtonView {
        let btn = MenuFooterButtonView(symbolName: symbolName, title: title, tintColor: tintColor)
        btn.onTap = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(btn)
        return btn
    }
}

// MARK: - VPNBadgeView

/// A small pill-shaped badge displaying "VPN" in system blue.
private final class VPNBadgeView: NSView {

    private var cornerRadiusSet = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth       = 0.5
        layer?.borderColor       = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        layer?.backgroundColor   = NSColor.systemBlue.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: "VPN")
        label.font      = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = .systemBlue
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard !cornerRadiusSet, bounds.height > 0 else { return }
        layer?.cornerRadius = bounds.height / 2
        cornerRadiusSet = true
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// A single button cell inside `MenuFooterView`. Uses an `NSStackView` to keep
/// the SF Symbol icon tightly adjacent to the title, with the pair centered.
private final class MenuFooterButtonView: MenuHoverView {

    var onTap: (() -> Void)?

    init(symbolName: String, title: String, tintColor: NSColor) {
        super.init(frame: .zero)

        addSubview(highlightView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])

        // SF Symbol image
        let symConfig  = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let imageView  = NSImageView()
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                            .withSymbolConfiguration(symConfig)
        imageView.contentTintColor = tintColor
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        // Title label
        let label = NSTextField(labelWithString: title)
        label.font      = .systemFont(ofSize: 13)
        label.textColor = tintColor
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false

        // Stack keeps icon hugging the title; the stack itself is centered
        let stack = NSStackView(views: [imageView, label])
        stack.orientation        = .horizontal
        stack.spacing            = 5
        stack.alignment          = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onTap?() }
}
