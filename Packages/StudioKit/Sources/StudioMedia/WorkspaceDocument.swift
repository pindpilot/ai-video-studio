import Foundation
public struct AssetOrigin: Codable, Sendable {
    public var provider: String
    public var model: String
    public var prompt: String
    public var relativePath: String
    public var createdAt: Date
    public var licenseNote: String
    public init(provider: String, model: String, prompt: String, relativePath: String, licenseNote: String) {
        self.provider = provider; self.model = model; self.prompt = prompt; self.relativePath = relativePath
        self.createdAt = Date(); self.licenseNote = licenseNote
    }
}
public struct WorkspaceDocument: Codable, Sendable {
    public var version = 1
    public var script = ""
    public var imagePrompt = ""
    public var language = "en-US"
    public var voiceID = ""
    public var image: AssetOrigin?
    public var voiceover: AssetOrigin?
    public var subtitleSource = ""
    public var subtitlesAreEstimated = false
    public init() {}
}
/// Media stays in an Application Support project directory. SwiftData holds the project ID.
/// Atomic sidecar snapshots avoid an invented SwiftData schema migration in this milestone.
public actor WorkspaceFiles {
    public let directory: URL
    public init(projectID: UUID, base: URL? = nil) throws {
        let root = try base ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = root.appendingPathComponent("AIStudio/Projects/" + projectID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func load() throws -> WorkspaceDocument {
        let url = directory.appendingPathComponent("workspace.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let value = try JSONDecoder().decode(WorkspaceDocument.self, from: Data(contentsOf: url))
        guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    public func save(_ document: WorkspaceDocument) throws {
        try JSONEncoder().encode(document).write(to: directory.appendingPathComponent("workspace.json"), options: .atomic)
    }
    public func url(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.contains("/"), !relativePath.contains("\\"), relativePath != ".." else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directory.appendingPathComponent(relativePath)
    }
    public func writeSubtitles(_ source: String) throws -> URL {
        let cues = try SubtitleTrack.parseSRT(source)
        let url = directory.appendingPathComponent("subtitles.srt")
        try SubtitleTrack.srt(cues).write(to: url, atomically: true, encoding: .utf8); return url
    }
}
