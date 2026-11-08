import AppKit
import SwiftUI

/// Manages the lifecycle of the onboarding and settings windows.
/// Conforms to NSWindowDelegate to nil-out the settings window reference on close and to
/// start monitoring if onboarding is closed without pressing Start.
final class WindowCoordinator: NSObject, NSWindowDelegate {

    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingStart: (() -> Void)?

    /// Wired by `AppDelegate` to Sparkle’s manual “Check for Updates” action.
    var onCheckForSparkleUpdates: (() -> Void)?

    // MARK: - Onboarding

    func showOnboarding(onStart: @escaping () -> Void) {
        onboardingStart = onStart
        let view = OnboardingView {
            onStart()
        }
        let window = makeWindow(
            size: NSSize(width: 420, height: 480),
            styleMask: [.titled, .closable]
        )
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissOnboarding() {
        let window = onboardingWindow
        onboardingWindow = nil   // cleared first so windowWillClose doesn't treat this as a dismissal
        onboardingStart = nil
        window?.close()
    }

    // MARK: - Settings

    func openSettings() {
        if let existing = settingsWindow {
            bringSettingsWindowToFront(existing)
            return
        }

        let window = makeWindow(
            size: NSSize(width: 440, height: 600),
            styleMask: [.titled, .closable, .resizable]
        )
        window.title = AppInfo.appName
        let settings = SettingsView(checkForSparkleUpdates: { [weak self] in
            self?.onCheckForSparkleUpdates?()
        })
        window.contentView = NSHostingView(rootView: settings)
        window.delegate = self
        settingsWindow = window
        bringSettingsWindowToFront(window)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === onboardingWindow, let start = onboardingStart {
            // Closed with the red button instead of "Start Monitoring": without this the
            // app would keep running with no menu bar item. Start with the default interval.
            if UserDefaults.standard.object(for: .refreshInterval) == nil {
                UserDefaults.standard.set(30.0, for: .refreshInterval)
            }
            onboardingWindow = nil
            onboardingStart = nil
            start()
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .settingsWindowDidBecomeKey, object: nil)
    }
}
