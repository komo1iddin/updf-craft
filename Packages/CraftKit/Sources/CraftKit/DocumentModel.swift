import CoreGraphics
import Foundation
import Observation

/// UI tomonidagi hujjat modeli. Engine handle'ini (`DocumentID`) va sahifa geometriyasini
/// saqlaydi; barcha engine ishlari `EngineActor`ga yuboriladi.
@MainActor
@Observable
public final class DocumentModel {
    public let id: DocumentID
    public let url: URL
    public let pageSizes: [CGSize]
    public private(set) var isClosed = false

    @ObservationIgnored private let engine: EngineActor

    public var pageCount: Int { pageSizes.count }

    public init(opened: OpenedDocument, engine: EngineActor = .shared) {
        self.id = opened.id
        self.url = opened.url
        self.pageSizes = opened.pageSizes
        self.engine = engine
    }

    /// Faylni engine'da ochadi (asinxron).
    public static func open(url: URL, password: String? = nil) async throws(EngineError) -> DocumentModel {
        let opened = try await EngineActor.shared.open(url: url, password: password)
        return DocumentModel(opened: opened)
    }

    /// Sahifani `scale` piksel/punkt bilan butunlay chizadi.
    public func renderPage(_ index: Int, scale: CGFloat, options: RenderOptions = .annotations)
        async throws(EngineError) -> CGImage
    {
        try await engine.render(id, page: index, scale: Double(scale), options: options)
    }

    public func text(page index: Int) async throws(EngineError) -> String {
        try await engine.text(id, page: index)
    }

    public func close() async {
        guard !isClosed else { return }
        isClosed = true
        await engine.close(id)
    }
}
