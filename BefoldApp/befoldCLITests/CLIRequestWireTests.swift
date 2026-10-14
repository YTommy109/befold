@testable import BefoldCLI
import BefoldKit
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
            displayMode: .source, showSidebar: false
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

    // 往復テストはフィールド名や case 名の変更を検知できない(両側が同じ型で追従するため)。
    // 旧版の CLI と新版の本体(またはその逆)が混在しうるので、固定 JSON を直接デコードして守る。

    @Test("旧形式の固定 JSON(オープン要求・全オプション)をデコードできる")
    func decodesLegacyOpenRequestJSON() {
        let json = """
        {"open":{"paths":["/tmp/a.mmd"],"options":{"showHiddenFiles":true,"sortOrder":"folders-first",\
        "showLineNumbers":false,"sourceMode":true,"showSidebar":false}}}
        """

        let decoded = CLIRequestWire.decode(userInfo: ["request": json, "requestID": "id"])

        let options = CLIOpenOptions(
            showHiddenFiles: true, sortOrder: .foldersFirst, showLineNumbers: false,
            displayMode: .source, showSidebar: false
        )
        #expect(decoded == .open(paths: ["/tmp/a.mmd"], options: options))
    }

    /// 旧 CLI の --source/--preview は sourceMode: Bool で届く。displayMode へ読み替えないと
    /// アップデート直後の旧 CLI のフラグが黙って捨てられる(TASK-700)。
    @Test(
        "旧 CLI の sourceMode は displayMode へ読み替えられる",
        arguments: [(true, CLIDisplayModeOption.source), (false, .rendered)]
    )
    func decodesLegacySourceModeAsDisplayMode(legacy: Bool, expected: CLIDisplayModeOption) {
        let json = #"{"open":{"paths":["/tmp/a.md"],"options":{"sourceMode":\#(legacy)}}}"#

        let decoded = CLIRequestWire.decode(userInfo: ["request": json, "requestID": "id"])

        #expect(decoded == .open(paths: ["/tmp/a.md"], options: CLIOpenOptions(displayMode: expected)))
    }

    @Test("sourceMode と displayMode が両方あれば displayMode が勝ち、diff も運べる")
    func displayModeWinsOverLegacySourceMode() {
        let json = """
        {"open":{"paths":["/a.md"],"options":{"sourceMode":false,\
        "displayMode":"diff","comparisonTarget":"head"}}}
        """

        let decoded = CLIRequestWire.decode(userInfo: ["request": json, "requestID": "id"])

        let options = CLIOpenOptions(displayMode: .diff, comparisonTarget: .head)
        #expect(decoded == .open(paths: ["/a.md"], options: options))
    }

    @Test("opensInNewWindow は旧 JSON(キー無し)で false、送ると往復できる")
    func opensInNewWindowIsBackwardCompatible() throws {
        let legacy = #"{"open":{"paths":["/a.md"],"options":{}}}"#
        #expect(CLIRequestWire.decode(userInfo: ["request": legacy, "requestID": "id"])
            == .open(paths: ["/a.md"], options: CLIOpenOptions()))

        let request = CLIRequest.open(paths: ["/a.md"], options: CLIOpenOptions(opensInNewWindow: true))
        let info = try #require(CLIRequestWire.userInfo(for: request, requestID: "id"))
        #expect(CLIRequestWire.decode(userInfo: info) == request)
    }

    @Test("line は往復でき、旧 JSON(キー無し)では nil になる")
    func lineRoundTripsAndIsBackwardCompatible() throws {
        let request = CLIRequest.open(paths: ["/a.md"], options: CLIOpenOptions(displayMode: .source, line: 120))
        let info = try #require(CLIRequestWire.userInfo(for: request, requestID: "id"))
        #expect(CLIRequestWire.decode(userInfo: info) == request)

        let legacy = #"{"open":{"paths":["/a.md"],"options":{"displayMode":"source"}}}"#
        #expect(CLIRequestWire.decode(userInfo: ["request": legacy, "requestID": "id"])
            == .open(paths: ["/a.md"], options: CLIOpenOptions(displayMode: .source)))
    }

    @Test("送信側は旧キー sourceMode を出力しない")
    func encodingNeverEmitsLegacySourceMode() throws {
        let data = try JSONEncoder().encode(CLIOpenOptions(displayMode: .source))
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("sourceMode"))
        #expect(json.contains(#""displayMode":"source""#))
    }

    @Test("旧形式の固定 JSON でオプションの各フィールドを省略すると nil になる")
    func decodesLegacyOpenRequestJSONWithOmittedOptions() {
        let json = #"{"open":{"paths":["/tmp/a.mmd"],"options":{"sortOrder":"alphabetical"}}}"#

        let decoded = CLIRequestWire.decode(userInfo: ["request": json, "requestID": "id"])

        #expect(decoded == .open(paths: ["/tmp/a.mmd"], options: CLIOpenOptions(sortOrder: .alphabetical)))
    }

    @Test("旧形式の固定 JSON(ブックマーク要求)をデコードできる")
    func decodesLegacyBookmarkRequestJSON() {
        let json = #"{"bookmark":{"paths":["/tmp/a.mmd","/tmp/b.md"]}}"#

        let decoded = CLIRequestWire.decode(userInfo: ["request": json, "requestID": "id"])

        #expect(decoded == .bookmark(paths: ["/tmp/a.mmd", "/tmp/b.md"]))
    }
}
