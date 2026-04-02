import AppKit

/// Card-style hero header: circular icon on the left; network name + status dot,
/// ISP, and external IP stacked on the right.
final class MenuHeroHeaderView: NSView {

    var onOpenWiFiSettings: (() -> Void)?

    private let nameLabel    = NSTextField(labelWithString: "")
    private let ispLabel     = NSTextField(labelWithString: "")
    private let extIPLabel   = NSTextField(labelWithString: "")
    private let vpnBadgeView = VPNBadgeView()
    private weak var statusDotView: NSView?
    private weak var iconBgView: NSView?
    private var ringLayer: CAShapeLayer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        // ── Circular icon ──────────────────────────────────────────────────
        let iconSize = MenuLayout.heroIconSize
        let iconBg = NSView()
        iconBg.wantsLayer = true
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.layer?.cornerRadius    = iconSize / 2
        iconBg.layer?.masksToBounds   = true
        iconBg.layer?.backgroundColor = NSColor(named: "HeroIconBackground")?.cgColor
        addSubview(iconBg)
        iconBgView = iconBg

        // Partial-arc ring layer drawn on top of iconBg, parented to self.layer
        // so it isn't clipped by iconBg's masksToBounds.
        // Path is set/updated in layout() once Auto Layout has resolved iconBg.frame.
        let ring = CAShapeLayer()
        ring.fillColor   = nil
        ring.lineWidth   = MenuLayout.ringStrokeWidth
        ring.lineCap     = .round
        ring.strokeStart = 0
        ring.strokeEnd   = 0
        // Disable all implicit animations on this layer
        ring.actions = ["strokeEnd": NSNull(), "strokeColor": NSNull(), "path": NSNull()]
        ringLayer = ring

        let iconImageView = NSImageView()
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling  = .scaleProportionallyDown
        let symConfig = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        iconImageView.image         = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                                              accessibilityDescription: nil)?
                                        .withSymbolConfiguration(symConfig)
        iconImageView.contentTintColor = NSColor(named: "HeroIconTint")
        iconBg.addSubview(iconImageView)

        // ── Status dot ─────────────────────────────────────────────────────
        let dot = NSView()
        dot.wantsLayer = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.layer?.cornerRadius  = 5
        dot.layer?.masksToBounds = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor  // set properly on first status update
        addSubview(dot)
        statusDotView = dot

        // ── Text labels ────────────────────────────────────────────────────
        nameLabel.font      = .systemFont(ofSize: 15, weight: .bold)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        ispLabel.font      = .systemFont(ofSize: 12, weight: .regular)
        ispLabel.textColor = .secondaryLabelColor
        ispLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ispLabel)

        extIPLabel.font      = .systemFont(ofSize: 12, weight: .regular)
        extIPLabel.textColor = .secondaryLabelColor
        extIPLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(extIPLabel)

        vpnBadgeView.isHidden = true
        vpnBadgeView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(vpnBadgeView)

        // ── Layout ─────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            iconBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.heroLeadingPadding),
            iconBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: iconSize),
            iconBg.heightAnchor.constraint(equalToConstant: iconSize),

            iconImageView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),

            // Name + dot sit on the same baseline
            nameLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 14),
            nameLabel.topAnchor.constraint(equalTo: iconBg.topAnchor, constant: 6),

            dot.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            dot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor, constant: -1),
            dot.widthAnchor.constraint(equalToConstant: 9),
            dot.heightAnchor.constraint(equalToConstant: 9),

            ispLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            ispLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),

            extIPLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            extIPLabel.topAnchor.constraint(equalTo: ispLabel.bottomAnchor, constant: 3),

            vpnBadgeView.leadingAnchor.constraint(equalTo: extIPLabel.trailingAnchor, constant: 6),
            vpnBadgeView.centerYAnchor.constraint(equalTo: extIPLabel.centerYAnchor),
        ])

        nameLabel.stringValue  = Host.current().localizedName ?? "Mac"
        ispLabel.stringValue   = menuNoValue
        extIPLabel.stringValue = menuNoValue

        // Add ring as sublayer of self after wantsLayer = true ensures self.layer exists
        if let ring = ringLayer { layer?.addSublayer(ring) }
    }

    override func layout() {
        super.layout()
        updateRingPath()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        iconBgView?.layer?.backgroundColor = NSColor(named: "HeroIconBackground")?.cgColor
    }

    private func updateRingPath() {
        guard let ring = ringLayer, let iconBg = iconBgView else { return }
        guard iconBg.frame.width > 0 else { return }
        // Slightly outside the circle so the stroke doesn't overlap the icon background
        let radius = iconBg.frame.width / 2 + MenuLayout.ringStrokeWidth
        let center = CGPoint(x: iconBg.frame.midX, y: iconBg.frame.midY)
        let path   = CGMutablePath()
        // Start at 12 o'clock (π/2 in macOS Y-up coords) and go clockwise
        path.addArc(center: center, radius: radius,
                    startAngle: .pi / 2,
                    endAngle:   .pi / 2 - 2 * .pi,
                    clockwise:  true)
        ring.path = path
    }

    // MARK: - Updates

    func updateStatus(_ status: AppState.ConnectionStatus) {
        let color: NSColor
        switch status {
        case .connected:  color = .systemGreen
        case .blocked:    color = .systemOrange
        case .noNetwork:  color = .systemRed
        }
        statusDotView?.layer?.backgroundColor = color.cgColor
    }

    func updateNetwork(name: String?) {
        nameLabel.stringValue = name ?? Host.current().localizedName ?? "Mac"
    }

    func updateISP(_ isp: String?) {
        ispLabel.stringValue = isp ?? menuNoValue
    }

    func updateExternalIP(_ ip: String?, isVPN: Bool) {
        extIPLabel.stringValue = ip ?? menuNoValue
        vpnBadgeView.isHidden = !isVPN || ip == nil
    }

    func updateWiFiStrength(_ rssi: Int?) {
        guard let ring = ringLayer else { return }
        if let rssi {
            // Map RSSI to a 0–1 coverage fraction.
            // -50 dBm (excellent) → 1.0, -90 dBm (unusable) → 0.0
            let fraction = CGFloat((Double(rssi) + WiFiThreshold.rssiOffset) / WiFiThreshold.rssiRange).clamped(to: 0...1)
            let color: NSColor
            switch rssi {
            case WiFiThreshold.excellent...: color = .systemGreen
            case WiFiThreshold.good...:      color = .systemYellow
            case WiFiThreshold.fair...:      color = .systemOrange
            default:                         color = .systemRed
            }
            ring.strokeColor = color.cgColor
            ring.strokeEnd   = fraction
        } else {
            ring.strokeEnd = 0
        }
    }

    // MARK: - Click → open WiFi settings

    override func mouseDown(with event: NSEvent) {
        onOpenWiFiSettings?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }
}

// MARK: - VPNBadgeView

/// A small pill-shaped badge displaying "VPN" in system blue.
private final class VPNBadgeView: NSView {

    private var cornerRadiusSet = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth       = 0.5
        layer?.borderColor       = NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        layer?.backgroundColor   = NSColor.systemBlue.withAlphaComponent(0.18).cgColor

        let label = NSTextField(labelWithString: "VPN")
        label.font      = .monospacedSystemFont(ofSize: 9, weight: .semibold)
        label.textColor = .systemBlue
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard !cornerRadiusSet, bounds.height > 0 else { return }
        layer?.cornerRadius = bounds.height / 2
        cornerRadiusSet = true
    }
}
