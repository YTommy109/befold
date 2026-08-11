import BefoldKit
import Foundation

enum DirectoryLister {
    /// 存在確認・ディレクトリ判定の単一の実装元。ObjCBool の取り回しは
    /// DefaultFileReader に集約し、ここではそこへ委譲する。
    private static let fileReader: any FileReading = DefaultFileReader()

    /// 親移動エントリを許可する上限(ホームディレクトリ)の本番既定値。
    /// FileReading は「存在・種別・内容の読み取り」に責務を絞っており、
    /// ホームの所在はそこに属さないため、独立した既定値として持つ。
    static var defaultHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// 一覧構築ロジックの同期版。本番の経路は非同期版(listingAsync)のみを使うため、
    /// ここは並べ替え・隠しファイル・親移動エントリの規則を直接検証するテスト用の入口。
    /// - Parameter home: 親移動エントリを許可する上限(ホームディレクトリ)。
    ///   既定は実ユーザーのホーム。テストは一時ディレクトリを渡して実ホームの
    ///   内容に依存せずに親移動エントリの規則を検証する。
    static func listing(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false,
        home: URL = defaultHome
    ) -> DirectoryListing {
        buildListing(
            in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles, home: home
        )
    }

    /// listing と同一ロジックを、呼び出し元アクターを離れて実行する版。
    /// nonisolated async のため、ウィンドウ生成直後の初期一覧・windowDidBecomeKey・
    /// navigateToFolder のいずれの経路でも FileManager 列挙がメインスレッドを塞がない
    /// (ViewerLoadPipeline.load と同じパターン)。サイドバーの一覧取得はこの 1 本に揃えている。
    static func listingAsync(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false
    ) async -> DirectoryListing {
        buildListing(
            in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles, home: defaultHome
        )
    }

    /// 直下の行だけを、呼び出し元アクターを離れて列挙する。ツリー展開した
    /// フォルダの子リストはこちらで取る。
    ///
    /// `listingAsync` を使ってはならない。あちらは親移動行を別に持つ
    /// **ルート一覧の材料**なので、展開したフォルダごとに `..` 行が生えてしまう。
    static func childEntriesAsync(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false
    ) async -> [FileListEntry]? {
        childEntries(in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles)
    }

    /// 開いているファイルが、そのファイルの入っているフォルダーの一覧に無ければ末尾へ足す。
    ///
    /// allExtensions に含まれない拡張子(plaintext フォールバック)のファイルは列挙に載らない
    /// ため、そのままだと「いま開いている文書」が一覧から消える。サイドバー
    /// (SidebarNavigator)とプレビューのフォルダー一覧(FolderListingView)の **両方** が
    /// ここを通す。片側だけに適用していた頃は、同じフォルダーでもカレントディレクトリとして
    /// 見たときにだけこの行が現れ、親から選んで見たときには消えていた(TASK-295)。
    ///
    /// 追記先が **フラット化後の配列の末尾** であることは、ツリー展開が入っても正しい。
    /// 深さ優先で畳んだ配列の末尾は「最後のルート直下行とその配下すべての直後」であり、
    /// そこは配下を持たない新しいルート直下行が入る位置そのものだから。足す行の
    /// `depth` は 0(既定)のままでよい。
    static func appendingOpenFile(
        _ openFile: URL?, to entries: [FileListEntry], in directory: URL
    ) -> [FileListEntry] {
        guard let openFile else { return entries }
        let openFileParent = openFile.deletingLastPathComponent()
        // まず解決なしの生パスで比較する。両者が文字列として一致するなら、同じ変換
        // (resolvingSymlinksInPath)を通しても結果は一致するため、シンボリックリンク解決の
        // ファイルシステム呼び出し(normalizedPathKey)を省ける。このビューはこの関数を
        // body 評価のたびに呼ぶため、一致して抜けられる通常時(directory の中身をそのまま
        // 見ている間)は毎回 syscall 無しで済む。生パスが食い違う場合だけ、シンボリックリンク
        // 越しに同じディレクトリを指している可能性があるので、正規化して確定させる。
        let sameDirectory = openFileParent.path == directory.path
            || openFileParent.normalizedPathKey == directory.normalizedPathKey
        guard sameDirectory else { return entries }
        // 重複判定も同じ理由で、まず生パスの一致を試してから正規化キーに落ちる。
        guard !entries.contains(where: { $0.url.path == openFile.path }) else { return entries }
        let key = openFile.normalizedPathKey
        guard !entries.contains(where: { $0.pathKey == key }) else { return entries }
        return entries + [FileListEntry(url: openFile, kind: .file)]
    }

    /// 列挙結果を **行に畳む前の材料** として組む。畳むのは `DirectoryListing.rows` の
    /// 1 箇所だけで、ここは行を作らない。
    ///
    /// ルートの列挙失敗はここで空へ畳む。ルート一覧には失敗を出す先が無く(開閉三角は
    /// 子フォルダの行にしか無い)、ここを Optional にすると
    /// 「開いている文書は必ず一覧に含める」(appendingOpenFile)も通らなくなる。
    /// ルート列挙失敗の表示は TASK-410 で扱う。
    private static func buildListing(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool, home: URL
    ) -> DirectoryListing {
        DirectoryListing(
            parentEntry: parentNavigationEntry(for: directory, home: home),
            rootChildren: childEntries(
                in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles
            ) ?? []
        )
    }

    /// 上位フォルダーへの移動行。ホームの外へは出さないため、その外なら nil。
    /// 一覧の項目ではなく移動手段なので、並べ替えの対象に含めず常に先頭へ置く
    /// (`.alphabetical` のマージへ混ぜると `..` がファイル名としてソートされる)。
    static func parentNavigationEntry(for directory: URL, home: URL) -> FileListEntry? {
        let parent = directory.deletingLastPathComponent()
        guard isWithinHome(parent, home: home) else { return nil }
        return FileListEntry(url: parent, kind: .parentNavigation)
    }

    /// `directory` 直下の行(親移動行を含まない)。並び順の規則はここが単一の実装元で、
    /// ツリー展開時は展開したフォルダごとにこの関数の結果が材料になる。
    /// 列挙に失敗した場合は **nil**(空のフォルダの `[]` と区別する)。ツリー展開は
    /// この区別を使って「読めなかったフォルダ」を空フォルダとして表示しない(TASK-404)。
    static func childEntries(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool
    ) -> [FileListEntry]? {
        guard let (folders, files) = sortedContents(in: directory, showHiddenFiles: showHiddenFiles) else {
            return nil
        }
        let folderEntries = folders.map {
            FileListEntry(url: $0, kind: .folder, containsSupportedFile: containsSupportedFile(in: $0))
        }
        let fileEntries = files.map { FileListEntry(url: $0, kind: .file) }

        switch sortOrder {
        case .foldersFirst:
            return folderEntries + fileEntries
        case .alphabetical:
            return [FileListEntry].mergedByFileName(
                folderEntries, fileEntries, name: \.url.lastPathComponent
            )
        }
    }

    /// ディレクトリ直下の全エントリ(フォルダ+ファイル混在、隠しファイル含む)を、
    /// ファイル名の localizedStandardCompare 昇順で 1 本のリストにして返す。
    /// Quick Open のパスモードは隠しファイルの出し分けを呼び出し側(入力の断片)で
    /// 決めるため、ここではフィルタせず全件を返す。列挙・ソートの単一情報源に寄せ、
    /// 呼び出し側が FileManager を直接叩いて未定義順の結果を得るのを防ぐ。
    static func allEntriesSorted(in directory: URL, fileReader: any FileReading = Self.fileReader) -> [URL] {
        // Quick Open は候補が 0 件のときに「該当なし」と出すだけで、列挙失敗を
        // 別の案内に分ける口を持たない。ここでは空へ畳む(区別の導入は TASK-410)。
        let (folders, files) = sortedContents(
            in: directory, showHiddenFiles: true, fileReader: fileReader
        ) ?? ([], [])
        // Quick Open は候補 URL をそのまま行 ID・正規化キーとしてハッシュするため、
        // ここで native 裏打ちへ揃える(列挙側では揃えない。TASK-273)。
        return [URL].mergedByFileName(folders, files, name: \.lastPathComponent)
            .map(\.nativeBackedFileURL)
    }

    static func containsSupportedFile(in directory: URL) -> Bool {
        firstSupportedFile(in: directory) != nil
    }

    /// 先頭の対応形式ファイル。判定は BefoldKit.DirectoryEnumeration(単一の実装元)に委譲する。
    static func firstSupportedFile(in directory: URL, fileReader: any FileReading = Self.fileReader) -> URL? {
        DirectoryEnumeration.firstSupportedFile(in: directory, fileReader: fileReader)
    }

    /// 指定 URL がホームディレクトリ自身、またはその配下かどうかを判定する。
    /// symlink を解決した normalizedPathKey で比較し、パス表記の揺れを吸収する。
    /// 前方一致だけの兄弟パス(例: ホームが `/Users/xxx` のとき `/Users/xxx2`)を
    /// 誤って含めないよう、区切り文字 `/` を含めて比較する。
    /// - Parameter home: 比較の基準となるホームディレクトリ。既定は実ユーザーのホーム。
    ///   テストは一時ディレクトリを渡し、実ホームに依存せず判定規則だけを検証する。
    static func isWithinHome(_ url: URL, home: URL = defaultHome) -> Bool {
        let homeKey = home.normalizedPathKey
        let target = url.normalizedPathKey
        return target == homeKey || target.hasPrefix(homeKey + "/")
    }

    /// 指定パスが存在するファイル(ディレクトリでない)かどうかを判定する。
    static func isExistingFile(_ url: URL) -> Bool {
        fileReader.isExistingFile(at: url)
    }

    /// 指定パスが存在するかどうかを判定する(ディレクトリ含む)。
    static func fileExists(_ url: URL) -> Bool {
        fileReader.fileExists(at: url)
    }

    /// 指定パスが存在するディレクトリかどうかを判定する。
    static func isDirectory(_ url: URL) -> Bool {
        fileReader.isDirectory(at: url)
    }

    /// CLI シム経由のオープン用にパスを解決する。実体は BefoldKit.SupportedFileResolver
    /// (GUI・CLI 双方の単一の実装元)に委譲する。
    /// - Parameter fileReader: テスト用に差し替え可能。
    static func resolveFileToOpen(at url: URL, fileReader: any FileReading = Self.fileReader) -> URL? {
        SupportedFileResolver.resolveFileToOpen(at: url, fileReader: fileReader)
    }

    // MARK: - Private

    /// ディレクトリ内容の列挙・分類・ソートは BefoldKit.DirectoryEnumeration
    /// (単一の実装元)に委譲する。
    private static func sortedContents(
        in directory: URL, showHiddenFiles: Bool = false, fileReader: any FileReading = Self.fileReader
    ) -> (folders: [URL], files: [URL])? {
        DirectoryEnumeration.sortedContents(
            in: directory, showHiddenFiles: showHiddenFiles, fileReader: fileReader
        )
    }
}
