import Foundation

/// プレビューエリアが表示すべき対象。ファイルなら既存の ViewerWebView、
/// フォルダーなら FolderListingView(その URL 直下の一覧)を表示する。
enum PreviewTarget: Equatable {
    /// 一覧がまだ届いておらず、提示対象が確定していない(ウィンドウ生成直後)。
    /// 「選択を消してフォルダーを表示している」状態と区別するために独立した値を持つ。
    /// 両者を `.folder` に潰していた頃は、起動直後に一覧が届くまでのあいだ
    /// フォルダー提示と判定され、印刷・検索・ズームが誤って無効化されていた(ADR 0002)。
    case undetermined
    case file
    case folder(URL)

    /// フォルダー表示のときの対象ディレクトリ。ViewerContentView は
    /// ViewerWebView を常駐させたまま一覧を重ねるため、switch ではなくこの値で分岐する。
    /// 未確定のときは nil を返し、開こうとしているファイル側を提示する。
    var folderURL: URL? {
        guard case let .folder(url) = self else { return nil }
        return url
    }
}

/// サイドバーの選択状態からプレビュー対象を決める純粋ロジック。
/// FileListModel/SidebarNavigator の状態をそのまま参照し、独自の状態を持たない。
enum PreviewTargetResolver {
    /// - Parameter hasLoadedEntries: 一覧が一度でも反映されたか。選択が一覧に見つからない
    ///   ときの意味がこれで変わる。反映済みなら「選択が古い(削除・移動)」ので現在ディレクトリの
    ///   一覧へ落とすのが正しく、未反映なら「まだ分からない」であって、フォルダー提示ではない。
    static func resolve(
        selection: FileListEntry.ID?,
        entries: [FileListEntry],
        currentDirectory: URL,
        hasLoadedEntries: Bool = true
    ) -> PreviewTarget {
        // 選択を消してあるのは navigateToFolder の意図的な指示。現在ディレクトリの一覧を出す。
        guard let selection else { return .folder(currentDirectory) }
        guard let entry = matchingEntry(for: selection, in: entries) else {
            return hasLoadedEntries ? .folder(currentDirectory) : .undetermined
        }
        return entry.kind == .file ? .file : .folder(entry.url)
    }

    /// 選択に対応する行。まず ID(URL)で照合し、外れたときだけ正規化パスキーで照合し直す。
    ///
    /// シンボリックリンク経由のパス(`/tmp/...` と `/private/tmp/...` など)で開かれると、
    /// 一覧の URL と選択の URL は同じファイルを指しながら文字列としては一致しない。
    /// 一方 SidebarNavigator の選択維持判定は正規化キーで比較して「選択は有効」と結論するため、
    /// 両者が食い違うと、**選択は保持されたまま提示対象だけがフォルダーへ落ちる**
    /// (文書を開いたのに一覧が出る)。照合の基準をここで揃える(ADR 0002)。
    ///
    /// 正規化は syscall を伴うため、一致する通常の経路では走らせない。
    private static func matchingEntry(
        for selection: FileListEntry.ID, in entries: [FileListEntry]
    ) -> FileListEntry? {
        if let entry = entries.first(where: { $0.id == selection }) { return entry }
        let selectionKey = selection.normalizedPathKey
        return entries.first { $0.pathKey == selectionKey }
    }
}
