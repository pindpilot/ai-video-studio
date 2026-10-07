import Foundation
public enum PipelineStage: String, Codable, CaseIterable, Sendable {
    case script, scenes, visuals, voiceover, subtitles, music, edit, export
    public var title: String { rawValue.capitalized }
}
public struct StudioProject: Identifiable, Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var id: UUID
    public var schemaVersion: Int
    public var name: String
    public var idea: String
    public var createdAt: Date
    public init(name: String, idea: String) {
        id = UUID(); schemaVersion = Self.currentSchemaVersion
        self.name = name; self.idea = idea; createdAt = Date()
    }
}
public enum StudioBuildStatus {
    public static let milestone = "M4: local timeline and foreground MP4 export. Cloud AI video, captions and device audio checks remain pending."
}
