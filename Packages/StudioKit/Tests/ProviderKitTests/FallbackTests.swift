import XCTest
@testable import ProviderKit

private actor Counter {
    var value = 0
    func next() -> Int { value += 1; return value }
}
final class FallbackTests: XCTestCase {
    private func manifest(_ id: String, bucket: String? = nil) -> ModelManifest {
        .init(id: id, provider: "Mock", model: id, capability: .text,
              source: .init(documentationURL: URL(string: "https://example.com")!, verifiedOn: "fixture", eligibility: .verifiedOperation),
              needsKey: false, terms: "Test only", dataDisclosure: "No network", quotaBucket: bucket)
    }
    private var request: GenerationRequest { .init(capability: .text, text: "Test") }
    private var config: [String: ModelConfiguration] {
        ["one": .init(enabled: true), "two": .init(enabled: true), "three": .init(enabled: true)]
    }
    func testExactExample() async throws {
        let engine = FallbackEngine(sleep: { _ in })
        await engine.register(manifest("one")) { _ in throw ProviderFailure(.quotaExceeded, message: "Quota exhausted") }
        await engine.register(manifest("two")) { _ in throw ProviderFailure(.modelUnavailable, message: "Unavailable") }
        await engine.register(manifest("three")) { _ in .init(text: "Success") }
        let result = try await engine.execute(request, chain: ["one", "two", "three"], configurations: config)
        XCTAssertEqual(result.modelID, "three"); XCTAssertEqual(result.attempts.count, 3)
        XCTAssertEqual(result.attempts.compactMap(\.errorClass), [.quotaExceeded, .modelUnavailable])
    }
    func testEveryErrorClass() async throws {
        for kind in ProviderErrorClass.allCases {
            let engine = FallbackEngine(sleep: { _ in })
            await engine.register(manifest("one")) { _ in throw ProviderFailure(kind, message: "Fixture") }
            await engine.register(manifest("two")) { _ in .init(text: "Success") }
            do {
                let receipt = try await engine.execute(request, chain: ["one", "two"], configurations: config)
                XCTAssertFalse(kind == .invalidRequest || kind == .policyRefused)
                XCTAssertEqual(receipt.attempts.count, kind == .transient ? 4 : 2)
            } catch let failure as ChainFailure {
                XCTAssertTrue(kind == .invalidRequest || kind == .policyRefused)
                XCTAssertEqual(failure.attempts.count, 1); XCTAssertEqual(failure.terminal, kind)
            }
        }
    }
    func testUnknownErrorsRetryTwice() async throws {
        struct Unknown: Error {}
        let engine = FallbackEngine(sleep: { _ in }); let counter = Counter()
        await engine.register(manifest("one")) { _ in _ = await counter.next(); throw Unknown() }
        do {
            _ = try await engine.execute(request, chain: ["one"], configurations: config)
            XCTFail("Must fail")
        } catch let failure as ChainFailure { XCTAssertEqual(failure.attempts.count, 3) }
        let count = await counter.value; XCTAssertEqual(count, 3)
    }
    func testAllFailAndAuthState() async throws {
        let engine = FallbackEngine(sleep: { _ in })
        await engine.register(manifest("one")) { _ in throw ProviderFailure(.authFailed, message: "Key rejected") }
        await engine.register(manifest("two")) { _ in throw ProviderFailure(.quotaExceeded, message: "Quota exhausted") }
        do {
            _ = try await engine.execute(request, chain: ["one", "two"], configurations: config)
            XCTFail("Must fail")
        } catch let failure as ChainFailure { XCTAssertEqual(failure.attempts.count, 2); XCTAssertNil(failure.terminal) }
        let state = await engine.state(for: "one"); XCTAssertEqual(state.availability, .needsKey)
    }
    func testSharedQuotaSkipsSibling() async throws {
        let engine = FallbackEngine(sleep: { _ in }); let counter = Counter()
        await engine.register(manifest("one", bucket: "shared")) { _ in throw ProviderFailure(.quotaExceeded, message: "Quota exhausted") }
        await engine.register(manifest("two", bucket: "shared")) { _ in _ = await counter.next(); return .init(text: "Wrong") }
        await engine.register(manifest("three")) { _ in .init(text: "Success") }
        let receipt = try await engine.execute(request, chain: ["one", "two", "three"], configurations: config)
        XCTAssertEqual(receipt.modelID, "three")
        let count = await counter.value; XCTAssertEqual(count, 0)
    }
    func testEligibilityAndCooldown() async throws {
        let engine = FallbackEngine(sleep: { _ in })
        await engine.register(manifest("one")) { _ in throw ProviderFailure(.rateLimited, message: "Slow down", retryAfter: Date().addingTimeInterval(3600)) }
        await engine.register(manifest("two")) { _ in .init(text: "Success") }
        _ = try await engine.execute(request, chain: ["one", "two"], configurations: config)
        let receipt = try await engine.execute(request, chain: ["one", "two"], configurations: config)
        XCTAssertTrue(receipt.attempts[0].reason.contains("Cooldown"))
        var wide = request; wide.ratio = "9:16"
        do { _ = try await engine.execute(wide, chain: ["two"], configurations: config); XCTFail("Unknown ratio must skip") }
        catch let failure as ChainFailure { XCTAssertTrue(failure.attempts[0].reason.contains("unverified")) }
    }
    func testRetryAfterParsing() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProviderFailure.retryDate("120", now: now), now.addingTimeInterval(120))
        XCTAssertNotNil(ProviderFailure.retryDate("Wed, 21 Oct 2015 07:28:00 GMT"))
        XCTAssertNil(ProviderFailure.retryDate("unknown"))
    }
    func testCancellationDoesNotFailover() async throws {
        let engine = FallbackEngine(sleep: { _ in })
        await engine.register(manifest("one")) { _ in throw CancellationError() }
        await engine.register(manifest("two")) { _ in .init(text: "Wrong") }
        do { _ = try await engine.execute(request, chain: ["one", "two"], configurations: config); XCTFail("Cancelled") }
        catch is CancellationError {} 
    }
}
