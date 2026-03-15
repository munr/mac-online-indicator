import SwiftUI
import AppKit

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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let menuBuilder       = MenuBuilder()
    private let windowCoordinator = WindowCoordinator()

    private var currentStatus: AppState.ConnectionStatus = .noNetwork

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        setupStatusItem()

        AppState.shared.statusUpdateHandler = { [weak self] status in
            self?.currentStatus = status
            self?.applyIcon(for: status)
        }

        AppState.shared.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showLaunchTooltip()
        }

        UpdateChecker.checkIfNeeded { _ in
            // Result is persisted; SettingsView reads the cache on next open.
        }

        NotificationCenter.default.addObserver(
            forName: .iconPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.applyIcon(for: self.currentStatus)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menuBuilder.onCopyIPv4     = { [weak self] _ in self?.showCopiedTooltip(text: "IPv4 Copied") }
        menuBuilder.onCopyIPv6     = { [weak self] _ in self?.showCopiedTooltip(text: "IPv6 Copied") }
        menuBuilder.onOpenSettings = { [weak self] in self?.windowCoordinator.openSettings() }
        menuBuilder.onQuit         = { NSApplication.shared.terminate(nil) }

        let menu = menuBuilder.build()
        menu.delegate = self
        statusItem.menu = menu

        applyIcon(for: .noNetwork)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menuBuilder.updateAddresses(IPAddressProvider.current())
    }

    // MARK: - Icon

    private func applyIcon(for status: AppState.ConnectionStatus) {
        guard let button = statusItem.button else { return }

        let wifiName = IPAddressProvider.current().wifiName
        guard let output = StatusIconRenderer.render(for: status, wifiName: wifiName) else { return }

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
        let size        = hostingView.fittingSize
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
