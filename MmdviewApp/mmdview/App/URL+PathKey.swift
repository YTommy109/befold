import Foundation

extension URL {
    /// UserDefaults やウィンドウ管理の辞書キーに使う、正規化済みのパス文字列。
    /// シンボリックリンクを解決した絶対パスに揃えることで、同一ファイルを指す
    /// 別表記の URL（シンボリックリンク経由・相対パス等）を同じキーに集約する。
    var normalizedPathKey: String {
        resolvingSymlinksInPath().path
    }

    /// ウィンドウフレームの autosave 名。normalizedPathKey と同じ正規化基準を使い、
    /// パス区切りをキーに使えない文字へ置換する。
    var viewerFrameAutosaveName: String {
        "Viewer-" + normalizedPathKey.replacingOccurrences(of: "/", with: "_")
    }
}
