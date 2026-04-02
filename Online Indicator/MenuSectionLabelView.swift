import AppKit

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
