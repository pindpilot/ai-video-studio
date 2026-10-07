import Foundation
@preconcurrency import AVFoundation

public enum VoiceWriteFailure: Error { case unavailableLanguage, emptyText, busy, noAudio }
/// Buffer callback may run off-main. Only this locked writer touches AVAudioFile.
private final class AudioBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var file: AVAudioFile?
    private var failure: Error?
    private var frames: AVAudioFramePosition = 0
    private var sampleRate = 0.0
    init(url: URL) { self.url = url }
    func append(_ buffer: AVAudioBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
                sampleRate = pcm.format.sampleRate
            }
            try file?.write(from: pcm); frames += AVAudioFramePosition(pcm.frameLength)
        } catch { failure = error }
    }
    func finish() throws -> Double {
        lock.lock(); defer { lock.unlock() }
        file = nil
        if let failure { throw failure }
        guard frames > 0, sampleRate > 0 else { throw VoiceWriteFailure.noAudio }
        return Double(frames) / sampleRate
    }
}
@MainActor
public final class LocalVoiceWriter: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Double, Error>?
    private var sink: AudioBufferSink?
    private var currentURL: URL?
    public override init() { super.init(); synthesizer.delegate = self }
    public static func availableVoices() -> [(id: String, name: String, language: String)] {
        AVSpeechSynthesisVoice.speechVoices().map { ($0.identifier, $0.name, $0.language) }
    }
    public func write(text: String, language: String, voiceID: String, to url: URL) async throws -> Double {
        guard continuation == nil else { throw VoiceWriteFailure.busy }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceWriteFailure.emptyText }
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID), voice.language == language else {
            throw VoiceWriteFailure.unavailableLanguage
        }
        try Task.checkCancellation()
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice
        let writer = AudioBufferSink(url: url); sink = writer; currentURL = url
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                synthesizer.write(utterance) { buffer in writer.append(buffer) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
    public func cancel() {
        _ = synthesizer.stopSpeaking(at: .immediate)
        complete(.failure(CancellationError()))
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, let sink = self.sink else { return }
            do { self.complete(.success(try sink.finish())) }
            catch { self.complete(.failure(error)) }
        }
    }
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.complete(.failure(CancellationError())) }
    }
    private func complete(_ result: Result<Double, Error>) {
        guard let pending = continuation else { return }
        continuation = nil
        if case .failure = result, let url = currentURL { try? FileManager.default.removeItem(at: url) }
        sink = nil; currentURL = nil; pending.resume(with: result)
    }
}
