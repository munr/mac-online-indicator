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
    private var dnsLookupRowView: MenuInfoRowView?
    private var probeRowView:     MenuInfoRowView?
    private var outageRowView:    MenuInfoRowView?
    private var captivePortalItem: NSMenuItem?

    private var ipv4MenuItem:            NSMenuItem?
    private var ipv6MenuItem:            NSMenuItem?
    private var networkSectionSeparator: NSMenuItem?
    private var networkSectionHeader:    NSMenuItem?

    private let dnsTag = 800

    private(set) var lastIPv4:       String?
    private(set) var lastIPv6:       String?
    private(set) var lastGateway:    String?
    private(set) var lastDNSServers: [String] = []
    private(set) var lastExternalIP: String?
    private var isVPNActive:         Bool = false

    private var renderedDNSServers: [String] = []

    // MARK: - Callbacks

    var onCopyIPv4:    ((String) -> Void)?
    var onCopyIPv6:    ((String) -> Void)?
    var onCopyGateway: ((String) -> Void)?
    var onCopyDNS:     ((String) -> Void)?
    var onCopyExternalIP: ((String) -> Void)?
    var onOpenCaptivePortal: (() -> Void)?
    var onRefreshPing:   (() -> Void)?
    var onRefreshSpeed:  (() -> Void)?
    var onOpenSettings:  (() -> Void)?
    var onQuit:          (() -> Void)?

    // MARK: - Build

    func build() -> NSMenu {
        let m = NSMenu()
        m.minimumWidth = MenuLayout.menuWidth

        // 1. Hero header
        let hero = MenuHeroHeaderView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: 100))
        hero.onOpenWiFiSettings = {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
        }
        hero.onCopyExternalIP = { [weak self] in
            guard let self, let ip = self.lastExternalIP else { return }
            self.copyToPasteboard(ip, callback: self.onCopyExternalIP)
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

        // Captive-portal sign-in row — hidden until a portal is detected
        let portalRow = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        portalRow.configure(label: "Network login required", value: "Sign in", available: true)
        portalRow.helpText = "Open the network login page"
        portalRow.onCopy = { [weak self] in
            self?.menu.cancelTracking()
            self?.onOpenCaptivePortal?()
        }
        let portalItem = NSMenuItem()
        portalItem.view     = portalRow
        portalItem.isHidden = true
        captivePortalItem   = portalItem
        m.addItem(portalItem)

        // 3. NETWORK section
        let networkSep = NSMenuItem.separator()
        networkSectionSeparator = networkSep
        m.addItem(networkSep)
        let networkHeader = makeSectionItem(title: "NETWORK")
        networkSectionHeader = networkHeader
        m.addItem(networkHeader)

        let ipv4Row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        ipv4Row.configure(label: "Internal IPv4", value: menuNoValue, available: false)
        ipv4Row.onCopy = { [weak self] in
            guard let self, let v = self.lastIPv4 else { return }
            self.copyToPasteboard(v, callback: self.onCopyIPv4)
        }
        ipv4RowView = ipv4Row
        let ipv4Item = NSMenuItem()
        ipv4Item.view = ipv4Row
        ipv4MenuItem = ipv4Item
        m.addItem(ipv4Item)

        let ipv6Row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        ipv6Row.configure(label: "Internal IPv6", value: menuNoValue, available: false)
        ipv6Row.onCopy = { [weak self] in
            guard let self, let v = self.lastIPv6 else { return }
            self.copyToPasteboard(v, callback: self.onCopyIPv6)
        }
        ipv6RowView = ipv6Row
        let ipv6Item = NSMenuItem()
        ipv6Item.view = ipv6Row
        ipv6MenuItem = ipv6Item
        m.addItem(ipv6Item)

        // 4. ROUTER section
        m.addItem(.separator())
        m.addItem(makeSectionItem(title: "ROUTER"))

        let gwRow = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        gwRow.configure(label: "Gateway", value: menuNoValue, available: false)
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
        dnsRow.configure(label: "DNS", value: menuNoValue, available: false)
        dnsRow.onCopy = { [weak self] in
            guard let self, !self.lastDNSServers.isEmpty else { return }
            self.copyToPasteboard(self.lastDNSServers.joined(separator: "\n"), callback: self.onCopyDNS)
        }
        let dnsItem = NSMenuItem()
        dnsItem.view = dnsRow
        dnsItem.tag  = dnsTag
        m.addItem(dnsItem)

        // 5. DIAGNOSTICS section
        m.addItem(.separator())
        m.addItem(makeSectionItem(title: "DIAGNOSTICS"))
        dnsLookupRowView = addInfoRow(to: m, label: "DNS Lookup")
        probeRowView     = addInfoRow(to: m, label: "Probes")
        outageRowView    = addInfoRow(to: m, label: "Last Outage")
        resetDNSLookup()
        updateProbe(nil)
        updateLastOutage(nil)

        // 6. Footer
        let footer = MenuFooterView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: 44))
        footer.onSettings = { [weak self] in
            self?.menu.cancelTracking()
            // Open after the menu's tracking loop ends, otherwise activation/focus is swallowed.
            DispatchQueue.main.async { self?.onOpenSettings?() }
        }
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

    private func addInfoRow(to menu: NSMenu, label: String) -> MenuInfoRowView {
        let row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
        row.configure(label: label, value: menuNoValue, available: false)
        row.helpText = "Diagnostic information"
        let item = NSMenuItem()
        item.view = row
        menu.addItem(item)
        return row
    }

    // MARK: - Diagnostics

    /// Per-target probe summary and captive-portal row. Pass nil to clear (e.g. no network).
    func updateProbe(_ result: ProbeResult?) {
        captivePortalItem?.isHidden = !(result?.captivePortal ?? false)
        probeRowView?.configure(
            label: "Probes",
            value: result?.summary ?? menuNoValue,
            available: result.map { $0.failedHosts.isEmpty } ?? false
        )
    }

    func updateDNSLookup(ms: Double?) {
        dnsLookupRowView?.configure(
            label: "DNS Lookup",
            value: ms.map { "\(Int($0.rounded())) ms" } ?? "Failed",
            available: ms != nil
        )
    }

    func resetDNSLookup() {
        dnsLookupRowView?.configure(label: "DNS Lookup", value: menuNoValue, available: false)
    }

    func updateLastOutage(_ summary: String?) {
        outageRowView?.configure(label: "Last Outage", value: summary ?? "None", available: summary != nil)
    }

    // MARK: - Dynamic Address Update

    func updateAddresses(_ addresses: IPAddressProvider.Addresses) {
        lastIPv4       = addresses.ipv4
        lastIPv6       = addresses.ipv6
        lastGateway    = addresses.gateway
        lastDNSServers = addresses.dnsServers

        ipv4RowView?.configure(
            label: "Internal IPv4",
            value: addresses.ipv4 ?? menuUnavailable,
            available: addresses.ipv4 != nil
        )
        ipv6RowView?.configure(
            label: "Internal IPv6",
            value: addresses.ipv6 ?? menuUnavailable,
            available: addresses.ipv6 != nil
        )
        gatewayRowView?.configure(
            label: "Gateway",
            value: addresses.gateway ?? menuUnavailable,
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

        // Map servers to (label, value, available) triples; fall back to a single
        // "Unavailable" placeholder row when there are no servers.
        let entries: [(label: String, value: String, available: Bool)] = servers.isEmpty
            ? [("DNS", menuUnavailable, false)]
            : servers.enumerated().map { (i, server) in (i == 0 ? "DNS" : "", server, true) }

        for (i, entry) in entries.enumerated() {
            let row = MenuInfoRowView(frame: NSRect(x: 0, y: 0, width: MenuLayout.menuWidth, height: MenuLayout.rowHeight))
            row.configure(label: entry.label, value: entry.value, available: entry.available)
            row.onCopy = copyBlock
            let item = NSMenuItem()
            item.view = row
            item.tag  = dnsTag
            menu.insertItem(item, at: firstIndex + i)
        }

        renderedDNSServers = servers
    }

    // MARK: - Visibility Preferences

    func applyVisibilityPreferences() {
        let showIPv4 = UserDefaults.standard.bool(for: .showInternalIPv4, default: true)
        let showIPv6 = UserDefaults.standard.bool(for: .showInternalIPv6, default: true)
        ipv4MenuItem?.isHidden = !showIPv4
        ipv6MenuItem?.isHidden = !showIPv6
        let hideSection = !showIPv4 && !showIPv6
        networkSectionSeparator?.isHidden = hideSection
        networkSectionHeader?.isHidden    = hideSection
    }

    // MARK: - Connection Status

    func updateConnectionStatus(_ status: AppState.ConnectionStatus) {
        heroHeaderView?.updateStatus(status)
    }

    // MARK: - External IP / ISP / VPN

    func updateExternalIP(_ ip: String?) {
        lastExternalIP = ip
        heroHeaderView?.updateExternalIP(ip, isVPN: isVPNActive)
    }

    func updateISP(_ isp: String?) {
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
