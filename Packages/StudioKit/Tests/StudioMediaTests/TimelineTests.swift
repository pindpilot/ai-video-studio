import XCTest
@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import StudioMedia
final class TimelineTests: XCTestCase {
    func testDimensionsSplitSpeedAndValidation() throws {
        XCTAssertEqual(ExportRatio.portrait.dimensions(fullHD: false).height, 1280)
        XCTAssertEqual(ExportRatio.landscape.dimensions(fullHD: true).width, 1920)
        XCTAssertEqual(ExportRatio.square.dimensions(fullHD: true).height, 1080)
        var document = TimelineDocument(); document.clips = [.init(relativePath: "image.jpg", kind: .image, duration: 6, speed: 2)]
        let id = document.clips[0].id; try document.split(id, at: 2)
        XCTAssertEqual(document.clips.count, 2); XCTAssertEqual(document.duration, 3)
        XCTAssertEqual(document.clips[1].start, 2)
        try document.validate()
        document.clips[0].relativePath = "../private"; XCTAssertThrowsError(try document.validate())
    }
    func testInvalidTimeAndEmptyTimelineRejected() {
        XCTAssertThrowsError(try TimelineDocument().validate())
        var document = TimelineDocument(); document.clips = [.init(relativePath: "clip.mp4", kind: .video, duration: .nan)]
        XCTAssertThrowsError(try document.validate())
        document.clips[0].duration = 10; document.clips[0].speed = 0
        XCTAssertThrowsError(try document.validate())
    }
    func testDiskTimelineRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = TimelineDocument(); document.clips = [.init(relativePath: "clip.mov", kind: .video, duration: 4)]
        let first = TimelineFiles(directory: directory); try await first.save(document)
        let loaded = try await TimelineFiles(directory: directory).load(); XCTAssertEqual(loaded, document)
    }
    func testPhotoImportNormalizesToJPEGAndRejectsInvalidData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = CGContext(data: nil, width: 80, height: 120, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        let source = directory.appendingPathComponent("source.png")
        let output = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(output))
        let files = TimelineFiles(directory: directory)
        let name = try await files.importPhoto(source)
        XCTAssertTrue(name.hasSuffix(".jpg"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let imported = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)!
        XCTAssertEqual(CGImageSourceGetType(imported) as String?, UTType.jpeg.identifier)
        XCTAssertEqual(CGImageSourceCreateImageAtIndex(imported, 0, nil)?.height, 120)
        let bad = directory.appendingPathComponent("bad.png")
        try Data("not an image".utf8).write(to: bad)
        do { _ = try await files.importPhoto(bad); XCTFail("Invalid photo must be rejected") }
        catch { XCTAssertTrue(error is TimelineFailure) }
    }
    func testRealStillExportHasCorrectSizeDurationAndCodec() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = context.makeImage()!
        let source = directory.appendingPathComponent("fixture.png")
        let destination = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        var timeline = TimelineDocument(); timeline.ratio = .square; timeline.clips = [.init(relativePath: source.lastPathComponent, kind: .image, duration: 1)]
        let output = try await VideoExporter().export(timeline, directory: directory)
        let asset = AVURLAsset(url: output); let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1, accuracy: 0.1)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize); XCTAssertEqual(size.width, 720); XCTAssertEqual(size.height, 720)
        let descriptions = try await track.load(.formatDescriptions)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(descriptions[0]), kCMVideoCodecType_H264)
        // Save a decoded actual frame for visual inspection, not only codec metadata.
        if let evidence = ProcessInfo.processInfo.environment["MEDIA_EVIDENCE_DIR"] {
            try FileManager.default.createDirectory(atPath: evidence, withIntermediateDirectories: true)
            let generator = AVAssetImageGenerator(asset: asset)
            let (frame, _) = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
            let url = URL(fileURLWithPath: evidence).appendingPathComponent("M4-export-frame.png")
            let png = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(png, frame, nil); XCTAssertTrue(CGImageDestinationFinalize(png))
            let fixture = URL(fileURLWithPath: evidence).appendingPathComponent("M4-fixture.mp4")
            try? FileManager.default.removeItem(at: fixture)
            try FileManager.default.copyItem(at: output, to: fixture)
        }
    }
}
