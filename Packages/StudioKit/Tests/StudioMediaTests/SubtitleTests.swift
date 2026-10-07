import XCTest
@testable import StudioMedia
final class SubtitleTests: XCTestCase {
    func testEstimateAndSRTRoundTrip() throws {
        let cues = try SubtitleTrack.estimate(script: "One two three four five six seven eight nine", duration: 9)
        XCTAssertEqual(cues.count, 2); XCTAssertEqual(cues.last?.end, 9)
        XCTAssertEqual(try SubtitleTrack.parseSRT(SubtitleTrack.srt(cues)), cues)
    }
    func testTimingAndMalformedInputRejected() {
        XCTAssertThrowsError(try SubtitleTrack.estimate(script: "Hi", duration: -.infinity))
        XCTAssertThrowsError(try SubtitleTrack.parseSRT("1\n00:00:05,000 --> 00:00:01,000\nNo"))
        XCTAssertThrowsError(try SubtitleTrack.parseSRT("bad"))
        XCTAssertThrowsError(try SubtitleTrack.estimate(script: " ", duration: 10))
        XCTAssertThrowsError(try SubtitleTrack.estimate(script: "Hi", duration: 1e100))
        XCTAssertThrowsError(try SubtitleTrack.parseSRT("1\n99999999999999999999:00:00,000 --> 99999999999999999999:00:01,000\nHi"))
    }
    func testDiskWorkspaceRoundTripAndTraversalRejected() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let id = UUID(); let first = try WorkspaceFiles(projectID: id, base: base)
        var document = WorkspaceDocument(); document.script = "Saved script"
        try await first.save(document)
        let second = try WorkspaceFiles(projectID: id, base: base)
        let loaded = try await second.load(); XCTAssertEqual(loaded.script, "Saved script")
        do { _ = try await second.url(for: "../private"); XCTFail("Traversal must fail") } catch {}
    }
}
