import AppKit
import SwiftUI

/// Manages the lifecycle of the onboarding and settings windows.
/// Conforms to NSWindowDelegate to nil-out the settings window reference on close.
final class WindowCoordinator: NSObject, NSWindowDelegate {

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // MARK: - Onboarding

    func showOnboarding(onStart: @escaping () -> Void) {
        let view = OnboardingView {
            onStart()
        }
        let window = makeWindow(
            size: NSSize(width: 420, height: 480),
            styleMask: [.titled, .closable]
        )
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    // MARK: - Settings

    func openSettings() {
        if let existing = settingsWindow {
            bringSettingsWindowToFront(existing)
            return
        }

        let window = makeWindow(
            size: NSSize(width: 440, height: 580),
            styleMask: [.titled, .closable]
        )
        window.title = AppInfo.appName
        window.contentView = NSHostingView(rootView: SettingsView())
        window.delegate = self
        settingsWindow = window
        bringSettingsWindowToFront(window)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }

    // MARK: - Private

    private func makeWindow(size: NSSize, styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    private func bringSettingsWindowToFront(_ window: NSWindow) {
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKey()
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .settingsWindowDidBecomeKey, object: nil)
    }
}
