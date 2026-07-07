import Foundation

/// cmd+o のファイル選択パネルの初期ディレクトリを決める純粋ロジック。
/// ウィンドウごとに記憶された最後のディレクトリがあればそれを、
/// 無ければ（ウィンドウ未オープン含む）ホームディレクトリを使う。
enum OpenPanelDirectoryResolver {
    static func resolve(lastOpenDirectory: URL?, homeDirectory: URL) -> URL {
        lastOpenDirectory ?? homeDirectory
    }
}
