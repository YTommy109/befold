import AppKit

// MARK: - NSWindowDelegate

/// ウィンドウそのもののライフサイクル契機(閉じる・キーになる・リサイズ完了)に対する後始末と追随。
///
/// ここに置くのは「AppKit がウィンドウについて通知してくること」だけで、
/// 文書の状態の遷移(表示モード・スクロール位置)は `ViewerDocumentPresenter` の担当。
/// フレームは窓由来の値だが**保存先は持たない**。粒度がアプリ全体なので、値は delegate 越しに
/// ウィンドウ管理層へ渡す(TASK-583)。
@MainActor
extension ViewerWindowController: NSWindowDelegate {
    /// 現在のウィンドウフレーム(位置＋サイズ)を上位へ渡す。
    /// フルスクリーン中のフレームは通常ウィンドウの寸法として無意味なため渡さない。
    private func reportAdjustedFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        delegate?.viewerWindow(self, didAdjustFrameTo: window.frameDescriptor)
    }

    func windowWillClose(_ notification: Notification) {
        swipeMonitor.stop()
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

    /// リサイズ完了時にのみ記録する。ライブリサイズ中は windowDidResize が毎フレーム
    /// 飛ぶため、そこでは記録せず UserDefaults への連打を避ける。
    ///
    /// **閉じたときには記録しない(TASK-583)。** 複数の窓を一括で閉じると windowWillClose の
    /// 到達順は AppKit 任せで、どの窓の寸法が最後に残るかを制御できない。再起動時に窓ごとの
    /// 寸法を戻すのは、この経路ではなくセッションのレイアウト(`SessionLayout.TabGroup.frame`)。
    func windowDidEndLiveResize(_ notification: Notification) {
        reportAdjustedFrame()
    }
}
