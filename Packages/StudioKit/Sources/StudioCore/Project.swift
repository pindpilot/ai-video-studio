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
    public static let milestone = "M3: manual scripts, Cloudflare script/image adapters, local voiceover audio and editable SRT. Device audio tests pending; video export arrives later."
}
