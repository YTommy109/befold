import AppKit

/// ウィンドウの引き当て。開閉に伴う記録の追随は `ViewerWindowSessionSync` が担う。
extension ViewerWindowManager {
    /// 指定の正規化パスに対応する開状態のウィンドウを返す。
    /// 同一ファイルを複数ウィンドウで開いている場合は、そのいずれか(先頭)を返す。
    func window(forPath path: String) -> NSWindow? {
        controllers[path]?.first?.window
    }
}
