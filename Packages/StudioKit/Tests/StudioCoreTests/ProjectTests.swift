import Foundation
import XCTest
@testable import StudioCore
final class ProjectTests: XCTestCase {
    func testProjectRoundTrip() throws {
        let project = StudioProject(name: "Test", idea: "A rainy evening")
        let data = try JSONEncoder().encode(project)
        XCTAssertEqual(try JSONDecoder().decode(StudioProject.self, from: data), project)
    }
    func testPipelineOrder() {
        XCTAssertEqual(PipelineStage.allCases.map(\.rawValue),
            ["script", "scenes", "visuals", "voiceover", "subtitles", "music", "edit", "export"])
    }
}
