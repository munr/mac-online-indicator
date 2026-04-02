import AppKit

/// Three-column stats bar: DOWN | UP | PING, with fractional auto-layout columns.
/// Clicking anywhere refreshes speed and ping.
final class MenuStatsBarView: MenuHoverView {

    var onRefresh: (() -> Void)?

    private let downValueLabel = NSTextField(labelWithString: menuNoValue)
    private let downUnitLabel  = NSTextField(labelWithString: "")
    private let upValueLabel   = NSTextField(labelWithString: menuNoValue)
    private let upUnitLabel    = NSTextField(labelWithString: "")
    private let pingValueLabel = NSTextField(labelWithString: menuNoValue)
    private let pingUnitLabel  = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        addSubview(highlightView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])

        // Top separator
        let sep = makeSeparator()
        addSubview(sep)

        // Configure value and unit labels
        configure(downValueLabel,  font: .systemFont(ofSize: 22, weight: .semibold))
        configure(upValueLabel,    font: .systemFont(ofSize: 22, weight: .semibold))
        configure(pingValueLabel,  font: .systemFont(ofSize: 22, weight: .semibold))
        configure(downUnitLabel,   font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        configure(upUnitLabel,     font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)
        configure(pingUnitLabel,   font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor)

        // Each column is a vertical stack: header, value, unit — centered horizontally.
        let col1 = makeColumnStack(header: "DOWN", value: downValueLabel, unit: downUnitLabel)
        let col2 = makeColumnStack(header: "UP",   value: upValueLabel,   unit: upUnitLabel)
        let col3 = makeColumnStack(header: "PING", value: pingValueLabel, unit: pingUnitLabel)

        let div1 = makeSeparator(vertical: true)
        let div2 = makeSeparator(vertical: true)

        [col1, col2, col3, div1, div2].forEach { addSubview($0) }

        NSLayoutConstraint.activate([
            // Top separator
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            // Three equal columns
            col1.leadingAnchor.constraint(equalTo: leadingAnchor),
            col1.topAnchor.constraint(equalTo: sep.bottomAnchor),
            col1.bottomAnchor.constraint(equalTo: bottomAnchor),
            col1.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 1.0 / 3.0),

            col2.leadingAnchor.constraint(equalTo: col1.trailingAnchor),
            col2.topAnchor.constraint(equalTo: col1.topAnchor),
            col2.bottomAnchor.constraint(equalTo: col1.bottomAnchor),
            col2.widthAnchor.constraint(equalTo: col1.widthAnchor),

            col3.leadingAnchor.constraint(equalTo: col2.trailingAnchor),
            col3.topAnchor.constraint(equalTo: col1.topAnchor),
            col3.bottomAnchor.constraint(equalTo: col1.bottomAnchor),
            col3.trailingAnchor.constraint(equalTo: trailingAnchor),

            // Vertical dividers
            div1.leadingAnchor.constraint(equalTo: col1.trailingAnchor),
            div1.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 10),
            div1.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            div1.widthAnchor.constraint(equalToConstant: 1),

            div2.leadingAnchor.constraint(equalTo: col2.trailingAnchor),
            div2.topAnchor.constraint(equalTo: div1.topAnchor),
            div2.bottomAnchor.constraint(equalTo: div1.bottomAnchor),
            div2.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    /// Returns a vertical NSStackView with the header, value, and unit labels centered.
    private func makeColumnStack(header: String, value: NSTextField, unit: NSTextField) -> NSStackView {
        let headerLabel = NSTextField(labelWithString: header)
        headerLabel.font      = .systemFont(ofSize: 10, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.alignment = .center
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let col = NSStackView(views: [headerLabel, value, unit])
        col.orientation  = .vertical
        col.alignment    = .centerX
        col.spacing      = 2
        col.edgeInsets   = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        col.translatesAutoresizingMaskIntoConstraints = false
        return col
    }

    private func configure(_ field: NSTextField,
                            font: NSFont,
                            color: NSColor = .labelColor) {
        field.font      = font
        field.textColor = color
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeSeparator(vertical: Bool = false) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    // MARK: - Updates

    func reset() {
        downValueLabel.stringValue = menuNoValue; downUnitLabel.stringValue = ""
        upValueLabel.stringValue   = menuNoValue; upUnitLabel.stringValue   = ""
        pingValueLabel.stringValue = menuNoValue; pingUnitLabel.stringValue = ""
    }

    func setUpdating() {
        downValueLabel.stringValue = "…"; downUnitLabel.stringValue = ""
        upValueLabel.stringValue   = "…"; upUnitLabel.stringValue   = ""
    }

    func updatePing(_ ms: Double?) {
        if let ms {
            pingValueLabel.stringValue = String(format: "%.0f", ms)
            pingUnitLabel.stringValue  = "ms"
        } else {
            pingValueLabel.stringValue = menuNoValue
            pingUnitLabel.stringValue  = ""
        }
    }

    func updateSpeed(download: Double?, upload: Double?) {
        if let dl = download {
            let (v, u) = formatSpeed(dl)
            downValueLabel.stringValue = v; downUnitLabel.stringValue = u
        } else {
            downValueLabel.stringValue = menuNoValue; downUnitLabel.stringValue = ""
        }
        if let ul = upload {
            let (v, u) = formatSpeed(ul)
            upValueLabel.stringValue = v; upUnitLabel.stringValue = u
        } else {
            upValueLabel.stringValue = menuNoValue; upUnitLabel.stringValue = ""
        }
    }

    private func formatSpeed(_ mbps: Double) -> (String, String) {
        switch mbps {
        case 100...:  return (String(format: "%.0f", mbps), "Mbps")
        case 10...:   return (String(format: "%.1f", mbps), "Mbps")
        case 1...:    return (String(format: "%.2f", mbps), "Mbps")
        default:      return (String(format: "%.0f", mbps * 1000), "Kbps")
        }
    }

    override func mouseDown(with event: NSEvent) { onRefresh?() }
}
