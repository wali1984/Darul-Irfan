import Foundation
import XCTest
@testable import DarulIrfan

final class PushUnregistrationTests: XCTestCase {
    func testOfflineAndRejectedUnsubscribeRemainRetryable() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnregistrationProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for code in [0, 401, 403, 429, 500, 503] {
            var request = URLRequest(url: URL(string: "https://unsubscribe.invalid/\(code)")!)
            request.httpMethod = "DELETE"
            let acknowledged = await PushUnregistration.send(request, session: session)
            XCTAssertFalse(acknowledged, "Failure \(code) must retain credentials for retry")
        }
        for code in [200, 204, 404] {
            var request = URLRequest(url: URL(string: "https://unsubscribe.invalid/\(code)")!)
            request.httpMethod = "DELETE"
            let acknowledged = await PushUnregistration.send(request, session: session)
            XCTAssertTrue(acknowledged, "Confirmed removal \(code) can clear credentials")
        }
    }
}

private final class UnregistrationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let code = Int(request.url!.lastPathComponent)!
        guard code != 0 else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
