import SwiftUI
import AppKit
import CoreLocation
import Sparkle

@main
struct OnlineIndicatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, CLLocationManagerDelegate {

    private var statusItem: NSStatusItem!
    private let menuBuilder       = MenuBuilder()
    private let windowCoordinator = WindowCoordinator()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let externalIPFetcher = CachedFetcher.externalIP
    private let ispFetcher        = CachedFetcher.isp

    private var currentStatus: AppState.ConnectionStatus = .noNetwork
    private var hasReportedStatus = false
    private let history = ConnectionHistory()
    private var lastKnownWifiName: String? = nil
    private var locationManager: CLLocationManager?
    private var lastLocationAuthorization: CLAuthorizationStatus?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit-test host launches the full app; don't start monitoring or show UI then.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        if UserDefaults.standard.object(for: .refreshInterval) == nil {
            windowCoordinator.showOnboarding { [weak self] in
                self?.windowCoordinator.dismissOnboarding()
                self?.startApp()
            }
        } else {
            startApp()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Setup

    private func startApp() {
        // The controller is lazy (to stay out of unit tests), so touch it here or the
        // updater, and its automatic checks, wouldn't start until the first manual check.
        _ = updaterController
        windowCoordinator.onCheckForSparkleUpdates = { [weak self] in
            self?.updaterController.checkForUpdates(nil)
        }
        setupStatusItem()

        AppState.shared.statusUpdateHandler = { [weak self] status, addresses in
            guard let self else { return }
            // Skip the first result after launch: it's a baseline, not a change.
            if self.hasReportedStatus && status != self.currentStatus {
                StatusNotifier.statusChanged(to: status)
            }
            self.hasReportedStatus = true
            self.currentStatus = status
            self.applyIcon(for: status, wifiName: addresses.wifiName, isVPNActive: addresses.isVPNActive)
            self.menuBuilder.updateConnectionStatus(status)
            self.history.record(status)
            self.menuBuilder.updateLastOutage(self.history.summary())
            if status == .noNetwork {
                self.menuBuilder.updateProbe(nil)
                self.menuBuilder.resetDNSLookup()
                self.menuBuilder.updateAddresses(IPAddressProvider.Addresses())
                self.menuBuilder.updateExternalIP(nil)
                self.menuBuilder.updateISP(nil)
                self.menuBuilder.updateVPNState(false)
            } else {
                self.menuBuilder.updateVPNState(addresses.isVPNActive)
            }
        }

        AppState.shared.probeResultHandler = { [weak self] result in
            self?.menuBuilder.updateProbe(result)
        }

        AppState.shared.dnsLookupHandler = { [weak self] ms in
            self?.menuBuilder.updateDNSLookup(ms: ms)
        }

        AppState.shared.speedSnapshotHandler = { [weak self] snapshot in
            self?.menuBuilder.updateSpeedSnapshot(snapshot)
        }

        AppState.shared.speedMeasuringChangedHandler = { [weak self] measuring in
            self?.menuBuilder.setSpeedMeasuring(measuring)
        }

        AppState.shared.speedResetHandler = { [weak self] in
            self?.menuBuilder.clearSpeedSnapshot()
        }

        AppState.shared.vpnStatusChangedHandler = { [weak self] addresses in
            guard let self else { return }
            if !addresses.isVPNActive { StatusNotifier.vpnDropped() }
            self.menuBuilder.updateVPNState(addresses.isVPNActive)
            self.updateMenuAddresses(addresses)
            self.invalidateExternalCaches()
            self.fetchExternalData()
            // No ping refresh here: this handler runs inside AppState.checkConnection, which
            // goes on to probe as soon as it returns.
            AppState.shared.refreshSpeedAutomatically()
        }

        AppState.shared.networkAddressesChangedHandler = { [weak self] addresses in
            self?.updateMenuAddresses(addresses)
        }

        AppState.shared.start()

        requestLocationPermissionIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showLaunchTooltip()
        }

        NotificationCenter.default.addObserver(
            forName: .iconPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let addresses = IPAddressProvider.current()
            self.applyIcon(for: self.currentStatus, wifiName: addresses.wifiName, isVPNActive: addresses.isVPNActive)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menuBuilder.onCopyIPv4    = { [weak self] _ in self?.showCopiedTooltip(text: "IPv4 Copied") }
        menuBuilder.onCopyIPv6    = { [weak self] _ in self?.showCopiedTooltip(text: "IPv6 Copied") }
        menuBuilder.onCopyGateway = { [weak self] _ in self?.showCopiedTooltip(text: "Gateway Copied") }
        menuBuilder.onCopyDNS     = { [weak self] _ in self?.showCopiedTooltip(text: "DNS Copied") }
        menuBuilder.onCopyExternalIP = { [weak self] _ in self?.showCopiedTooltip(text: "External IP Copied") }
        // Opening the Apple probe URL makes the portal redirect the browser to its login page.
        menuBuilder.onOpenCaptivePortal = {
            if let url = URL(string: ConnectivityChecker.defaultURLString) { NSWorkspace.shared.open(url) }
        }
        menuBuilder.onRefreshPing = { AppState.shared.forceRefreshPing() }
        menuBuilder.onRefreshSpeed = { AppState.shared.forceRefreshSpeed() }
        menuBuilder.onOpenSettings = { [weak self] in self?.windowCoordinator.openSettings() }
        menuBuilder.onQuit         = { NSApplication.shared.terminate(nil) }

        let menu = menuBuilder.build()
        menu.delegate = self
        statusItem.menu = menu

        applyIcon(for: .noNetwork, wifiName: nil, isVPNActive: false)
    }

    // MARK: - Location Permission (required for Wi-Fi SSID on macOS)

    private func requestLocationPermissionIfNeeded() {
        let lm = CLLocationManager()
        // CLLocationManager reports the current status as soon as a delegate is set; remember it so
        // that initial callback doesn't trigger a second check right after start().
        lastLocationAuthorization = lm.authorizationStatus
        lm.delegate = self
        locationManager = lm
        if lm.authorizationStatus == .notDetermined {
            lm.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != lastLocationAuthorization else { return }
        lastLocationAuthorization = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            AppState.shared.restart()
        default:
            break
        }
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // Menu open always gets a fresh snapshot — this is a user-initiated action.
        let addresses = IPAddressProvider.current()
        updateMenuAddresses(addresses)
        fetchExternalData()
        menuBuilder.applyVisibilityPreferences()
    }

    func menuDidClose(_ menu: NSMenu) {
        // NSMenu does not dispatch mouseExited to custom-view items on close, so hover
        // highlights can persist as stale state. Reset them all here.
        menu.items.compactMap(\.view).forEach { resetHoverViews(in: $0) }
    }

    private func resetHoverViews(in view: NSView) {
        (view as? MenuHoverView)?.resetHighlight()
        view.subviews.forEach { resetHoverViews(in: $0) }
    }

    /// Updates address rows, clearing everything when there is no real connectivity
    /// (no WiFi and no routable IPv4 or IPv6). Detects WiFi drop to immediately clear EXT/ISP.
    private func updateMenuAddresses(_ addresses: IPAddressProvider.Addresses) {
        let hasConnectivity = IPAddressProvider.hasConnectivity(addresses)
        if lastKnownWifiName != nil && addresses.wifiName == nil {
            invalidateExternalCaches()
            menuBuilder.updateExternalIP(nil)
            menuBuilder.updateISP(nil)
        }
        lastKnownWifiName = addresses.wifiName
        menuBuilder.updateAddresses(hasConnectivity ? addresses : IPAddressProvider.Addresses())
    }

    // MARK: - External data helpers

    private func invalidateExternalCaches() {
        externalIPFetcher.invalidateCache()
        ispFetcher.invalidateCache()
    }

    private func fetchExternalData() {
        externalIPFetcher.fetch { [weak self] ip in self?.menuBuilder.updateExternalIP(ip) }
        ispFetcher.fetch { [weak self] isp in self?.menuBuilder.updateISP(isp) }
    }

    // MARK: - Icon

    private func applyIcon(for status: AppState.ConnectionStatus,
                            wifiName: String?,
                            isVPNActive: Bool) {
        guard let button = statusItem.button else { return }

        guard let output = StatusIconRenderer.render(
            for: status,
            wifiName: wifiName,
            isVPNActive: isVPNActive
        ) else { return }

        button.toolTip = output.toolTip
        button.setAccessibilityLabel(output.accessibilityLabel)

        if let label = output.attributedLabel {
            button.image           = nil
            button.imagePosition   = .noImage
            button.attributedTitle = label
        } else {
            let barHeight  = NSStatusBar.system.thickness
            let iconSize   = output.tintedImage.size
            let finalImage = NSImage(size: NSSize(width: barHeight, height: barHeight),
                                     flipped: false) { rect in
                let ox = (rect.width  - iconSize.width)  / 2
                let oy = (rect.height - iconSize.height) / 2
                output.tintedImage.draw(in: NSRect(x: ox, y: oy,
                                                   width: iconSize.width, height: iconSize.height))
                return true
            }
            finalImage.isTemplate  = false
            button.image           = finalImage
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition   = .imageOnly
        }
    }

    // MARK: - Popovers

    private func showStatusPopover<Content: View>(content: Content, autoDismissAfter delay: Double) {
        guard let button = statusItem.button else { return }

        let hostingView = NSHostingView(rootView: content)
        let size        = sanitizedPopoverSize(for: hostingView)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let controller = NSViewController()
        controller.view = hostingView

        let popover = NSPopover()
        popover.behavior            = .transient
        popover.animates            = true
        popover.contentSize         = size
        popover.contentViewController = controller

        let anchor = NSRect(x: button.bounds.midX - 1, y: 0, width: 2, height: button.bounds.height)
        popover.show(relativeTo: anchor, of: button, preferredEdge: .minY)

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { popover.performClose(nil) }
        }
    }

    /// SwiftUI can occasionally report non-positive fitting sizes during transient popover creation.
    /// Clamp to safe minimums to avoid AppKit "Invalid view geometry" warnings.
    private func sanitizedPopoverSize<Content: View>(for hostingView: NSHostingView<Content>) -> NSSize {
        hostingView.layoutSubtreeIfNeeded()
        let measured = hostingView.fittingSize
        let minWidth: CGFloat = 80
        let minHeight: CGFloat = 24

        let width = measured.width.isFinite && measured.width > 0 ? measured.width : minWidth
        let height = measured.height.isFinite && measured.height > 0 ? measured.height : minHeight
        return NSSize(width: width, height: height)
    }

    private func showCopiedTooltip(text: String) {
        let content = HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.system(size: 13))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        showStatusPopover(content: content, autoDismissAfter: 1.5)
    }

    private func showLaunchTooltip() {
        let content = Text("\(AppInfo.appName) is running")
            .font(.system(size: 13))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        showStatusPopover(content: content, autoDismissAfter: 2.0)
    }
}
