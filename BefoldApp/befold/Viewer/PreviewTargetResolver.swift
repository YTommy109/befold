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
///
/// 引数だけから結果が決まる(ファイルシステムを読まない)ことが、この型の要件である。
/// 選択の正規化パスキーは呼び出し側が選択の書き込み時に採った値を渡す。ここで
/// `resolvingSymlinksInPath` を呼ぶと、結果がディスクの状態に依存して読み出しのたびに
/// 変わりうるため、呼び出し側は結果を持ち回れなくなる(TASK-278)。
enum PreviewTargetResolver {
    /// - Parameters:
    ///   - selectionPathKey: 選択の `normalizedPathKey`。`selection` が nil なら使わない。
    ///   - entryIndex: 一覧の索引。選択に対応する行を O(1) で引く。
    ///   - hasLoadedEntries: 一覧が一度でも反映されたか。選択が一覧に見つからない
    ///     ときの意味がこれで変わる。反映済みなら「選択が古い(削除・移動)」ので現在ディレクトリの
    ///     一覧へ落とすのが正しく、未反映なら「まだ分からない」であって、フォルダー提示ではない。
    ///   - isListingCurrent: 手元の一覧が `currentDirectory` のものか(= 取り直しが
    ///     終わっているか)。移動直後は前のディレクトリの行が残っているため、選択が
    ///     見つからないのは「選択が古い」ではなく「一覧がまだ追いついていない」を意味する。
    ///     これを区別しないと、切替直後の一瞬(取り直しが着地しなければ永続的に)
    ///     フォルダー提示へ落ちてファイル一覧が本文に重なる(TASK-445)。
    static func resolve(
        selection: FileListEntry.ID?,
        selectionPathKey: String?,
        entryIndex: FileListEntryIndex,
        currentDirectory: URL,
        hasLoadedEntries: Bool = true,
        isListingCurrent: Bool = true
    ) -> PreviewTarget {
        // 選択を消してあるのは navigateToFolder の意図的な指示。現在ディレクトリの一覧を出す。
        guard let selection else { return .folder(currentDirectory) }
        let entry = entryIndex.entry(
            for: selection, selectionPathKey: selectionPathKey ?? selection.path
        )
        guard let entry else {
            return hasLoadedEntries && isListingCurrent ? .folder(currentDirectory) : .undetermined
        }
        return entry.kind == .file ? .file : .folder(entry.url)
    }
}
