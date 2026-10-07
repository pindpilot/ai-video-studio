import Foundation

public enum Capability: String, Codable, CaseIterable, Sendable { case text, image, video, speech, transcription, translation, music, enhancement, backgroundRemoval, sceneDetection }
public struct ModelConstraints: Codable, Sendable {
    public var ratios: [String] = []
    public var maxDuration: Double? = nil
    public var resolutions: [String] = []
    public var languages: [String] = []
    public var asynchronous = false
    public init() {}
}
public struct ModelManifest: Identifiable, Codable, Sendable {
    public let id: String
    public let provider: String
    public let model: String
    public let capability: Capability
    public let source: ProviderSource
    public let keyPage: URL?
    public let needsKey: Bool
    public let constraints: ModelConstraints
    public let terms: String
    public let dataDisclosure: String
    public let quotaBucket: String?
    public let free: Bool
    public init(id: String, provider: String, model: String, capability: Capability, source: ProviderSource,
                keyPage: URL? = nil, needsKey: Bool = true, constraints: ModelConstraints = .init(),
                terms: String, dataDisclosure: String, quotaBucket: String? = nil, free: Bool = true) {
        self.id = id; self.provider = provider; self.model = model; self.capability = capability
        self.source = source; self.keyPage = keyPage; self.needsKey = needsKey; self.constraints = constraints
        self.terms = terms; self.dataDisclosure = dataDisclosure; self.quotaBucket = quotaBucket; self.free = free
    }
}
public struct GenerationRequest: Sendable {
    public let capability: Capability
    public let text: String
    public var inputFile: URL? = nil
    public var ratio: String? = nil
    public var duration: Double? = nil
    public var resolution: String? = nil
    public var language: String? = nil
    public init(capability: Capability, text: String) { self.capability = capability; self.text = text }
}
public struct TimedWord: Codable, Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double
    public init(text: String, start: Double, end: Double) { self.text = text; self.start = start; self.end = end }
}
public struct GenerationResult: Sendable {
    public let text: String?
    public let file: URL?
    public let words: [TimedWord]
    public let providerJobID: String?
    public init(text: String? = nil, file: URL? = nil, words: [TimedWord] = [], providerJobID: String? = nil) {
        self.text = text; self.file = file; self.words = words; self.providerJobID = providerJobID
    }
}
// Capability-specific protocols share normalized, file-backed values, never large inline media.
public protocol TextProvider: Sendable { func generateText(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol ImageProvider: Sendable { func generateImage(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol VideoProvider: Sendable {
    func submitVideo(_ request: GenerationRequest) async throws -> GenerationResult
    func pollVideo(jobID: String) async throws -> GenerationResult
    func cancelVideo(jobID: String) async throws
}
public protocol SpeechProvider: Sendable { func synthesize(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol TranscriptionProvider: Sendable { func transcribe(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol TranslationProvider: Sendable { func translate(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol MusicProvider: Sendable { func generateMusic(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol EnhancementProvider: Sendable { func enhance(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol BackgroundRemovalProvider: Sendable { func removeBackground(_ request: GenerationRequest) async throws -> GenerationResult }
public protocol SceneDetectionProvider: Sendable { func detectScenes(_ request: GenerationRequest) async throws -> GenerationResult }

public enum ProviderErrorClass: String, Codable, CaseIterable, Sendable {
    case quotaExceeded, rateLimited, transient, modelUnavailable, authFailed, invalidRequest, policyRefused
}
public struct ProviderFailure: Error, Sendable {
    public let kind: ProviderErrorClass
    // Adapter-authored safe summary only. Never pass server bodies, prompts, credentials or URLs here.
    public let message: String
    public let retryAfter: Date?
    public init(_ kind: ProviderErrorClass, message: String, retryAfter: Date? = nil) {
        self.kind = kind; self.message = message; self.retryAfter = retryAfter
    }
    public static func http(_ status: Int, retryAfter: Date? = nil) -> Self {
        switch status {
        case 401: return .init(.authFailed, message: "Key rejected")
        case 429: return .init(.rateLimited, message: "Rate limit reached", retryAfter: retryAfter)
        case 404, 503: return .init(.modelUnavailable, message: "Model unavailable", retryAfter: retryAfter)
        case 400, 422: return .init(.invalidRequest, message: "Request needs correction")
        case 403: return .init(.policyRefused, message: "Request refused; inspect provider policy")
        default: return .init(.transient, message: "Temporary provider error", retryAfter: retryAfter)
        }
    }
    public static func retryDate(_ header: String?, now: Date = Date()) -> Date? {
        guard let header else { return nil }
        if let seconds = Double(header), seconds >= 0 { return now.addingTimeInterval(seconds) }
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return parser.date(from: header)
    }
}
public struct Attempt: Codable, Sendable {
    public let modelID: String
    public let date: Date
    public let latency: Double
    public let errorClass: ProviderErrorClass?
    public let reason: String
}
public enum Availability: String, Codable, Sendable { case untested, available, rateLimited, quotaExhausted, unavailable, needsKey }
public struct ModelRuntime: Codable, Sendable {
    public var availability: Availability = .untested
    public var cooldownUntil: Date? = nil
    public var lastError: ProviderErrorClass? = nil
    public var lastErrorAt: Date? = nil
    public var message: String? = nil
    public init() {}
}
public struct ModelConfiguration: Codable, Sendable {
    public var enabled: Bool
    public var configured: Bool
    public init(enabled: Bool = false, configured: Bool = false) { self.enabled = enabled; self.configured = configured }
}
public struct ExecutionReceipt: Sendable {
    public let result: GenerationResult
    public let modelID: String
    public let attempts: [Attempt]
}
public struct ChainFailure: Error, Sendable {
    public let attempts: [Attempt]
    public let terminal: ProviderErrorClass?
}
