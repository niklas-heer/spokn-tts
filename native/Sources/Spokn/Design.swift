import AppKit

/// The tracking region stays present while its controls fade, so hovering restores them.
final class HoverControlsView: NSView {
    private let dimmedAlpha: CGFloat
    private var area: NSTrackingArea?
    private var keyboardReveal: DispatchWorkItem?
    private var keyboardActive = false
    private(set) var hovered = false
    private(set) var revealed = true
    var onReveal: ((Bool) -> Void)?
    var fadesWhenIdle = false { didSet { updateVisibility() } }
    init(dimmedAlpha: CGFloat) {
        self.dimmedAlpha = dimmedAlpha
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    isolated deinit { keyboardReveal?.cancel() }
    func install(_ content: NSView) {
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking); area = tracking
        if let window { setHovered(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))) }
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func setHovered(_ value: Bool) { hovered = value; updateVisibility() }
    func revealForKeyboard() {
        keyboardReveal?.cancel(); keyboardActive = true; updateVisibility()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Keep keyboard-focused controls visible until focus leaves them.
            if let responder = self.window?.firstResponder as? NSView, responder.isDescendant(of: self) {
                self.revealForKeyboard(); return
            }
            self.keyboardActive = false; self.updateVisibility()
        }
        keyboardReveal = work; DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
    private func updateVisibility() {
        let visible = !fadesWhenIdle || hovered || keyboardActive || NSWorkspace.shared.isVoiceOverEnabled
        guard revealed != visible else { return }
        revealed = visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            subviews.first?.animator().alphaValue = visible ? 1 : dimmedAlpha
        }
        onReveal?(visible)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if !revealed, dimmedAlpha == 0 { return nil }
        return super.hitTest(point)
    }
}

enum Design {
    nonisolated static let accent = NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.91, green: 0.56, blue: 0.39, alpha: 1) : NSColor(srgbRed: 0.70, green: 0.31, blue: 0.20, alpha: 1) }
    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color; label.lineBreakMode = .byTruncatingTail; return label
    }
    static func symbol(_ name: String, _ description: String, size: CGFloat = 16) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?.withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
    static func button(_ symbol: String, label: String, target: AnyObject?, action: Selector, size: CGFloat = 16) -> NSButton {
        let button = NSButton(image: self.symbol(symbol, label, size: size) ?? NSImage(), target: target, action: action)
        button.bezelStyle = .texturedRounded; button.isBordered = false; button.contentTintColor = .secondaryLabelColor
        button.toolTip = label; button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 32), button.heightAnchor.constraint(equalToConstant: 32)])
        return button
    }
    static func stack(_ views: [NSView], orientation: NSUserInterfaceLayoutOrientation = .vertical, spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = orientation; stack.spacing = spacing; stack.alignment = orientation == .vertical ? .leading : .centerY; stack.translatesAutoresizingMaskIntoConstraints = false; return stack
    }
    static func symbolView(_ name: String) -> NSImageView {
        let view = NSImageView(image: symbol(name, "Reading speed", size: 13) ?? NSImage())
        view.contentTintColor = .secondaryLabelColor
        return view
    }
}

final class WaveView: NSView {
    var color = Design.accent
    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 34) }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: dirtyRect).addClip()
        color.setFill()
        for (index, height) in [10.0, 21, 30, 17, 8].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: CGFloat(index) * 6 + 1, y: (bounds.height - height) / 2, width: 3, height: height), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
}

final class PanelSurface: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 20; layer?.masksToBounds = true; layer?.borderWidth = 1
        updateColors()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateColors() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.12, green: 0.125, blue: 0.14, alpha: 1) : NSColor(srgbRed: 0.975, green: 0.97, blue: 0.96, alpha: 1)).cgColor
        layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.13) : NSColor.black.withAlphaComponent(0.1)).cgColor
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateColors() }
}

final class SpeedSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let first = rectOfTickMark(at: 0).midX
        let last = rectOfTickMark(at: numberOfTickMarks - 1).midX
        let centerY = knobRect(flipped: flipped).midY
        let track = NSRect(x: first, y: centerY - 3, width: last - first, height: 6)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let fraction = CGFloat((doubleValue - minValue) / max(0.001, maxValue - minValue))
        Design.accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: first, y: track.minY, width: track.width * fraction, height: 6), xRadius: 3, yRadius: 3).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let circle = NSRect(x: knobRect.midX - 8, y: knobRect.midY - 8, width: 16, height: 16)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 3; shadow.shadowOffset = NSSize(width: 0, height: -1); shadow.set()
        NSColor.white.setFill(); NSBezierPath(ovalIn: circle).fill()
        shadow.shadowColor = .clear; shadow.set()
        Design.accent.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: circle.insetBy(dx: 5.5, dy: 5.5)).fill()
    }
}

final class SpeedScaleView: NSView {
    private weak var slider: NSSlider?
    init(slider: NSSlider) {
        self.slider = slider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        guard let slider else { return }
        let values = ["0.5×", "", "1× Normal", "", "1.5×", "", "2×"]
        for (index, value) in values.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: index == 2 ? .semibold : .regular),
                .foregroundColor: index == 2 ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
            let text = value as NSString
            let size = text.size(withAttributes: attributes)
            let center = slider.rectOfTickMark(at: index).midX
            text.draw(at: NSPoint(x: center - size.width / 2, y: 1), withAttributes: attributes)
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
