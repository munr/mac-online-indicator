import AppKit

/// Base class for interactive menu rows that show a selection highlight on hover.
/// Subclasses inherit the highlight view, tracking area management, and enter/exit
/// handlers — they only need to add `highlightView` to their layout and handle `mouseDown`.
class MenuHoverView: NSView {

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
