import SwiftUI
import AppKit

/// Short-lived popovers anchored under the status item (the "Copied" and launch tooltips).
enum StatusPopover {

    static func show<Content: View>(_ content: Content, from button: NSStatusBarButton?, autoDismissAfter delay: Double) {
        guard let button else { return }

        let hostingView = NSHostingView(rootView: content)
        let size        = sanitizedSize(for: hostingView)
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
    private static func sanitizedSize<Content: View>(for hostingView: NSHostingView<Content>) -> NSSize {
        hostingView.layoutSubtreeIfNeeded()
        let measured = hostingView.fittingSize
        let minWidth: CGFloat = 80
        let minHeight: CGFloat = 24

        let width = measured.width.isFinite && measured.width > 0 ? measured.width : minWidth
        let height = measured.height.isFinite && measured.height > 0 ? measured.height : minHeight
        return NSSize(width: width, height: height)
    }
}
