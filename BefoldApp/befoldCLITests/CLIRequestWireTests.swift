@testable import BefoldCLI
import Foundation
import Testing

/// 送信側(CLI)と受信側(befold.app)が共有するワイヤ表現の検証。
///
/// フィールドごとの文字列キーを手写しせず CLIRequest の Codable 適合に委ねているため、
/// ここでの往復検証が「CLIOpenOptions にフィールドを足しても送受が追従する」ことの担保になる
/// (フィールド名を列挙している箇所は Swift の合成 Codable だけで、送受のコードにはない)。
@Suite
struct CLIRequestWireTests {
    /// `.open` の paths/options を取り出す。種別が違えば nil を返す。
    private func openPayload(_ request: CLIRequest?) -> (paths: [String], options: CLIOpenOptions)? {
        guard case let .open(paths, options) = request else { return nil }
        return (paths, options)
    }

    @Test("全オプションを埋めたオープン要求が往復する")
    func roundTripsOpenRequestWithAllOptions() {
        let options = CLIOpenOptions(
            showHiddenFiles: true, sortOrder: .alphabetical, showLineNumbers: false,
            sourceMode: true, showSidebar: false
        )
        let request = CLIRequest.open(paths: ["/tmp/a.mmd", "/tmp/b.md"], options: options)

        let userInfo = CLIRequestWire.userInfo(for: request, requestID: "test-id")
        let decoded = CLIRequestWire.decode(userInfo: userInfo)

        // == 比較なので、CLIOpenOptions にフィールドが増えてもこのテストが追従する。
        #expect(decoded == request)
        #expect(CLIRequestWire.requestID(from: userInfo) == "test-id")
    }

    @Test("オプション未指定のオープン要求は既定値のまま往復する")
    func roundTripsOpenRequestWithoutOptions() {
        let request = CLIRequest.open(paths: ["/tmp/a.mmd"], options: CLIOpenOptions())

        let decoded = openPayload(
            CLIRequestWire.decode(userInfo: CLIRequestWire.userInfo(for: request, requestID: "id"))
        )

        #expect(decoded?.paths == ["/tmp/a.mmd"])
        #expect(decoded?.options == CLIOpenOptions())
    }

    @Test("ブックマーク要求が往復する")
    func roundTripsBookmarkRequest() {
        let request = CLIRequest.bookmark(paths: ["/tmp/a.mmd", "/tmp/b.md"])

        let userInfo = CLIRequestWire.userInfo(for: request, requestID: "test-id")

        #expect(CLIRequestWire.decode(userInfo: userInfo) == request)
    }

    /// 要求本体は 1 つのキーへ JSON として載る。フィールドごとのキーが userInfo に
    /// 現れないことを固定し、手写しミラーの再導入を防ぐ。
    @Test("userInfo は要求本体と requestID の 2 キーだけを持つ")
    func userInfoCarriesOnlyRequestAndRequestID() throws {
        let request = CLIRequest.open(
            paths: ["/tmp/a.mmd"], options: CLIOpenOptions(showHiddenFiles: true)
        )

        let userInfo = try #require(CLIRequestWire.userInfo(for: request, requestID: "id"))

        #expect(Set(userInfo.keys) == ["request", "requestID"])
        #expect(userInfo["showHiddenFiles"] == nil)
    }

    @Test("要求本体のキーがない userInfo は nil を返す")
    func returnsNilWithoutRequestPayload() {
        #expect(CLIRequestWire.decode(userInfo: ["requestID": "test-id"]) == nil)
    }

    @Test("壊れた JSON は nil を返す")
    func returnsNilForMalformedPayload() {
        let userInfo: [AnyHashable: Any] = ["request": "{not json", "requestID": "id"]

        #expect(CLIRequestWire.decode(userInfo: userInfo) == nil)
    }

    @Test("nil の userInfo は nil を返す")
    func returnsNilForNilUserInfo() {
        #expect(CLIRequestWire.decode(userInfo: nil) == nil)
    }

    @Test("requestID がなければ nil")
    func requestIDMissingReturnsNil() {
        #expect(CLIRequestWire.requestID(from: ["request": "{}"]) == nil)
    }
}
