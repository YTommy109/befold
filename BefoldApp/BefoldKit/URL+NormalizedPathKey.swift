import Foundation

public extension URL {
    /// UserDefaults やウィンドウ管理の辞書キーに使う、正規化済みのパス文字列。
    /// シンボリックリンクを解決した絶対パスに揃えることで、同一ファイルを指す
    /// 別表記の URL（シンボリックリンク経由・相対パス等）を同じキーに集約する。
    var normalizedPathKey: String {
        resolvingSymlinksInPath().path
    }

    /// パス文字列を native な連続 UTF-8 に揃えた、同値の file URL。
    /// FileManager 由来の URL はパスが NSString 裏打ちで、URL の Hashable が
    /// 1 文字ずつ ObjC を呼ぶ Unicode 正規化経路（`-[__NSCFString characterAtIndex:]`）に
    /// 落ちる。SwiftUI の ForEach は行 ID を辞書キーにするたびにこれを走らせるため、
    /// 300 件規模の一覧でメインスレッドが詰まる（344 件の実測で 10.3ms → 0.5ms）。
    var nativeBackedFileURL: URL {
        var path = path
        guard !path.isContiguousUTF8 else { return self }
        path.makeContiguousUTF8()
        return URL(fileURLWithPath: path, isDirectory: hasDirectoryPath)
    }
}
