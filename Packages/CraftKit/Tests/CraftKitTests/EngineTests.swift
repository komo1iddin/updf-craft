import CoreGraphics
import Foundation
import Testing

@testable import CraftKit

private let corpus = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // CraftKitTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // CraftKit
    .deletingLastPathComponent()  // Packages
    .deletingLastPathComponent()  // repo
    .appendingPathComponent("Tests/corpus")

@Suite("EngineActor")
struct EngineTests {
    let engine = EngineActor.shared

    @Test func opensAndReportsGeometry() async throws {
        let doc = try await engine.open(url: corpus.appendingPathComponent("hello.pdf"))
        #expect(doc.pageSizes.count == 2)
        #expect(abs(doc.pageSizes[0].width - 595.276) < 0.01)
        #expect(abs(doc.pageSizes[0].height - 841.89) < 0.01)
        #expect(doc.pageSizes[1] == CGSize(width: 792, height: 612))
        await engine.close(doc.id)
    }

    @Test func rotationSwapsSize() async throws {
        let doc = try await engine.open(url: corpus.appendingPathComponent("rotated.pdf"))
        #expect(doc.pageSizes == [CGSize(width: 600, height: 400)])
        await engine.close(doc.id)
    }

    @Test func rendersPixels() async throws {
        let doc = try await engine.open(url: corpus.appendingPathComponent("hello.pdf"))
        let image = try await engine.render(doc.id, page: 0, scale: 1)
        #expect(image.width == 595)
        #expect(image.height == 842)

        // Qizil kvadrat: PDF (56..206, 400..550) -> piksel y = 842 - 475 ≈ 367.
        let pixel = try #require(Self.pixel(image, x: 130, y: 367))
        #expect(pixel.r > 200 && pixel.g < 80 && pixel.b < 80)
        // Bo'sh joy oq.
        let blank = try #require(Self.pixel(image, x: 300, y: 820))
        #expect(blank.r == 255 && blank.g == 255 && blank.b == 255)
        await engine.close(doc.id)
    }

    @Test func rendersTileMatchingFullPage() async throws {
        let doc = try await engine.open(url: corpus.appendingPathComponent("hello.pdf"))
        let tile = try await engine.render(doc.id, page: 0, scale: 2,
                                           rect: CGRect(x: 200, y: 600, width: 64, height: 64))
        #expect(tile.width == 64 && tile.height == 64)
        let full = try await engine.render(doc.id, page: 0, scale: 2)
        let a = try #require(Self.pixel(tile, x: 10, y: 20))
        let b = try #require(Self.pixel(full, x: 210, y: 620))
        #expect(a == b)
        await engine.close(doc.id)
    }

    @Test func extractsText() async throws {
        let doc = try await engine.open(url: corpus.appendingPathComponent("hello.pdf"))
        let text = try await engine.text(doc.id, page: 0)
        #expect(text.contains("Hello, UPDF Craft"))
        #expect(text.contains("lazy dog"))
        await engine.close(doc.id)
    }

    @Test func reportsMissingFile() async {
        await #expect(throws: EngineError.self) {
            _ = try await engine.open(url: corpus.appendingPathComponent("missing.pdf"))
        }
        do {
            _ = try await engine.open(url: corpus.appendingPathComponent("missing.pdf"))
        } catch {
            #expect(error.code == .file)
        }
    }

    @Test func blockingBridgeOpensFromBackgroundThread() async throws {
        let url = corpus.appendingPathComponent("hello.pdf")
        let opened: OpenedDocument = try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                do {
                    let doc = try EngineActor.shared.runBlocking { engine in
                        try engine.open(url: url)
                    }
                    continuation.resume(returning: doc)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        #expect(opened.pageSizes.count == 2)
        await engine.close(opened.id)
    }

    struct RGB: Equatable { let r, g, b: UInt8 }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> RGB? {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let offset = y * image.bytesPerRow + x * 4  // BGRA
        return RGB(r: bytes[offset + 2], g: bytes[offset + 1], b: bytes[offset])
    }
}
