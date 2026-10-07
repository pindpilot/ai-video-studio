import Foundation

public typealias ProviderOperation = @Sendable (GenerationRequest) async throws -> GenerationResult
public actor FallbackEngine {
    private var manifests: [String: ModelManifest] = [:]
    private var operations: [String: ProviderOperation] = [:]
    private var states: [String: ModelRuntime] = [:]
    private var buckets: [String: ModelRuntime] = [:]
    private let sleep: @Sendable (Double) async throws -> Void
    public init(sleep: @escaping @Sendable (Double) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }) { self.sleep = sleep }
    public func register(_ manifest: ModelManifest, operation: @escaping ProviderOperation) {
        manifests[manifest.id] = manifest; operations[manifest.id] = operation
        if states[manifest.id] == nil { states[manifest.id] = .init() }
    }
    public func state(for id: String) -> ModelRuntime { states[id] ?? .init() }
    public func restoreStates(_ saved: [String: ModelRuntime]) { states = saved }
    public func snapshot() -> [String: ModelRuntime] { states }
    public func reset(_ id: String) {
        states[id] = .init()
        if let bucket = manifests[id]?.quotaBucket { buckets[bucket] = nil }
    }
    public func execute(_ request: GenerationRequest, chain: [String], configurations: [String: ModelConfiguration]) async throws -> ExecutionReceipt {
        var attempts: [Attempt] = []
        for id in chain {
            try Task.checkCancellation()
            guard let manifest = manifests[id], let operation = operations[id] else {
                attempts.append(skip(id, "Adapter not registered")); continue
            }
            let configuration = configurations[id] ?? .init()
            if let reason = ineligible(manifest, request: request, configuration: configuration) {
                attempts.append(skip(id, reason)); continue
            }
            for retry in 0...2 {
                try Task.checkCancellation()
                let started = Date()
                do {
                    let result = try await operation(request)
                    // Async jobs must be handled by the persistent queue, never blind resubmitted here.
                    guard result.providerJobID == nil else {
                        throw ProviderFailure(.invalidRequest, message: "Async provider jobs require the persistent queue")
                    }
                    states[id] = ModelRuntime(); states[id]?.availability = .available
                    attempts.append(.init(modelID: id, date: started, latency: Date().timeIntervalSince(started), errorClass: nil, reason: "Succeeded"))
                    return .init(result: result, modelID: id, attempts: attempts)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    let failure = error as? ProviderFailure ?? .init(.transient, message: "Unknown provider error")
                    attempts.append(.init(modelID: id, date: started, latency: Date().timeIntervalSince(started), errorClass: failure.kind, reason: failure.message))
                    update(id, manifest: manifest, failure: failure)
                    if failure.kind == .invalidRequest || failure.kind == .policyRefused {
                        throw ChainFailure(attempts: attempts, terminal: failure.kind)
                    }
                    if failure.kind == .transient && retry < 2 {
                        let delay = max(pow(2, Double(retry)), failure.retryAfter?.timeIntervalSinceNow ?? 0)
                        try await sleep(delay); continue
                    }
                    break
                }
            }
        }
        throw ChainFailure(attempts: attempts, terminal: nil)
    }
    private func skip(_ id: String, _ reason: String) -> Attempt {
        .init(modelID: id, date: Date(), latency: 0, errorClass: nil, reason: "Skipped: " + reason)
    }
    private func ineligible(_ m: ModelManifest, request: GenerationRequest, configuration: ModelConfiguration) -> String? {
        if !configuration.enabled { return "Disabled" }
        if !m.free { return "Paid models disabled in free-only build" }
        if m.source.eligibility != .verifiedOperation { return "Operation not verified or excluded" }
        if m.capability != request.capability { return "Wrong capability" }
        if m.constraints.asynchronous { return "Async queue not implemented in M1" }
        if m.needsKey && !configuration.configured { return "Needs key" }
        if let ratio = request.ratio, !m.constraints.ratios.contains(ratio) { return "Ratio unsupported or unverified" }
        if let resolution = request.resolution, !m.constraints.resolutions.contains(resolution) { return "Resolution unsupported or unverified" }
        if let duration = request.duration, m.constraints.maxDuration == nil || duration > (m.constraints.maxDuration ?? 0) { return "Duration unsupported or unverified" }
        if let language = request.language, !m.constraints.languages.contains(language) { return "Language unsupported or unverified" }
        let runtime = m.quotaBucket.flatMap { buckets[$0] } ?? states[m.id] ?? .init()
        if runtime.availability == .needsKey { return "Key needs attention" }
        if let until = runtime.cooldownUntil, until > Date() { return "Cooldown until \(until.formatted())" }
        if runtime.availability == .quotaExhausted && runtime.cooldownUntil == nil { return "Quota exhausted; reset unknown, manual recheck required" }
        return nil
    }
    private func update(_ id: String, manifest: ModelManifest, failure: ProviderFailure) {
        var runtime = ModelRuntime(); runtime.lastError = failure.kind
        runtime.lastErrorAt = Date(); runtime.message = failure.message
        switch failure.kind {
        case .quotaExceeded: runtime.availability = .quotaExhausted; runtime.cooldownUntil = failure.retryAfter
        case .rateLimited: runtime.availability = .rateLimited; runtime.cooldownUntil = failure.retryAfter ?? Date().addingTimeInterval(60)
        case .authFailed: runtime.availability = .needsKey
        case .modelUnavailable: runtime.availability = .unavailable; runtime.cooldownUntil = failure.retryAfter ?? Date().addingTimeInterval(60)
        default: runtime.availability = .untested
        }
        states[id] = runtime
        if failure.kind == .quotaExceeded || failure.kind == .rateLimited, let bucket = manifest.quotaBucket { buckets[bucket] = runtime }
    }
}
