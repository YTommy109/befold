import BefoldKit
import Foundation

/// サイドバーのヘッダーに出す「上位フォルダーへ移動する」メニューの中身を決める。
///
/// 上へ移動する経路(ヘッダーのパスポップアップ・⌘↑・delete)が参照する
/// **ホーム上限の単一の真実の源**。かつては一覧の先頭に置いた `..` 行がこの役目を
/// 担っており、行の有無がそのまま「上へ行けるか」を表していた(TASK-475 で廃止)。
///
/// `parent(of:home:)` を `ancestors(of:home:).first` として定義しているのが要点。
/// メニューと ⌘↑ で上限判定を別々に書くと、片方だけ直したときにもう片方が
/// ホームの外へ出られる形が残る。判定を 2 つ持たないこと。
enum SidebarPathMenu {
    /// `directory` から上位の祖先を、近い親から順にホームまで並べる。
    ///
    /// ホーム自身・ホーム外では空になる(上へ出す先が無い)。呼び出し側は空を
    /// 「メニューを出さない」に対応させる。
    ///
    /// - Parameter home: 移動の上限。テストは一時ディレクトリを渡して実ユーザーの
    ///   ホームに依存せずに規則を検証する。**既定値を持たせない**のは、渡し忘れが
    ///   コンパイルエラーにならず静かに実ホームを見に行くのを防ぐため。
    static func ancestors(of directory: URL, home: URL) -> [URL] {
        var result: [URL] = []
        var current = directory.standardizedFileURL
        while true {
            let parent = current.deletingLastPathComponent()
            // ルート("/")では deletingLastPathComponent が自分自身を返すため、
            // ホームがルートのときでも止まるようにしておく。
            guard parent.normalizedPathKey != current.normalizedPathKey else { break }
            guard DirectoryLister.isWithinHome(parent, home: home) else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    /// 1 つ上のフォルダー。ホーム自身・ホーム外では nil。
    ///
    /// `ancestors` の先頭そのもの。⌘↑ と delete の行き先はここから取る。
    static func parent(of directory: URL, home: URL) -> URL? {
        ancestors(of: directory, home: home).first
    }
}
