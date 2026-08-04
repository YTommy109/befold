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

    /// 一覧構築ロジックの同期版。本番の経路は非同期版(listEntriesAsync)のみを使うため、
    /// ここは並べ替え・隠しファイル・親移動エントリの規則を直接検証するテスト用の入口。
    /// - Parameter home: 親移動エントリを許可する上限(ホームディレクトリ)。
    ///   既定は実ユーザーのホーム。テストは一時ディレクトリを渡して実ホームの
    ///   内容に依存せずに親移動エントリの規則を検証する。
    static func listEntries(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false,
        home: URL = defaultHome
    ) -> [FileListEntry] {
        buildEntries(
            in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles, home: home
        )
    }

    /// listEntries と同一ロジックを、呼び出し元アクターを離れて実行する版。
    /// nonisolated async のため、ウィンドウ生成直後の初期一覧・windowDidBecomeKey・
    /// navigateToFolder のいずれの経路でも FileManager 列挙がメインスレッドを塞がない
    /// (ViewerLoadPipeline.load と同じパターン)。サイドバーの一覧取得はこの 1 本に揃えている。
    static func listEntriesAsync(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool = false
    ) async -> [FileListEntry] {
        buildEntries(
            in: directory, sortOrder: sortOrder, showHiddenFiles: showHiddenFiles, home: defaultHome
        )
    }

    private static func buildEntries(
        in directory: URL, sortOrder: SortOrder, showHiddenFiles: Bool, home: URL
    ) -> [FileListEntry] {
        let (folders, files) = sortedContents(in: directory, showHiddenFiles: showHiddenFiles)

        var entries: [FileListEntry] = []

        let parent = directory.deletingLastPathComponent()
        if isWithinHome(parent, home: home) {
            entries.append(FileListEntry(url: parent, kind: .parentNavigation))
        }

        let folderEntries = folders.map {
            FileListEntry(url: $0, kind: .folder, containsSupportedFile: containsSupportedFile(in: $0))
        }
        let fileEntries = files.map { FileListEntry(url: $0, kind: .file) }

        switch sortOrder {
        case .foldersFirst:
            entries += folderEntries
            entries += fileEntries
        case .alphabetical:
            entries += [FileListEntry].mergedByFileName(
                folderEntries, fileEntries, name: \.url.lastPathComponent
            )
        }

        return entries
    }

    /// ディレクトリ直下の全エントリ(フォルダ+ファイル混在、隠しファイル含む)を、
    /// ファイル名の localizedStandardCompare 昇順で 1 本のリストにして返す。
    /// Quick Open のパスモードは隠しファイルの出し分けを呼び出し側(入力の断片)で
    /// 決めるため、ここではフィルタせず全件を返す。列挙・ソートの単一情報源に寄せ、
    /// 呼び出し側が FileManager を直接叩いて未定義順の結果を得るのを防ぐ。
    static func allEntriesSorted(in directory: URL, fileReader: any FileReading = Self.fileReader) -> [URL] {
        let (folders, files) = sortedContents(in: directory, showHiddenFiles: true, fileReader: fileReader)
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
    ) -> (folders: [URL], files: [URL]) {
        DirectoryEnumeration.sortedContents(
            in: directory, showHiddenFiles: showHiddenFiles, fileReader: fileReader
        )
    }
}
