@testable import befold
import Foundation
import Testing

/// 能力(ViewerCapabilities)が提示状態から導出されること(ADR 0002 段 2)を検証する。
@Suite
struct ViewerCapabilitiesTests {
    private func makeCapabilities(
        isPresentingDocument: Bool = true,
        isRejected: Bool = false,
        isRenderable: Bool = true,
        isBinaryContent: Bool = false,
        showsCodeContent: Bool = true,
        showsDiff: Bool = false,
        supportsSourceMode: Bool = true,
        supportsDiffDisplay: Bool = true,
        gitDiffAvailability: GitDiffAvailability = .changed,
        isDirectHTMLMode: Bool = false,
        isDocumentJumpEnabled: Bool = true
    ) -> ViewerCapabilities {
        ViewerCapabilities(
            isPresentingDocument: isPresentingDocument,
            isRejected: isRejected,
            isRenderable: isRenderable,
            isBinaryContent: isBinaryContent,
            showsCodeContent: showsCodeContent,
            showsDiff: showsDiff,
            supportsSourceMode: supportsSourceMode,
            supportsDiffDisplay: supportsDiffDisplay,
            gitDiffAvailability: gitDiffAvailability,
            isDirectHTMLMode: isDirectHTMLMode,
            isDocumentJumpEnabled: isDocumentJumpEnabled
        )
    }

    @Test("フォルダー一覧の表示中は、見えない文書に対する操作をすべて許さない")
    func deniesEverythingWhilePresentingFolder() {
        let capabilities = makeCapabilities(isPresentingDocument: false)

        #expect(!capabilities.canPrint)
        #expect(!capabilities.canFind)
        #expect(!capabilities.canZoom)
        #expect(!capabilities.canToggleSourceMode)
        #expect(!capabilities.canSelectPreviewMode)
        #expect(!capabilities.canSelectSourceMode)
        #expect(!capabilities.canToggleLineNumbers)
        #expect(!capabilities.canBookmark)
    }

    @Test("文書を提示していれば、種別に応じた操作が許される")
    func allowsDocumentCommandsWhilePresentingDocument() {
        let capabilities = makeCapabilities()

        #expect(capabilities.canPrint)
        #expect(capabilities.canFind)
        #expect(capabilities.canZoom)
        #expect(capabilities.canToggleSourceMode)
        #expect(capabilities.canBookmark)
    }

    @Test("HTML 直接ロード中は検索だけを止め、他は止めない")
    func disablesOnlyFindInDirectHTMLMode() {
        let capabilities = makeCapabilities(isDirectHTMLMode: true)

        #expect(!capabilities.canFind)
        #expect(capabilities.canPrint)
        #expect(capabilities.canZoom)
    }

    @Test("表示できないファイルでは文書操作を許さない")
    func deniesCommandsForRejectedFile() {
        let capabilities = makeCapabilities(isRejected: true)

        #expect(!capabilities.canPrint)
        #expect(!capabilities.canFind)
        #expect(!capabilities.canZoom)
        #expect(!capabilities.canToggleSourceMode)
    }

    @Test("モード切替は種別で決まる: 画像・PDF はソース側、プレビュー不可の種別はプレビュー側を落とす")
    func modeSelectionFollowsFileType() {
        #expect(!makeCapabilities(isBinaryContent: true).canSelectSourceMode)
        #expect(makeCapabilities(isBinaryContent: true).canSelectPreviewMode)
        #expect(!makeCapabilities(isRenderable: false).canSelectPreviewMode)
        #expect(makeCapabilities(isRenderable: false).canSelectSourceMode)
    }

    @Test("行番号はソース相当の内容を表示しているときだけ切り替えられる")
    func lineNumbersFollowCodeContent() {
        #expect(makeCapabilities(showsCodeContent: true).canToggleLineNumbers)
        #expect(!makeCapabilities(showsCodeContent: false).canToggleLineNumbers)
    }

    /// CSV/TSV は viewer 側が差分を描かない(viewer-main.js の type === "csv" 分岐)。
    /// ここで許すと、描かれない差分のために git のサブプロセスだけが走る(TASK-324)。
    @Test("差分は種別が差分表示に対応しているときだけ選べる")
    func diffFollowsDiffDisplaySupport() {
        #expect(makeCapabilities(supportsDiffDisplay: true).canSelectDiffMode)
        #expect(!makeCapabilities(supportsDiffDisplay: false).canSelectDiffMode)
        // テキストソースを持たない種別(画像・PDF)は差分も選べない。
        #expect(!makeCapabilities(isBinaryContent: true, supportsDiffDisplay: true).canSelectDiffMode)
    }

    /// 差分を選ぶこと自体がソース表示へ移る操作なので、レンダリング表示中でも
    /// 差分は選べなければならない。ここを「いまソースを出しているか」で判定すると、
    /// ⌘3 が押せず一度 ⌘2 を経由しないと差分へ行けなくなる。
    @Test("差分はレンダリング表示中でも選べる")
    func diffSelectableWhileRendered() {
        #expect(makeCapabilities(showsCodeContent: false, supportsDiffDisplay: true).canSelectDiffMode)
    }

    /// レイアウトの切替は差分を選んでいる間だけ意味を持つ(AC#3)。
    @Test("差分レイアウトは差分表示中だけ切り替えられる")
    func diffLayoutRequiresDiffMode() {
        #expect(makeCapabilities(showsDiff: true, supportsDiffDisplay: true).canToggleDiffLayout)
        #expect(!makeCapabilities(showsDiff: false, supportsDiffDisplay: true).canToggleDiffLayout)
        #expect(!makeCapabilities(showsDiff: true, supportsDiffDisplay: false).canToggleDiffLayout)
    }

    /// ADR(libgit2 移行)の Fallback: git が使えないときは差分表示モードを選択不可にする。
    /// 種別だけで決めていた頃は、モードは選べて取得結果が nil に畳まれ、黙って通常の
    /// ソース表示へ戻っていた(TASK-438.2)。
    @Test("差分表示モードの可否は git 側の事実も見る")
    func diffSelectionFollowsGitAvailability() {
        #expect(makeCapabilities(gitDiffAvailability: .changed).canSelectDiffMode)
        // 未解決の間は選べるまま。ここを不可にすると初期表示で無効→有効が入れ替わる。
        #expect(makeCapabilities(gitDiffAvailability: .undetermined).canSelectDiffMode)
        #expect(!makeCapabilities(gitDiffAvailability: .unavailable).canSelectDiffMode)
        #expect(!makeCapabilities(gitDiffAvailability: .unchanged).canSelectDiffMode)
    }

    /// ツールバーのセグメントもメニューも `canSelect(_:)` だけを見る(ADR 0002 段 2)。
    /// 条件が 1 箇所にあることを、モード別の対応表側からも固定する。
    @Test("git が使えないときは canSelect(.diff) も落ちる")
    func canSelectDiffFollowsTheSameCondition() {
        #expect(!makeCapabilities(gitDiffAvailability: .unavailable).canSelect(.diff))
        #expect(makeCapabilities(gitDiffAvailability: .unavailable).canSelect(.source))
        #expect(makeCapabilities(gitDiffAvailability: .changed).canSelect(.diff))
    }

    @Test("文書内ジャンプはゲートが閉じている間は不可")
    func deniesJumpWhileGateIsClosed() {
        #expect(makeCapabilities(isDocumentJumpEnabled: true).canJump)
        #expect(!makeCapabilities(isDocumentJumpEnabled: false).canJump)
    }

    @Test("文書内ジャンプは検索と同じく HTML 直接ロード中と非提示中は不可")
    func deniesJumpWithoutVisibleDocument() {
        #expect(!makeCapabilities(isPresentingDocument: false).canJump)
        #expect(!makeCapabilities(isRejected: true).canJump)
        #expect(!makeCapabilities(isDirectHTMLMode: true).canJump)
    }

    @Test("何も提示していない既定値はすべて不可")
    func noneDeniesEverything() {
        #expect(ViewerCapabilities.none == ViewerCapabilities(
            isPresentingDocument: false, isRejected: false, isRenderable: false,
            isBinaryContent: false, showsCodeContent: false, supportsSourceMode: false,
            supportsDiffDisplay: false, gitDiffAvailability: .undetermined, isDirectHTMLMode: false,
            isDocumentJumpEnabled: false
        ))
        #expect(!ViewerCapabilities.none.canPrint)
    }
}

extension ViewerCapabilities {
    /// すべて可能な状態。コマンド実行側のテストが「能力あり」を簡潔に表すために使う。
    static let allEnabledForTesting = ViewerCapabilities(
        isPresentingDocument: true,
        isRejected: false,
        isRenderable: true,
        isBinaryContent: false,
        showsCodeContent: true,
        supportsSourceMode: true,
        supportsDiffDisplay: true,
        gitDiffAvailability: .changed,
        isDirectHTMLMode: false,
        isDocumentJumpEnabled: true
    )
}
