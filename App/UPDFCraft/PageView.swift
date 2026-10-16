import AppKit

/// Bitta sahifa: layer-backed view, bitmap `CALayer.contents` orqali ko'rsatiladi.
/// Frame — sahifa o'lchami punktlarda; bitmap ixtiyoriy masshtabda bo'lishi mumkin,
/// layer uni frame'ga moslaydi. M1'da bu yerga tile layer'lar va overlay'lar qo'shiladi.
@MainActor
final class PageView: NSView {
    var image: CGImage? {
        didSet { needsDisplay = true }
    }

    /// Oyna boshqa zichlikdagi ekranga o'tganda (Retina ↔ oddiy) chaqiriladi.
    var onBackingChange: (() -> Void)?

    init(pageSize: CGSize) {
        super.init(frame: NSRect(origin: .zero, size: pageSize))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        self.shadow = shadow

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Sahifa 1")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) ishlatilmaydi")
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var isOpaque: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onBackingChange?()
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.white.cgColor
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear
        layer.contents = image
    }
}
