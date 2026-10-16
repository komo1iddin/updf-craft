import CoreGraphics
import CraftCore
import Dispatch
import Foundation

/// Engine'dagi ochiq hujjatning identifikatori. Handle'ning o'zi (`CC_DOC`) faqat
/// `EngineActor` ichida yashaydi; tashqariga faqat shu `Sendable` qiymat chiqadi.
public struct DocumentID: Hashable, Sendable, CustomStringConvertible {
    let rawValue: UInt64
    public var description: String { "doc#\(rawValue)" }
}

/// Engine'dan qaytgan, ochilgan hujjat haqidagi o'zgarmas ma'lumot.
public struct OpenedDocument: Sendable {
    public let id: DocumentID
    public let url: URL
    /// Har bir sahifaning ko'rinadigan o'lchami punktlarda (/Rotate hisobga olingan).
    public let pageSizes: [CGSize]
}

/// CraftCore'ga yagona kirish nuqtasi.
///
/// PDFium global holatli va thread-safe emas, shuning uchun barcha engine chaqiruvlari
/// bitta serial executor'da bajariladi: actor'ning executor'i — o'z `DispatchSerialQueue`si.
/// Boshqa turlar `@EngineActor` bilan shu executor'ga bog'lanishi mumkin.
@globalActor
public actor EngineActor {
    public static let shared = EngineActor()

    private let queue = DispatchSerialQueue(label: "com.updfcraft.engine", qos: .userInitiated)

    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    private var initialized = false
    private var documents: [DocumentID: CC_DOC] = [:]
    private var nextID: UInt64 = 1

    private init() {}

    /// Engine versiyasi, masalan "craftcore 0.1.0 (pdfium)".
    public nonisolated static var version: String { String(cString: CC_Version()) }

    // MARK: - Hujjat

    public func open(url: URL, password: String? = nil) throws(EngineError) -> OpenedDocument {
        try ensureInitialized()
        let handle: CC_DOC? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            if let password {
                return password.withCString { CC_Doc_Open(path, $0) }
            }
            return CC_Doc_Open(path, nil)
        }
        guard let handle else { throw EngineError.last() }

        let count = CC_Doc_PageCount(handle)
        guard count >= 0 else {
            let error = EngineError.last()
            CC_Doc_Close(handle)
            throw error
        }
        var sizes: [CGSize] = []
        sizes.reserveCapacity(Int(count))
        for index in 0..<count {
            var size = CC_Size()
            guard CC_Page_Size(handle, index, &size) == CC_OK else {
                let error = EngineError.last()
                CC_Doc_Close(handle)
                throw error
            }
            sizes.append(CGSize(width: size.width, height: size.height))
        }

        let id = DocumentID(rawValue: nextID)
        nextID += 1
        documents[id] = handle
        return OpenedDocument(id: id, url: url, pageSizes: sizes)
    }

    public func close(_ id: DocumentID) {
        guard let handle = documents.removeValue(forKey: id) else { return }
        CC_Doc_Close(handle)
    }

    // MARK: - Render

    /// Sahifani (yoki uning `rect` hududini) `scale` piksel/punkt bilan chizadi.
    ///
    /// `rect` — to'liq sahifa bitmap'i (`round(size * scale)`) ichidagi piksel hudud,
    /// `nil` bo'lsa butun sahifa. Natija oq fonli sRGB `CGImage`.
    public func render(
        _ id: DocumentID,
        page: Int,
        scale: Double,
        rect: CGRect? = nil,
        options: RenderOptions = []
    ) throws(EngineError) -> CGImage {
        let handle = try document(id)
        var size = CC_Size()
        guard CC_Page_Size(handle, Int32(page), &size) == CC_OK else { throw EngineError.last() }

        let full = CGRect(x: 0, y: 0,
                          width: (size.width * scale).rounded(),
                          height: (size.height * scale).rounded())
        let area = (rect ?? full).integral
        guard area.width >= 1, area.height >= 1, area.width <= 32_768, area.height <= 32_768 else {
            throw EngineError(code: .argument, message: "render hududi noto'g'ri: \(area)")
        }
        let width = Int(area.width)
        let height = Int(area.height)

        // BGRA xotirada = 32-bit little-endian ARGB. Oq fon bilan alpha doim 255.
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: bitmapInfo),
              let pixels = context.data
        else {
            throw EngineError(code: .memory, message: "\(width)x\(height) bitmap yaratib bo'lmadi")
        }

        let pixelRect = CC_PixelRect(x: Int32(area.minX), y: Int32(area.minY),
                                     width: Int32(width), height: Int32(height))
        let status = CC_Render_Rect(handle, Int32(page), scale, pixelRect, pixels,
                                    Int32(context.bytesPerRow), options.rawValue)
        guard status == CC_OK else { throw EngineError.last() }
        guard let image = context.makeImage() else {
            throw EngineError(code: .memory, message: "CGImage yaratib bo'lmadi")
        }
        return image
    }

    // MARK: - Matn

    public func text(_ id: DocumentID, page: Int) throws(EngineError) -> String {
        let handle = try document(id)
        let length = CC_TextExtract_PageUTF8(handle, Int32(page), nil, 0)
        guard length >= 0 else { throw EngineError.last() }
        var buffer = [CChar](repeating: 0, count: Int(length) + 1)
        guard CC_TextExtract_PageUTF8(handle, Int32(page), &buffer, buffer.count) >= 0 else {
            throw EngineError.last()
        }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Ichki

    private func ensureInitialized() throws(EngineError) {
        guard !initialized else { return }
        guard CC_Init() == CC_OK else { throw EngineError.last() }
        initialized = true
    }

    private func document(_ id: DocumentID) throws(EngineError) -> CC_DOC {
        guard let handle = documents[id] else {
            throw EngineError(code: .argument, message: "\(id) ochiq emas")
        }
        return handle
    }
}

// MARK: - Sinxron ko'prik

extension EngineActor {
    /// Engine amalini sinxron bajaradi va natijani kutadi.
    ///
    /// `NSDocument.read(from:ofType:)` kabi sinxron API'lar uchun. Engine hech qachon
    /// main actor'ni kutmaydi, shuning uchun main thread'dan chaqirish deadlock bermaydi
    /// (faqat amal davomida UI kutadi). Swift concurrency pool thread'laridan (async
    /// kontekstdan) chaqirmang — u yerda `await` ishlating.
    public nonisolated func runBlocking<T: Sendable, E: Error>(
        _ operation: @escaping @Sendable (isolated EngineActor) throws(E) -> T
    ) throws(E) -> T {
        dispatchPrecondition(condition: .notOnQueue(queue))
        let box = BlockingBox<T, E>()
        let done = DispatchSemaphore(value: 0)
        Task {
            let result = await self.perform(operation)
            box.store(result)
            done.signal()
        }
        done.wait()
        return try box.load().get()
    }

    private func perform<T: Sendable, E: Error>(
        _ operation: (isolated EngineActor) throws(E) -> T
    ) -> Result<T, E> {
        do throws(E) {
            return .success(try operation(self))
        } catch {
            return .failure(error)
        }
    }
}

/// `runBlocking` natijasini thread'lar orasida uzatish uchun.
private final class BlockingBox<T: Sendable, E: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, E>?

    func store(_ value: Result<T, E>) {
        lock.withLock { result = value }
    }

    func load() -> Result<T, E> {
        lock.withLock { result! }
    }
}
