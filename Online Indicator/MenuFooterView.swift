import AppKit

/// Two-button footer: "Settings" on the left, "Quit" on the right.
/// Each button is a custom clickable view so we can precisely center
/// the icon + label pair — NSButton's built-in layout doesn't reliably
/// center icon+title within wide bounds.
final class MenuFooterView: NSView {

    var onSettings: (() -> Void)?
    var onQuit:     (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer       = true
        autoresizingMask = .width

        // Top separator
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        let settingsBtn = makeFooterButton(
            symbolName: "sun.min",
            title: "Settings",
            tintColor: .labelColor,
            action: { [weak self] in self?.onSettings?() }
        )

        let quitBtn = makeFooterButton(
            symbolName: "rectangle.portrait.and.arrow.right",
            title: "Quit",
            tintColor: .white,
            action: { [weak self] in self?.onQuit?() }
        )

        // Vertical divider
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            sep.heightAnchor.constraint(equalToConstant: 1),

            settingsBtn.leadingAnchor.constraint(equalTo: leadingAnchor),
            settingsBtn.topAnchor.constraint(equalTo: sep.bottomAnchor),
            settingsBtn.bottomAnchor.constraint(equalTo: bottomAnchor),
            settingsBtn.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),

            divider.leadingAnchor.constraint(equalTo: settingsBtn.trailingAnchor),
            divider.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 8),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            divider.widthAnchor.constraint(equalToConstant: 1),

            quitBtn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            quitBtn.trailingAnchor.constraint(equalTo: trailingAnchor),
            quitBtn.topAnchor.constraint(equalTo: sep.bottomAnchor),
            quitBtn.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Returns a fully laid-out, clickable button view with the icon immediately
    /// beside the label, the pair centered within the button area.
    private func makeFooterButton(symbolName: String,
                                   title: String,
                                   tintColor: NSColor,
                                   action: @escaping () -> Void) -> MenuFooterButtonView {
        let btn = MenuFooterButtonView(symbolName: symbolName, title: title, tintColor: tintColor)
        btn.onTap = action
        btn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(btn)
        return btn
    }
}

// MARK: - MenuFooterButtonView

/// A single button cell inside `MenuFooterView`. The icon is embedded as an
/// `NSTextAttachment` in the label's attributed string so it baseline-aligns
/// with the text automatically, avoiding SF Symbol template whitespace issues.
private final class MenuFooterButtonView: MenuHoverView {

    var onTap: (() -> Void)?

    init(symbolName: String, title: String, tintColor: NSColor) {
        super.init(frame: .zero)

        addSubview(highlightView)
        NSLayoutConstraint.activate([
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            highlightView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])

        let font = NSFont.systemFont(ofSize: 13)
        let iconSize: CGFloat = 13

        // Use paletteColors to tint the SF Symbol — consistent with StatusIconRenderer.
        let symConfig = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tintColor]))
        let tintedIcon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(symConfig)

        // Embed the icon as a text attachment so it sits on the same baseline as the title.
        // The bounds offset centers it on the font's cap height.
        let attachment = NSTextAttachment()
        attachment.image = tintedIcon
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - iconSize) / 2,
                                   width: iconSize, height: iconSize)

        let str = NSMutableAttributedString(attachment: attachment)
        str.append(NSAttributedString(string: " \(title)",
                                      attributes: [.font: font, .foregroundColor: tintColor]))

        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = str
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onTap?() }
}
