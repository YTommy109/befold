import AppKit

// MARK: - NSWindowDelegate

/// ウィンドウそのもののライフサイクル契機(閉じる・キーになる・リサイズ完了)に対する後始末と追随。
///
/// ここに置くのは「AppKit がウィンドウについて通知してくること」だけで、
/// 文書の状態の遷移(表示モード・スクロール位置)は `+Presentation` の担当。
/// フレームの保存だけはウィンドウ由来の値をファイル単位で永続化するため、この層が持つ。
@MainActor
extension ViewerWindowController: NSWindowDelegate {
    /// 現在のウィンドウフレーム(位置＋サイズ)を保存する。
    /// フルスクリーン中のフレームは通常ウィンドウの寸法として無意味なため保存しない。
    private func saveWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        perFileState.windowFrame.recordUserAdjustedFrame(window.frameDescriptor, for: fileURL)
    }

    func windowWillClose(_ notification: Notification) {
        swipeMonitor.stop()
        saveWindowFrame()
        store.close()
        sidebar.cancelPendingListing()
        delegate?.viewerWindowWillClose(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // ディレクトリ監視はしていないため、キーになったタイミングで一覧を取り直し、
        // 他所で作成/削除されたファイルをサイドバーへ反映する。
        sidebar.refreshFileList()
        delegate?.viewerWindowDidBecomeKey(self)
    }

    /// リサイズ完了時にのみ保存する。ライブリサイズ中は windowDidResize が毎フレーム
    /// 飛ぶため、そこでは保存せず UserDefaults への連打を避ける。
    /// ドラッグ移動やタイリングでの位置変更は windowWillClose 時にまとめて保存される。
    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrame()
    }
}
