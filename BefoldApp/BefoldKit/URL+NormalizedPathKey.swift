import Foundation

public extension URL {
    /// UserDefaults やウィンドウ管理の辞書キーに使う、正規化済みのパス文字列。
    /// シンボリックリンクを解決した絶対パスに揃えることで、同一ファイルを指す
    /// 別表記の URL（シンボリックリンク経由・相対パス等）を同じキーに集約する。
    var normalizedPathKey: String {
        resolvingSymlinksInPath().path
    }

    /// パスのバイト列は変えずに、文字列の裏打ちだけを native な連続 UTF-8 に揃えた同値の file URL。
    ///
    /// FileManager 由来の URL はパスが NSString 裏打ちで、URL の Hashable が
    /// 1 文字ずつ ObjC を呼ぶ Unicode 正規化経路（`-[__NSCFString characterAtIndex:]`）に
    /// 落ちる。SwiftUI の ForEach は行 ID を辞書キーにするたびにこれを走らせるため、
    /// 300 件規模の一覧でメインスレッドが詰まる（344 件の実測で 11.3ms → 0.3ms）。
    ///
    /// 作り直しはファイルシステム表現（ディスク上のバイト列そのもの）を通す。
    /// `URL(fileURLWithPath:)` はパスを再解釈するため精密合成（NFC）の名前を NFD へ
    /// 分解してしまい、正規化に敏感なボリューム（SMB/NFS/exFAT）上のファイルを
    /// 開けなくなる（344 件の実測でコストは 0.7ms、`URL(string:)` 経由の 2.9ms より安い）。
    ///
    /// file URL でない場合は何もせず自身を返す（scheme や query を書き換えないため）。
    var nativeBackedFileURL: URL {
        guard isFileURL, !path.isContiguousUTF8 else { return self }
        return withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else { return self }
            return URL(
                fileURLWithFileSystemRepresentation: pointer,
                isDirectory: hasDirectoryPath,
                relativeTo: nil
            )
        }
    }
}
