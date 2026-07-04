import Foundation
@testable import mmdview
import Testing

@Suite
struct URLResponseValidationTests {
    private func httpResponse(status: Int) throws -> HTTPURLResponse {
        guard let url = URL(string: "https://example.com/x") else {
            throw URLError(.badURL)
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: status, httpVersion: nil, headerFields: nil
        ) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    @Test(arguments: [404, 500, 301])
    func throwsForNonSuccessStatus(status: Int) throws {
        let response = try httpResponse(status: status)

        #expect(throws: URLError.self) {
            try response.validateHTTPSuccess()
        }
    }

    @Test(arguments: [200, 204, 299])
    func passesForSuccessStatus(status: Int) throws {
        let response = try httpResponse(status: status)

        #expect(throws: Never.self) {
            try response.validateHTTPSuccess()
        }
    }

    @Test("HTTP 以外の応答(file:// 等)は検証せず通す")
    func passesForNonHTTPResponse() {
        let response = URLResponse(
            url: URL(fileURLWithPath: "/files/a.dmg"),
            mimeType: nil, expectedContentLength: 0, textEncodingName: nil
        )

        #expect(throws: Never.self) {
            try response.validateHTTPSuccess()
        }
    }
}
