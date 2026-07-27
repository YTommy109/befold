import Foundation

/// 「名前がドット始まりなら隠しファイル」という、Quick Open の走査・索引・パスモードで
/// 共有する隠し判定の単一情報源。
///
/// サイドバー系(`DirectoryLister` / `SupportedFileResolver`)が使う FileManager の
/// `.skipsHiddenFiles` は、ドット始まりに加えて chflags の hidden フラグ(例: `~/Library`)も
/// 隠す。Quick Open の候補には git 追跡ファイル索引由来の「文字列だけ」の候補が混ざり、
/// hidden フラグを URL から stat しても走査と索引でフィルタの意味がずれてしまう。
/// そこで Quick Open 側は「名前のドット始まり」だけで一貫して判定し、走査・索引・パスモードの
/// フィルタを同じ意味に揃える。Finder の hidden フラグ込みの定義を **あえて使わない** のはこのため。
public enum HiddenFileRule {
    /// パス構成要素 1 つ(ファイル名・ディレクトリ名)がドット始まり(= 隠し)か。
    public static func isHidden(component name: some StringProtocol) -> Bool {
        name.hasPrefix(".")
    }

    /// 相対パスに、ドット始まりの構成要素が 1 つでも含まれるか。
    /// 基準ディレクトリ自体がドット始まりでも(例: `~/.config` を開いた場合)配下が
    /// 丸ごと隠し扱いにならないよう、判定は相対部分だけを見る前提で呼ぶこと。
    public static func containsHiddenComponent(inRelativePath relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { isHidden(component: $0) }
    }
}
