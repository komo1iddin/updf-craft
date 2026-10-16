import AppKit
import CraftKit

/// M0 canvas: `NSScrollView` ichida bitta sahifa (birinchi). Foydalanuvchi zoom qilmaguncha
/// sahifa oynaga sig'diriladi (fit). Pinch/zoom'da `NSScrollView` magnification
/// ishlatiladi; zoom yoki oyna o'lchamini o'zgartirish tugagach sahifa yangi masshtabda
/// qayta chiziladi. Tile'lar va continuous rejim — M1 (reja §3.4).
@MainActor
final class CanvasViewController: NSViewController {
    static let pageMargin: CGFloat = 24
    /// Bitta bitmap'ning eng katta tomoni (piksel) — tile'larsiz render uchun chegara.
    private static let maxBitmapDimension: CGFloat = 8192

    let model: DocumentModel
    private let pageIndex = 0
    private let scrollView = NSScrollView()
    private let pageView: PageView
    private var renderTask: Task<Void, Never>?
    private var renderedScale: CGFloat = 0
    /// Foydalanuvchi o'zi zoom qilmaguncha sahifa oynaga sig'diriladi.
    private var fitsToWindow = true

    private let initialSize: CGSize

    init(model: DocumentModel, initialSize: CGSize) {
        self.model = model
        self.initialSize = initialSize
        let size = model.pageSizes.first ?? CGSize(width: 612, height: 792)
        self.pageView = PageView(pageSize: size)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) ishlatilmaydi")
    }

    override func loadView() {
        let margin = Self.pageMargin
        let container = NSView(frame: NSRect(
            x: 0, y: 0,
            width: pageView.frame.width + margin * 2,
            height: pageView.frame.height + margin * 2))
        pageView.setFrameOrigin(NSPoint(x: margin, y: margin))
        pageView.onBackingChange = { [weak self] in self?.renderIfNeeded() }
        container.addSubview(pageView)

        scrollView.frame = NSRect(origin: .zero, size: initialSize)
        scrollView.contentView = CenteringClipView()
        scrollView.documentView = container
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .underPageBackgroundColor
        view = scrollView

        NotificationCenter.default.addObserver(
            self, selector: #selector(magnificationDidEnd(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if let window = view.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(liveResizeDidEnd(_:)),
                name: NSWindow.didEndLiveResizeNotification, object: window)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if fitsToWindow {
            fitPage()
        }
        if !view.inLiveResize {
            renderIfNeeded()
        }
    }

    @objc private func magnificationDidEnd(_ notification: Notification) {
        fitsToWindow = false
        renderIfNeeded()
    }

    @objc private func liveResizeDidEnd(_ notification: Notification) {
        renderIfNeeded()
    }

    private func fitPage() {
        guard let documentView = scrollView.documentView else { return }
        let available = scrollView.contentSize
        let content = documentView.frame.size
        guard content.width > 0, content.height > 0, available.width > 0 else { return }
        let fit = min(1, available.width / content.width, available.height / content.height)
        if abs(scrollView.magnification - fit) > 0.001 {
            scrollView.magnification = fit
        }
    }

    /// Joriy ekran masshtabi (backing × magnification) bilan chizilmagan bo'lsa, qayta chizadi.
    private func renderIfNeeded() {
        guard let window = view.window else { return }
        let pageSize = pageView.frame.size
        let wanted = window.backingScaleFactor * scrollView.magnification
        let cap = Self.maxBitmapDimension / max(pageSize.width, pageSize.height)
        let scale = min(wanted, cap)
        guard abs(scale - renderedScale) > 0.01 else { return }

        renderTask?.cancel()
        renderTask = Task { [weak self, model, pageIndex] in
            do {
                let image = try await model.renderPage(pageIndex, scale: scale)
                guard let self, !Task.isCancelled else { return }
                self.pageView.image = image
                self.renderedScale = scale
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.presentError(error)
            }
        }
    }
}

/// Hujjat ko'rinadigan maydondan kichik bo'lsa, uni markazda ushlab turadi.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let frame = documentView.frame
        if rect.width > frame.width {
            rect.origin.x = (frame.width - rect.width) / 2
        }
        if rect.height > frame.height {
            rect.origin.y = (frame.height - rect.height) / 2
        }
        return rect
    }
}
