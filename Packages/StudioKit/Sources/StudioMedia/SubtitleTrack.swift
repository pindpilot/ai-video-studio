import Foundation
public struct SubtitleCue: Identifiable, Codable, Equatable, Sendable {
    public var id: Int
    public var start: Double
    public var end: Double
    public var text: String
    public init(id: Int, start: Double, end: Double, text: String) {
        self.id = id; self.start = start; self.end = end; self.text = text
    }
}
public enum SubtitleFailure: Error { case invalidTiming, invalidSRT, emptyScript }
public enum SubtitleTrack {
    /// Manual estimate only. Not speech recognition or word alignment.
    public static func estimate(script: String, duration: Double) throws -> [SubtitleCue] {
        guard duration.isFinite, duration > 0, duration <= 86_400 else { throw SubtitleFailure.invalidTiming }
        let words = script.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { throw SubtitleFailure.emptyScript }
        let chunks = stride(from: 0, to: words.count, by: 7).map { Array(words[$0..<min($0 + 7, words.count)]) }
        var count = 0
        return chunks.enumerated().map { index, chunk in
            let start = duration * Double(count) / Double(words.count); count += chunk.count
            return SubtitleCue(id: index + 1, start: start, end: duration * Double(count) / Double(words.count), text: chunk.joined(separator: " "))
        }
    }
    public static func srt(_ cues: [SubtitleCue]) throws -> String {
        try validate(cues)
        return cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }
    public static func parseSRT(_ source: String) throws -> [SubtitleCue] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard lines.count >= 3, Int(lines[0].trimmingCharacters(in: .whitespaces)) != nil else { throw SubtitleFailure.invalidSRT }
            let times = lines[1].components(separatedBy: " --> ")
            guard times.count == 2 else { throw SubtitleFailure.invalidSRT }
            cues.append(.init(id: cues.count + 1, start: try seconds(times[0]), end: try seconds(times[1]), text: lines.dropFirst(2).joined(separator: "\n")))
        }
        try validate(cues); return cues
    }
    private static func validate(_ cues: [SubtitleCue]) throws {
        var previousEnd = 0.0
        for cue in cues {
            guard cue.start.isFinite, cue.end.isFinite, cue.start >= previousEnd, cue.end > cue.start, cue.end <= 86_400,
                  !cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SubtitleFailure.invalidTiming }
            previousEnd = cue.end
        }
    }
    private static func seconds(_ text: String) throws -> Double {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard parts.count == 3, let hours = Int(parts[0]), let minutes = Int(parts[1]), let seconds = Double(parts[2]),
              (0...24).contains(hours), (0..<60).contains(minutes), seconds >= 0, seconds < 60 else { throw SubtitleFailure.invalidSRT }
        return Double(hours * 3600 + minutes * 60) + seconds
    }
    private static func timestamp(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, ms % 1000)
    }
}
