import BefoldKit
import Testing

/// RejectReason のユーザー向け文言が BefoldKit のリソースバンドルから
/// 取得できることを検証する(QuickLook 拡張からの再利用可否の担保)。
@Suite
struct RejectReasonTests {
    @Test("localizedMessage が非空の文言を返す")
    func localizedMessageIsNotEmpty() {
        #expect(!RejectReason.unsupportedFormat.localizedMessage.isEmpty)
        #expect(!RejectReason.fileTooLarge.localizedMessage.isEmpty)
    }

    @Test("理由ごとに異なる文言を返す")
    func localizedMessageDiffersByReason() {
        #expect(
            RejectReason.unsupportedFormat.localizedMessage
                != RejectReason.fileTooLarge.localizedMessage
        )
    }
}
