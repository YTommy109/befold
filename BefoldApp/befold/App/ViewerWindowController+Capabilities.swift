import BefoldKit

// MARK: - Presentation State / Capabilities

/// 「いま何を提示していて、そこで何ができるか」を提示状態から導出する層(ADR 0002 段 2)。
///
/// メニューの有効判定・ツールバーの有効判定・コマンドの実行ガードは、すべてここが返す
/// `ViewerCapabilities` だけを見る。**条件をここ以外に書かない**ことで、
/// 「メニューは無効なのに別経路では通る」を作らない。
///
/// 導出そのものは `ViewerCapabilitiesFactory` が持ち、ここはウィンドウ側の入力
/// (提示対象・現在 URL・WebView の状態)を集めて渡すだけにする。
@MainActor
extension ViewerWindowController {
    /// プレビュー領域がフォルダー一覧を出しているか。ViewerContentView と同じ
    /// fileListModel.previewTarget を見る(導出点は 1 つ。ADR 0002)。
    var isPreviewingFolder: Bool {
        fileListModel.previewTarget.folderURL != nil
    }

    /// いま何ができるか。メニュー・ツールバー・コマンド実行はすべてこの値だけを見る(ADR 0002)。
    /// 導出そのものは ViewerCapabilitiesFactory(ウィンドウを知らない純関数)に置く。
    var capabilities: ViewerCapabilities {
        ViewerCapabilitiesFactory.make(
            store: store, isPresentingDocument: !isPreviewingFolder,
            fileURL: fileURL, gitDiffAvailability: gitDiffAvailability,
            isDirectHTMLMode: webViewProxy.isDirectHTMLMode
        )
    }

    /// 差分を出せる git の事実。サイドバーが持つ値(基準ディレクトリの種別・git 状態)から
    /// 導出する。サイドバーを畳んでいてもこの 2 つは取得され続けるため、表示の有無に
    /// 依存しない。
    private var gitDiffAvailability: GitDiffAvailability {
        GitDiffAvailability.make(
            baseDirectory: fileListModel.baseDirectory,
            gitStatus: fileListModel.gitStatus,
            fileURL: fileURL
        )
    }

    /// そのモードをいま選べるか(ViewerToolbarHost の要求)。判断は capabilities 側にある。
    func canSelect(_ mode: ViewerDisplayMode) -> Bool {
        capabilities.canSelect(mode)
    }
}
