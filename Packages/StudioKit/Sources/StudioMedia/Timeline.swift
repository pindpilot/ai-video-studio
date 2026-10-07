import Foundation
import ImageIO
import UniformTypeIdentifiers
public enum MediaKind: String, Codable, Sendable { case image, video }
public enum ExportRatio: String, CaseIterable, Codable, Sendable {
    case portrait = "9:16", landscape = "16:9", square = "1:1"
    public func dimensions(fullHD: Bool) -> (width: Int, height: Int) {
        let short = fullHD ? 1080 : 720
        switch self {
        case .portrait: return (short, fullHD ? 1920 : 1280)
        case .landscape: return (fullHD ? 1920 : 1280, short)
        case .square: return (short, short)
        }
    }
}
public struct TimelineClip: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var relativePath: String
    public var kind: MediaKind
    public var start: Double
    public var duration: Double
    public var speed: Double
    public var volume: Float
    public init(relativePath: String, kind: MediaKind, start: Double = 0, duration: Double = 5, speed: Double = 1, volume: Float = 1) {
        id = UUID(); self.relativePath = relativePath; self.kind = kind; self.start = start
        self.duration = duration; self.speed = speed; self.volume = volume
    }
    public var outputDuration: Double { duration / speed }
}
public enum TimelineFailure: Error { case invalidClip, missingMedia, emptyTimeline, mediaTooShort, exportFailed, unsupportedVersion }
public struct TimelineDocument: Codable, Equatable, Sendable {
    public var version = 1
    public var clips: [TimelineClip] = []
    public var ratio: ExportRatio = .portrait
    public var fullHD = false
    public var voiceoverPath: String?
    public var voiceoverVolume: Float = 1
    public var lastExportPath: String?
    public init() {}
    public var duration: Double { clips.reduce(0) { $0 + $1.outputDuration } }
    public func validate() throws {
        guard !clips.isEmpty, clips.count <= 100 else { throw TimelineFailure.emptyTimeline }
        for clip in clips {
            guard Self.safePath(clip.relativePath), clip.start.isFinite, clip.start >= 0,
                  clip.duration.isFinite, clip.duration >= 0.1, clip.duration <= 600,
                  clip.speed.isFinite, (0.25...4).contains(clip.speed),
                  clip.volume.isFinite, (0...1).contains(clip.volume) else { throw TimelineFailure.invalidClip }
        }
        guard duration <= 600, voiceoverVolume.isFinite, (0...1).contains(voiceoverVolume),
              voiceoverPath == nil || Self.safePath(voiceoverPath!) else { throw TimelineFailure.invalidClip }
    }
    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("/") && !path.contains("\\") && path != ".." && path != "."
    }
    public mutating func split(_ id: UUID, at sourceOffset: Double) throws {
        guard let index = clips.firstIndex(where: { $0.id == id }), sourceOffset.isFinite,
              sourceOffset >= 0.1, sourceOffset <= clips[index].duration - 0.1 else { throw TimelineFailure.invalidClip }
        let original = clips[index]
        var second = original; second.id = UUID(); second.start += sourceOffset; second.duration -= sourceOffset
        clips[index].duration = sourceOffset; clips.insert(second, at: index + 1)
    }
}
public actor TimelineFiles {
    public nonisolated let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load() throws -> TimelineDocument {
        let url = directory.appendingPathComponent("timeline.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let document = try JSONDecoder().decode(TimelineDocument.self, from: Data(contentsOf: url))
        guard document.version == 1 else { throw TimelineFailure.unsupportedVersion }
        return document
    }
    public func save(_ document: TimelineDocument) throws {
        try JSONEncoder().encode(document).write(to: directory.appendingPathComponent("timeline.json"), options: .atomic)
    }
    /// Decode HEIC/JPEG/PNG, apply EXIF orientation and bound pixel size off the UI thread.
    public func importPhoto(_ source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2560
              ] as CFDictionary) else { throw TimelineFailure.invalidClip }
        let name = UUID().uuidString + ".jpg"
        let target = directory.appendingPathComponent(name)
        guard let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw TimelineFailure.invalidClip }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            try? FileManager.default.removeItem(at: target)
            throw TimelineFailure.invalidClip
        }
        return name
    }
    public func importFile(_ source: URL, kind: MediaKind) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let suffix = source.pathExtension.lowercased()
        guard !suffix.isEmpty, suffix.count <= 10, suffix.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw TimelineFailure.invalidClip }
        let name = UUID().uuidString + "." + suffix
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(name))
        return name
    }
}
