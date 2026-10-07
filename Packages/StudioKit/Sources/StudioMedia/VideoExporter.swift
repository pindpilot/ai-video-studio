import Foundation
@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import CoreVideo

/// Serial actor keeps frame creation and composition work off the UI actor.
/// Export is foreground-only. A cancelled/failed output is deleted, never marked ready.
public actor VideoExporter {
    public init() {}
    public func export(_ timeline: TimelineDocument, directory: URL) async throws -> URL {
        try timeline.validate(); try Task.checkCancellation()
        let size = timeline.ratio.dimensions(fullHD: timeline.fullHD)
        let output = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        var temporary: [URL] = []
        defer { for url in temporary { try? FileManager.default.removeItem(at: url) } }
        do {
            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw TimelineFailure.exportFailed }
            var instructions: [AVMutableVideoCompositionInstruction] = []
            var audioParameters: [AVMutableAudioMixInputParameters] = []
            var cursor = CMTime.zero
            for clip in timeline.clips {
                try Task.checkCancellation()
                let original = directory.appendingPathComponent(clip.relativePath)
                guard FileManager.default.fileExists(atPath: original.path) else { throw TimelineFailure.missingMedia }
                let source: URL
                if clip.kind == .image {
                    source = directory.appendingPathComponent(UUID().uuidString + "-still.mp4"); temporary.append(source)
                    try await writeStill(original, duration: clip.duration, width: size.width, height: size.height, to: source)
                } else { source = original }
                let asset = AVURLAsset(url: source)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw TimelineFailure.missingMedia }
                let sourceDuration = try await asset.load(.duration)
                let trimStart = clip.kind == .image ? 0 : clip.start
                guard trimStart + clip.duration <= sourceDuration.seconds + 0.04 else { throw TimelineFailure.mediaTooShort }
                let range = CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 600), duration: CMTime(seconds: clip.duration, preferredTimescale: 600))
                let outputDuration = CMTime(seconds: clip.outputDuration, preferredTimescale: 600)
                try videoTrack.insertTimeRange(range, of: track, at: cursor)
                videoTrack.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: outputDuration)
                let native = try await track.load(.naturalSize)
                let orientation = try await track.load(.preferredTransform)
                let transform = Self.fitTransform(size: native, orientation: orientation, width: size.width, height: size.height)
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack); layer.setTransform(transform, at: cursor)
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(start: cursor, duration: outputDuration); instruction.layerInstructions = [layer]
                instruction.backgroundColor = CGColor(gray: 0, alpha: 1); instructions.append(instruction)
                if clip.kind == .video, let audio = try await asset.loadTracks(withMediaType: .audio).first,
                   let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    try destination.insertTimeRange(range, of: audio, at: cursor)
                    destination.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration), toDuration: outputDuration)
                    let parameters = AVMutableAudioMixInputParameters(track: destination); parameters.setVolume(clip.volume, at: cursor); audioParameters.append(parameters)
                }
                cursor = CMTimeAdd(cursor, outputDuration)
            }
            if let name = timeline.voiceoverPath {
                let asset = AVURLAsset(url: directory.appendingPathComponent(name))
                guard let audio = try await asset.loadTracks(withMediaType: .audio).first,
                      let destination = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw TimelineFailure.missingMedia }
                let duration = try await asset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, cursor))
                try destination.insertTimeRange(range, of: audio, at: .zero)
                let parameters = AVMutableAudioMixInputParameters(track: destination)
                parameters.setVolume(timeline.voiceoverVolume, at: .zero); audioParameters.append(parameters)
            }
            let video = AVMutableVideoComposition(); video.renderSize = CGSize(width: size.width, height: size.height)
            video.frameDuration = CMTime(value: 1, timescale: 30); video.instructions = instructions
            let mix = AVMutableAudioMix(); mix.inputParameters = audioParameters
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1920x1080) else { throw TimelineFailure.exportFailed }
            session.videoComposition = video; session.audioMix = mix; session.outputURL = output; session.outputFileType = .mp4; session.shouldOptimizeForNetworkUse = true
            try await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    session.exportAsynchronously { continuation.resume() }
                }
                try Task.checkCancellation()
                guard session.status == .completed else { throw TimelineFailure.exportFailed }
            } onCancel: { session.cancelExport() }
            return output
        } catch {
            try? FileManager.default.removeItem(at: output); throw error
        }
    }
    public static func fitTransform(size: CGSize, orientation: CGAffineTransform, width: Int, height: Int) -> CGAffineTransform {
        let bounds = CGRect(origin: .zero, size: size).applying(orientation)
        let scale = min(CGFloat(width) / max(abs(bounds.width), 1), CGFloat(height) / max(abs(bounds.height), 1))
        return orientation.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (CGFloat(width) - abs(bounds.width) * scale) / 2, y: (CGFloat(height) - abs(bounds.height) * scale) / 2))
    }
    private func writeStill(_ source: URL, duration: Double, width: Int, height: Int, to output: URL) async throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary) else { throw TimelineFailure.missingMedia }
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        guard writer.canAdd(input) else { throw TimelineFailure.exportFailed }; writer.add(input)
        guard writer.startWriting() else { throw TimelineFailure.exportFailed }; writer.startSession(atSourceTime: .zero)
        do {
            guard let pool = adaptor.pixelBufferPool else { throw TimelineFailure.exportFailed }
            let frameCount = Int(ceil(duration * 30))
            for index in 0..<frameCount {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw TimelineFailure.exportFailed }
                    try await Task.sleep(for: .milliseconds(10)); try Task.checkCancellation()
                }
                var optional: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optional) == kCVReturnSuccess, let buffer = optional else { throw TimelineFailure.exportFailed }
                CVPixelBufferLockBaseAddress(buffer, [])
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                    CVPixelBufferUnlockBaseAddress(buffer, []); throw TimelineFailure.exportFailed
                }
                context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                let scale = min(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
                let rect = CGRect(x: (CGFloat(width) - CGFloat(image.width) * scale) / 2, y: (CGFloat(height) - CGFloat(image.height) * scale) / 2, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                context.draw(image, in: rect); CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else { throw TimelineFailure.exportFailed }
            }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw TimelineFailure.exportFailed }
        } catch { writer.cancelWriting(); throw error }
    }
}
