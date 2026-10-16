import AppKit
import CraftKit

/// Hujjat oynasi. Tab'lar — native `NSWindow` tabbing (reja §3.3).
@MainActor
final class DocumentWindowController: NSWindowController {
    init(model: DocumentModel) {
        let contentRect = Self.initialContentRect(for: model)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "UPDFCraftDocument"
        window.minSize = NSSize(width: 320, height: 240)
        window.subtitle = model.pageCount == 1 ? "1 sahifa" : "\(model.pageCount) sahifa"
        // contentViewController oynani view o'lchamiga moslaydi, shuning uchun view
        // boshlang'ich o'lcham bilan yaratiladi.
        window.contentViewController = CanvasViewController(model: model,
                                                            initialSize: contentRect.size)
        window.center()
        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) ishlatilmaydi")
    }

    /// Birinchi sahifa ekranning ko'rinadigan qismiga sig'adigan o'lcham.
    private static func initialContentRect(for model: DocumentModel) -> NSRect {
        let page = model.pageSizes.first ?? CGSize(width: 612, height: 792)
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let margin = CanvasViewController.pageMargin * 2
        let maxHeight = visible.height * 0.9
        let maxWidth = visible.width * 0.8
        let fit = min(1, (maxHeight - margin) / page.height, (maxWidth - margin) / page.width)
        let size = CGSize(width: max(480, page.width * fit + margin),
                          height: max(360, page.height * fit + margin))
        return NSRect(origin: .zero, size: size)
    }
}
