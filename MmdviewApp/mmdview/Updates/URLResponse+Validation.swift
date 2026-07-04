import Foundation

extension URLResponse {
    /// HTTP 応答のステータスが 2xx 以外なら URLError(.badServerResponse) を投げる。
    /// HTTP 以外の応答(file:// 等)は検証せず通す。
    func validateHTTPSuccess() throws {
        if let http = self as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }
}
