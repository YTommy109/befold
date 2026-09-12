import AppKit

/// ウィンドウの引き当て。開閉に伴う記録の追随は `ViewerWindowSessionSync` が担う。
extension ViewerWindowManager {
    /// 指定の正規化パスに対応する開状態のウィンドウを返す。
    /// 同一ファイルを複数ウィンドウで開いている場合は、そのいずれか(先頭)を返す。
    ///
    /// **復元の対象になる種別の窓だけを見る**(TASK-616)。唯一の呼び出し元は
    /// `SessionRestorer.restoreLastSession` のキー窓決定で、引き当てたいのは復元した通常窓。
    /// `controllers` は復元の対象でない窓(スライド窓)も持つ多重マップなので、絞らないと
    /// 起動時の CLI 要求でスライド窓が先に開いていたときにそちらがキーになる。
    func window(forPath path: String) -> NSWindow? {
        controllers[path]?.first { $0.kind.isRestorable }?.window
    }
}
