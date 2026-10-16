import CraftCore
import Foundation

/// CraftCore xatosi (`CC_GetLastError` + `CC_GetLastErrorMessage`).
public struct EngineError: Error, Sendable, Equatable, LocalizedError {
    public enum Code: Int32, Sendable {
        case unknown = 1
        case notInitialized = 2
        case argument = 3
        case file = 4
        case format = 5
        case password = 6
        case security = 7
        case page = 8
        case memory = 9
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    /// Joriy thread'dagi oxirgi engine xatosi. Faqat `EngineActor` ichida chaqiriladi.
    static func last() -> EngineError {
        let raw = CC_GetLastError()
        let code = Code(rawValue: Int32(raw.rawValue)) ?? .unknown
        return EngineError(code: code, message: String(cString: CC_GetLastErrorMessage()))
    }

    public var errorDescription: String? { message }
}

/// `CC_RENDER_*` bayroqlari.
public struct RenderOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let annotations = RenderOptions(rawValue: UInt32(CC_RENDER_ANNOTATIONS))
    public static let grayscale = RenderOptions(rawValue: UInt32(CC_RENDER_GRAYSCALE))
    public static let noSmoothText = RenderOptions(rawValue: UInt32(CC_RENDER_NO_SMOOTH_TEXT))
    public static let printing = RenderOptions(rawValue: UInt32(CC_RENDER_PRINTING))
}
