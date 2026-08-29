@testable import befold
import Foundation
import Testing

/// 読み込み中のスピナーを出す条件（TASK-567）。
///
/// **「まだ何も出せていない」ときだけ出す。** PDF は `content` ではなく `data` で
/// 描くため、PDF から別のファイルへ移る区間だけ「content が空」の判定が真になる。
/// 面の宛先は描画が確定した種別で切り替わるので、その間まだ PDF が見えている。
/// 空判定だけでスピナーを出すと、見えている PDF の上に一瞬重なる。
@MainActor
@Suite
struct ViewerContentStateLoadingIndicatorTests {
    @Test("何も出せていなければ出す")
    func showsWhileNothingIsOnScreen() {
        let state = ViewerContentState()
        state.beginLoading()

        #expect(state.showsLoadingIndicator)
    }

    /// `data` で描く種別（PDF）は `content` が空でも面が前の文書を出している。
    @Test("PDF の面が前の文書を出している間は出さない")
    func staysHiddenWhileThePDFSurfaceIsStillShowing() {
        let state = ViewerContentState()
        _ = state.applyDisplayState(ViewerContentState.DisplayState(
            fileType: .pdf, contentHash: 1, chunkSession: nil, rejectReason: nil,
            isTruncated: false, content: "", data: Data([0x25, 0x50]),
            tracksLineCount: false, hasDeclaredHTMLCharset: nil
        ))
        state.beginLoading()

        #expect(!state.showsLoadingIndicator)
    }

    @Test("すでに内容が出ていれば出さない")
    func staysHiddenWhenContentIsAlreadyShown() {
        let state = ViewerContentState()
        state.appendChunk("# hello", isAtEnd: true)
        state.beginLoading()

        #expect(!state.showsLoadingIndicator)
    }

    @Test("読み込みが終われば出さない")
    func staysHiddenAfterLoading() {
        let state = ViewerContentState()
        state.beginLoading()
        state.finishLoading(url: URL(fileURLWithPath: "/files/a.md"))

        #expect(!state.showsLoadingIndicator)
    }
}
