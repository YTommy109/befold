import BefoldKit

// MARK: - Presentation State / Capabilities

extension ViewerWindowController {
    /// プレビュー領域がフォルダー一覧を出しているか。ViewerContentView と同じ
    /// fileListModel.previewTarget を見る(導出点は 1 つ。ADR 0002)。
    var isPreviewingFolder: Bool {
        fileListModel.previewTarget.folderURL != nil
    }

    /// いま何ができるか。メニュー・ツールバー・コマンド実行はすべてこの値だけを見る(ADR 0002)。
    /// 条件をここ以外に書かないことで、「メニューは無効なのに別経路では通る」を作らない。
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
}
