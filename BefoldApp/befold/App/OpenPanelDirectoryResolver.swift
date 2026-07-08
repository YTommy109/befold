import Foundation

/// cmd+o のファイル選択パネルの初期ディレクトリを決める純粋ロジック。
/// キーウィンドウが表示中のファイルのディレクトリがあればそれを、
/// 無ければ（ウィンドウ未オープン含む）ホームディレクトリを使う。
enum OpenPanelDirectoryResolver {
    static func resolve(currentFileDirectory: URL?, homeDirectory: URL) -> URL {
        currentFileDirectory ?? homeDirectory
    }
}
