import AppKit

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
        m.minimumWidth = 300

        // 1. Hero header
        let hero = MenuHeroHeaderView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        hero.onOpenWiFiSettings = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        }
        heroHeaderView = hero
        let heroItem = NSMenuItem()
        heroItem.view      = hero
        heroItem.isEnabled = false
        m.addItem(heroItem)

        // 2. Stats bar
        let stats = MenuStatsBarView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
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

        let ipv4Row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        ipv4Row.configure(label: "Internal IPv4", value: "—", available: false)
        ipv4Row.onCopy = { [weak self] in
            guard let self, let v = self.lastIPv4 else { return }
            self.copyToPasteboard(v, callback: self.onCopyIPv4)
        }
        ipv4RowView = ipv4Row
        let ipv4Item = NSMenuItem()
        ipv4Item.view = ipv4Row
        m.addItem(ipv4Item)

        let ipv6Row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        ipv6Row.configure(label: "Internal IPv6", value: "—", available: false)
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

        let gwRow = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        gwRow.configure(label: "Gateway", value: "—", available: false)
        gwRow.onCopy = { [weak self] in
            guard let self, let v = self.lastGateway else { return }
            self.copyToPasteboard(v, callback: self.onCopyGateway)
        }
        gatewayRowView = gwRow
        let gwItem = NSMenuItem()
        gwItem.view = gwRow
        m.addItem(gwItem)

        // DNS placeholder row — replaced dynamically; tag = dnsTag
        let dnsRow = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        dnsRow.configure(label: "DNS", value: "—", available: false)
        dnsRow.onCopy = { [weak self] in
            guard let self, !self.lastDNSServers.isEmpty else { return }
            self.copyToPasteboard(self.lastDNSServers.joined(separator: "\n"), callback: self.onCopyDNS)
        }
        let dnsItem = NSMenuItem()
        dnsItem.view = dnsRow
        dnsItem.tag  = dnsTag
        m.addItem(dnsItem)

        // 5. Footer
        let footer = MenuFooterView(frame: NSRect(x: 0, y: 0, width: 300, height: 54))
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
        let view = MenuSectionLabelView(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
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
            value: addresses.ipv4 ?? "Unavailable",
            available: addresses.ipv4 != nil
        )
        ipv6RowView?.configure(
            label: "Internal IPv6",
            value: addresses.ipv6 ?? "Unavailable",
            available: addresses.ipv6 != nil
        )
        gatewayRowView?.configure(
            label: "Gateway",
            value: addresses.gateway ?? "Unavailable",
            available: addresses.gateway != nil
        )
        refreshDNSItems(servers: addresses.dnsServers)
        heroHeaderView?.updateNetwork(name: addresses.wifiName)
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
            let row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
            row.configure(label: "DNS", value: "Unavailable", available: false)
            row.onCopy = copyBlock
            let item = NSMenuItem()
            item.view = row
            item.tag  = dnsTag
            menu.insertItem(item, at: firstIndex)
        } else {
            for (i, server) in servers.enumerated() {
                let row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
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

    private let nameLabel  = NSTextField(labelWithString: "")
    private let ispLabel   = NSTextField(labelWithString: "")
    private let extIPLabel = NSTextField(labelWithString: "")
    private weak var statusDotView: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        // ── Circular icon ──────────────────────────────────────────────────
        let iconSize: CGFloat = 56
        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.layer?.cornerRadius  = iconSize / 2
        iconBg.layer?.masksToBounds = true
        iconBg.layer?.backgroundColor = NSColor(
            calibratedRed: 0.10, green: 0.24, blue: 0.22, alpha: 1
        ).cgColor
        addSubview(iconBg)

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

        // ── Layout ─────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
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
        ])

        nameLabel.stringValue  = Host.current().localizedName ?? "Mac"
        ispLabel.stringValue   = "—"
        extIPLabel.stringValue = "—"
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
        ispLabel.stringValue = isp ?? "—"
    }

    func updateExternalIP(_ ip: String?, isVPN: Bool) {
        if let ip {
            extIPLabel.stringValue = isVPN ? "\(ip)  VPN" : ip
        } else {
            extIPLabel.stringValue = "—"
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

// MARK: - MenuStatsBarView

/// Three-column stats bar: DOWN | UP | PING, with fractional auto-layout columns.
/// Clicking anywhere refreshes speed and ping.
final class MenuStatsBarView: NSView {

    var onRefresh: (() -> Void)?

    private let downValueLabel = NSTextField(labelWithString: "—")
    private let downUnitLabel  = NSTextField(labelWithString: "")
    private let upValueLabel   = NSTextField(labelWithString: "—")
    private let upUnitLabel    = NSTextField(labelWithString: "")
    private let pingValueLabel = NSTextField(labelWithString: "—")
    private let pingUnitLabel  = NSTextField(labelWithString: "")

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

    private var trackingArea: NSTrackingArea?

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
        let sep = makeLine()
        addSubview(sep)

        // Three hidden "column guide" views — each takes exactly 1/3 of the width.
        // All content is centered within its column guide.
        let col1 = makeColumnGuide()
        let col2 = makeColumnGuide()
        let col3 = makeColumnGuide()
        [col1, col2, col3].forEach { addSubview($0) }

        let downHeader  = makeHeaderLabel("DOWN")
        let upHeader    = makeHeaderLabel("UP")
        let pingHeader  = makeHeaderLabel("PING")

        configure(downValueLabel,  font: .systemFont(ofSize: 22, weight: .semibold))
        configure(upValueLabel,    font: .systemFont(ofSize: 22, weight: .semibold))
        configure(pingValueLabel,  font: .systemFont(ofSize: 22, weight: .semibold))
        configure(downUnitLabel,   font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        configure(upUnitLabel,     font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        configure(pingUnitLabel,   font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)

        let div1 = makeLine(vertical: true)
        let div2 = makeLine(vertical: true)

        [downHeader, upHeader, pingHeader,
         downValueLabel, upValueLabel, pingValueLabel,
         downUnitLabel, upUnitLabel, pingUnitLabel,
         div1, div2].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            // Top separator
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            // Column guides — equal thirds pinned to the full width
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

            // DOWN column
            downHeader.centerXAnchor.constraint(equalTo: col1.centerXAnchor),
            downHeader.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 10),
            downValueLabel.centerXAnchor.constraint(equalTo: col1.centerXAnchor),
            downValueLabel.topAnchor.constraint(equalTo: downHeader.bottomAnchor, constant: 2),
            downUnitLabel.centerXAnchor.constraint(equalTo: col1.centerXAnchor),
            downUnitLabel.topAnchor.constraint(equalTo: downValueLabel.bottomAnchor, constant: 2),

            // UP column
            upHeader.centerXAnchor.constraint(equalTo: col2.centerXAnchor),
            upHeader.topAnchor.constraint(equalTo: downHeader.topAnchor),
            upValueLabel.centerXAnchor.constraint(equalTo: col2.centerXAnchor),
            upValueLabel.topAnchor.constraint(equalTo: upHeader.bottomAnchor, constant: 2),
            upUnitLabel.centerXAnchor.constraint(equalTo: col2.centerXAnchor),
            upUnitLabel.topAnchor.constraint(equalTo: upValueLabel.bottomAnchor, constant: 2),

            // PING column
            pingHeader.centerXAnchor.constraint(equalTo: col3.centerXAnchor),
            pingHeader.topAnchor.constraint(equalTo: downHeader.topAnchor),
            pingValueLabel.centerXAnchor.constraint(equalTo: col3.centerXAnchor),
            pingValueLabel.topAnchor.constraint(equalTo: pingHeader.bottomAnchor, constant: 2),
            pingUnitLabel.centerXAnchor.constraint(equalTo: col3.centerXAnchor),
            pingUnitLabel.topAnchor.constraint(equalTo: pingValueLabel.bottomAnchor, constant: 2),

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

    private func makeHeaderLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font      = .systemFont(ofSize: 10, weight: .semibold)
        f.textColor = .secondaryLabelColor
        f.alignment = .center
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    private func configure(_ field: NSTextField,
                            font: NSFont,
                            color: NSColor = .labelColor) {
        field.font      = font
        field.textColor = color
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeColumnGuide() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func makeLine(vertical: Bool = false) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    // MARK: - Updates

    func reset() {
        downValueLabel.stringValue = "—"; downUnitLabel.stringValue = ""
        upValueLabel.stringValue   = "—"; upUnitLabel.stringValue   = ""
        pingValueLabel.stringValue = "—"; pingUnitLabel.stringValue = ""
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
            pingValueLabel.stringValue = "—"
            pingUnitLabel.stringValue  = ""
        }
    }

    func updateSpeed(download: Double?, upload: Double?) {
        if let dl = download {
            let (v, u) = formatSpeed(dl)
            downValueLabel.stringValue = v; downUnitLabel.stringValue = u
        } else {
            downValueLabel.stringValue = "—"; downUnitLabel.stringValue = ""
        }
        if let ul = upload {
            let (v, u) = formatSpeed(ul)
            upValueLabel.stringValue = v; upUnitLabel.stringValue = u
        } else {
            upValueLabel.stringValue = "—"; upUnitLabel.stringValue = ""
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

    // MARK: - Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { highlightView.isHidden = false }
    override func mouseExited(with event: NSEvent)  { highlightView.isHidden = true }
    override func mouseDown(with event: NSEvent)    { onRefresh?() }
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
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
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
final class MenuInfoRowView: NSView {

    var onCopy: (() -> Void)?

    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

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

    private var trackingArea: NSTrackingArea?

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
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: valueField.leadingAnchor, constant: -8),

            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.60),
        ])
    }

    func configure(label: String, value: String, available: Bool) {
        labelField.stringValue = label
        valueField.stringValue = value
        valueField.textColor   = available ? .labelColor : .tertiaryLabelColor
    }

    // MARK: - Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { highlightView.isHidden = false }
    override func mouseExited(with event: NSEvent)  { highlightView.isHidden = true }
    override func mouseDown(with event: NSEvent)    { onCopy?() }
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

/// A single button cell inside `MenuFooterView`. Uses an `NSStackView` to keep
/// the SF Symbol icon tightly adjacent to the title, with the pair centered.
private final class MenuFooterButtonView: NSView {

    var onTap: (() -> Void)?

    private let highlight: NSVisualEffectView = {
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

    private var trackingArea: NSTrackingArea?

    init(symbolName: String, title: String, tintColor: NSColor) {
        super.init(frame: .zero)

        addSubview(highlight)
        NSLayoutConstraint.activate([
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlight.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) { highlight.isHidden = false }
    override func mouseExited(with event: NSEvent)  { highlight.isHidden = true }
    override func mouseDown(with event: NSEvent)    { onTap?() }
}
