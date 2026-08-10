import BefoldKit

// MARK: - Presentation State / Capabilities

/// 「いま何を提示していて、そこで何ができるか」を提示状態から導出する層(ADR 0002 段 2)。
///
/// メニューの有効判定・ツールバーの有効判定・コマンドの実行ガードは、すべてここが返す
/// `ViewerCapabilities` だけを見る。**条件をここ以外に書かない**ことで、
/// 「メニューは無効なのに別経路では通る」を作らない。
///
/// `ViewerCapabilities` 自身は `import Foundation` だけの純粋な値型に保ち、
/// `ViewerStore` や `URL` から Bool を取り出す作業(＝どの入力を信じるか)はこちら側に置く。
/// 両者を 1 つのイニシャライザへ畳むと、下の `supportsDiffDisplay` だけ入力が違う理由が
/// 見えなくなり、揃えたくなる圧力が生まれる(TASK-338 の再発経路)。
@MainActor
extension ViewerWindowController {
    /// プレビュー領域がフォルダー一覧を出しているか。ViewerContentView と同じ
    /// fileListModel.previewTarget を見る(導出点は 1 つ。ADR 0002)。
    var isPreviewingFolder: Bool {
        fileListModel.previewTarget.folderURL != nil
    }

    /// いま何ができるか。メニュー・ツールバー・コマンド実行はすべてこの値だけを見る(ADR 0002)。
    var capabilities: ViewerCapabilities {
        ViewerCapabilities(
            isPresentingDocument: !isPreviewingFolder,
            isRejected: store.isRejected,
            isRenderable: store.fileType.isRenderable,
            isBinaryContent: store.fileType.isBinaryContent,
            showsCodeContent: store.showsCodeContent,
            showsDiff: store.showsDiff,
            supportsSourceMode: store.fileType.supportsSourceMode,
            // 差分の種別ゲートだけは、いま表示中の URL から直接導く。store.fileType は
            // 非同期のコンテンツロード完了まで旧ファイルの値を保つため、切替中に届いた
            // 取得契機(`.git/index` 変更・他ウィンドウの保存)が旧ファイルの種別で通り、
            // 差分を描けない CSV/TSV に対して git を起こしてしまう(TASK-338)。
            supportsDiffDisplay: FileType(url: fileURL).supportsDiffDisplay,
            isDirectHTMLMode: webViewProxy.isDirectHTMLMode
        )
    }

    /// そのモードをいま選べるか。ツールバーのセグメントとメニューの有効判定が共有する。
    func canSelect(_ mode: ViewerDisplayMode) -> Bool {
        switch mode {
        case .rendered: capabilities.canSelectPreviewMode
        case .source: capabilities.canSelectSourceMode
        case .diff: capabilities.canSelectDiffMode
        }
    }
}
