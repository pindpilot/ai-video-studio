import XCTest
@testable import ProviderKit
final class CloudflareTests: XCTestCase {
    func testTextEnvelope() throws {
        let data = Data(#"{"success":true,"result":{"response":"A script"}}"#.utf8)
        XCTAssertEqual(try CloudflareAdapter.decodeText(data).text, "A script")
    }
    func testFalseSuccessAndMalformedResponseRejected() {
        for source in [#"{"success":false,"result":{"response":"no"}}"#, #"{"success":true,"result":{}}"#, "not json"] {
            XCTAssertThrowsError(try CloudflareAdapter.decodeText(Data(source.utf8)))
        }
    }
    func testImageContractAndInvalidBase64() throws {
        let jpegHeader = Data([0xff, 0xd8, 0xff, 0xe0])
        let encoded = jpegHeader.base64EncodedString()
        let fixture = try JSONSerialization.data(withJSONObject: ["success": true, "result": ["image": encoded]])
        XCTAssertEqual(try CloudflareAdapter.decodeImage(fixture), jpegHeader)
        XCTAssertThrowsError(try CloudflareAdapter.decodeImage(Data(#"{"success":true,"result":{"image":"not-base64"}}"#.utf8)))
    }
    func testExactRequestAndHTTPFailure() async throws {
        let adapter = CloudflareAdapter(accountID: String(repeating: "a", count: 32), token: "fixture-only", outputDirectory: FileManager.default.temporaryDirectory) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.cloudflare.com/client/v4/accounts/" + String(repeating: "a", count: 32) + "/ai/run/@cf/meta/llama-3.2-3b-instruct")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
            return HTTPReply(data: Data(), status: 429, retryAfter: "120")
        }
        do { _ = try await adapter.generateText(.init(capability: .text, text: "Idea")); XCTFail("Must fail") }
        catch let error as ProviderFailure { XCTAssertEqual(error.kind, .rateLimited); XCTAssertNotNil(error.retryAfter) }
    }
    func testUnknownImageDimensionsRejectedBeforeTransport() async {
        let adapter = CloudflareAdapter(accountID: "bad", token: "", outputDirectory: FileManager.default.temporaryDirectory) { _ in
            XCTFail("Must not call transport"); return HTTPReply(data: Data(), status: 200)
        }
        var request = GenerationRequest(capability: .image, text: "An image"); request.ratio = "9:16"
        do { _ = try await adapter.generateImage(request); XCTFail("Must fail") }
        catch let error as ProviderFailure { XCTAssertEqual(error.kind, .invalidRequest) }
        catch { XCTFail("Wrong error") }
    }
}
