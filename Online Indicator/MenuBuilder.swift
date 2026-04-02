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

    var onCopyIPv4:    ((String) -> Void)?
    var onCopyIPv6:    ((String) -> Void)?
    var onCopyGateway: ((String) -> Void)?
    var onCopyDNS:     ((String) -> Void)?
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
        ipv4Row.configure(label: "Internal IPv4", value: menuNoValue, available: false)
        ipv4Row.onCopy = { [weak self] in
            guard let self, let v = self.lastIPv4 else { return }
            self.copyToPasteboard(v, callback: self.onCopyIPv4)
        }
        ipv4RowView = ipv4Row
        let ipv4Item = NSMenuItem()
        ipv4Item.view = ipv4Row
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
