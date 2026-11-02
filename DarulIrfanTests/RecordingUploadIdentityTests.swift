import Foundation
import XCTest
@testable import DarulIrfan

@MainActor
final class RecordingUploadIdentityTests: XCTestCase {
    func testUploadReturnsItsOwnIdentityWithoutFetchingTheSharedLibrary() async throws {
        let id = try await upload(response: #"{"ok":true,"id":"my-recording"}"#)
        XCTAssertEqual(id, "my-recording")
    }

    func testMissingOrInvalidIdentityIsRejected() async throws {
        for response in ["{}", #"{"id":""}"#, #"{"id":"   "}"#, #"{"id":42}"#] {
            do {
                _ = try await upload(response: response)
                XCTFail("Expected an invalid upload identity to fail")
            } catch MemberGroupError.requestFailed { }
        }
    }

    private func upload(response: String) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingUploadProtocol.self]
        config.httpAdditionalHeaders = ["X-Fixture-Response": response]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp3")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let service = MemberGroupService(baseURL: URL(string: "https://recording-upload.invalid")!,
            session: transport, uploads: transport, savedSession: RecordingUploadSession())
        return try await service.uploadRecording(from: file, contentType: "audio/mpeg",
            title: "My recording", durationSeconds: 10, in: "usa")
    }
}

private final class RecordingUploadSession: MemberSessionStore, @unchecked Sendable {
    func load() -> MemberSession? { .init(token: "fixture", expiresAt: .distantFuture, memberID: "fixture") }
    func save(_ value: MemberSession) { }
    func delete() { }
    func deleteIfCurrent(token: String) -> Bool { true }
}

private final class RecordingUploadProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.httpMethod == "POST", request.url?.path == "/v1/groups/usa/recordings",
              let payload = request.value(forHTTPHeaderField: "X-Fixture-Response") else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
