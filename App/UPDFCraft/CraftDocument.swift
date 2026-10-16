import AppKit
import CraftKit
import os

/// PDF hujjat. M0'da faqat o'qiladi (Info.plist: role = Viewer).
///
/// `read(from:ofType:)` engine'da faylni sinxron ochadi (`EngineActor.runBlocking`),
/// natija lock ostida saqlanadi va `makeWindowControllers` undan `DocumentModel` yaratadi.
///
/// Concurrent reading (`canConcurrentlyReadDocuments`) hozircha o'chiq: AppKit unda
/// `-[NSDocument init]`ni fon thread'ida chaqiradi, Swift 6 esa NSDocument
/// subclass'ining init'ini main actor'ga bog'laydi va runtime'da yiqiladi. PDFium faylni
/// dangasa ochadi, shuning uchun main thread'dagi sinxron ochish qisqa.
@objc(CraftDocument)
final class CraftDocument: NSDocument {
    private let opened = OSAllocatedUnfairLock<OpenedDocument?>(initialState: nil)
    private(set) var model: DocumentModel?

    override class var autosavesInPlace: Bool {
        false
    }

    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        let document: OpenedDocument
        do {
            document = try EngineActor.shared.runBlocking { engine throws(EngineError) in
                try engine.open(url: url)
            }
        } catch {
            throw Self.readError(error, url: url)
        }
        let previous = opened.withLock { state in
            defer { state = document }
            return state
        }
        if let previous {  // revert: eski handle'ni yopish
            Task { await EngineActor.shared.close(previous.id) }
        }
    }

    override func makeWindowControllers() {
        guard let document = opened.withLock({ $0 }) else { return }
        let model = DocumentModel(opened: document)
        self.model = model
        addWindowController(DocumentWindowController(model: model))
    }

    override func close() {
        if let model {
            Task { await model.close() }
        } else if let document = opened.withLock({ $0 }) {
            Task { await EngineActor.shared.close(document.id) }
        }
        super.close()
    }

    /// Engine xatosini NSDocument kutadigan Cocoa xatosiga aylantiradi.
    private nonisolated static func readError(_ error: EngineError, url: URL) -> NSError {
        let code: Int
        switch error.code {
        case .file: code = NSFileReadNoSuchFileError
        case .format: code = NSFileReadCorruptFileError
        default: code = NSFileReadUnknownError
        }
        return NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [
            NSURLErrorKey: url,
            NSLocalizedFailureReasonErrorKey: error.message,
            NSUnderlyingErrorKey: error as NSError,
        ])
    }
}
