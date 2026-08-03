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
        #expect(!RejectReason.binaryContent.localizedMessage.isEmpty)
    }

    @Test("理由ごとに異なる文言を返す")
    func localizedMessageDiffersByReason() {
        let messages = [
            RejectReason.unsupportedFormat.localizedMessage,
            RejectReason.fileTooLarge.localizedMessage,
            RejectReason.binaryContent.localizedMessage,
        ]

        #expect(Set(messages).count == messages.count)
    }

    /// バイナリ拒否は「形式が非対応」と区別できることに意味があるため、
    /// 汎用文言との差異を CLI 出力側でも固定する(TASK-260)。
    @Test("cliMessage も理由ごとに異なる文言を返す")
    func cliMessageDiffersByReason() {
        let messages = [
            RejectReason.unsupportedFormat.cliMessage,
            RejectReason.fileTooLarge.cliMessage,
            RejectReason.binaryContent.cliMessage,
        ]

        #expect(Set(messages).count == messages.count)
        #expect(messages.allSatisfy { !$0.isEmpty })
    }
}
