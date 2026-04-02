import AppKit

/// A menu row: left-aligned label (secondary color) + right-aligned monospace
/// value (primary color). Highlights on hover and fires `onCopy` on click.
final class MenuInfoRowView: MenuHoverView {

    var onCopy: (() -> Void)?

    private let labelField = NSTextField(labelWithString: "")
    private let valueField = NSTextField(labelWithString: "")

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
            labelField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.heroLeadingPadding),
            labelField.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelField.trailingAnchor.constraint(lessThanOrEqualTo: valueField.leadingAnchor, constant: -8),

            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.heroLeadingPadding),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.60),
        ])
    }

    func configure(label: String, value: String, available: Bool) {
        labelField.stringValue = label
        valueField.stringValue = value
        valueField.textColor   = available ? .labelColor : .tertiaryLabelColor
    }

    override func mouseDown(with event: NSEvent) { onCopy?() }
}
