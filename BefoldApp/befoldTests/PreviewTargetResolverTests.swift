@testable import befold
import Foundation
import Testing

@Suite
struct PreviewTargetResolverTests {
    private let currentDirectory = URL(fileURLWithPath: "/tmp/PreviewTargetResolverTests")

    /// 本番(FileListModel)と同じ渡し方で解決する。選択の正規化キーは選択の書き込み時に
    /// 採るのが本番の作法なので、テストでもここで 1 度だけ採る。
    private func resolve(
        selection: FileListEntry.ID?,
        entries: [FileListEntry],
        currentDirectory: URL? = nil,
        hasLoadedEntries: Bool = true
    ) -> PreviewTarget {
        PreviewTargetResolver.resolve(
            selection: selection,
            selectionPathKey: selection?.normalizedPathKey,
            entryIndex: FileListEntryIndex(entries: entries),
            currentDirectory: currentDirectory ?? self.currentDirectory,
            hasLoadedEntries: hasLoadedEntries
        )
    }

    @Test("選択が nil のときは現在のディレクトリの一覧を対象にする")
    func nilSelectionResolvesToCurrentDirectory() {
        #expect(resolve(selection: nil, entries: []) == .folder(currentDirectory))
    }

    @Test("選択がファイルのときはファイル表示を対象にする")
    func fileSelectionResolvesToFile() {
        let file = FileListEntry(url: currentDirectory.appendingPathComponent("a.mmd"), kind: .file)
        #expect(resolve(selection: file.id, entries: [file]) == .file)
    }

    @Test("選択がフォルダーのときはそのフォルダーの一覧を対象にする")
    func folderSelectionResolvesToThatFolder() {
        let folder = FileListEntry(url: currentDirectory.appendingPathComponent("sub"), kind: .folder)
        #expect(resolve(selection: folder.id, entries: [folder]) == .folder(folder.url))
    }

    @Test("選択が一覧に存在しない(古い状態)ときは現在のディレクトリの一覧を対象にする")
    func staleSelectionFallsBackToCurrentDirectory() {
        let target = resolve(
            selection: currentDirectory.appendingPathComponent("gone.mmd"), entries: []
        )
        #expect(target == .folder(currentDirectory))
    }

    @Test("folderURL はフォルダー表示のときだけ対象ディレクトリを返す")
    func folderURLIsOnlySetForFolderTarget() {
        #expect(PreviewTarget.folder(currentDirectory).folderURL == currentDirectory)
        #expect(PreviewTarget.file.folderURL == nil)
        #expect(PreviewTarget.undetermined.folderURL == nil)
    }

    @Test("一覧が届く前に選択が一覧に無いのは「未確定」であってフォルダー表示ではない")
    func selectionBeforeFirstListingIsUndetermined() {
        let target = resolve(
            selection: currentDirectory.appendingPathComponent("opening.mmd"),
            entries: [],
            hasLoadedEntries: false
        )
        #expect(target == .undetermined)
    }

    @Test("一覧が届いた後に選択が見つからなければ、従来どおり現在ディレクトリの一覧へ落とす")
    func staleSelectionAfterListingFallsBackToFolder() {
        let target = resolve(
            selection: currentDirectory.appendingPathComponent("gone.mmd"),
            entries: [FileListEntry(url: currentDirectory.appendingPathComponent("other.mmd"), kind: .file)]
        )
        #expect(target == .folder(currentDirectory))
    }

    @Test("同じファイルを指す別表記(/private 付き・無し)で選択されていても、その行に一致する")
    func matchesSelectionThroughAlternatePathSpelling() throws {
        // macOS では /var・/tmp が /private 配下への入り口になっており、同じファイルが
        // 2 通りの綴りを持つ。CLI や Finder から渡る URL は一覧側(FileManager 由来)と
        // 別表記になりうるため、文字列としては一致しない。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewTargetResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("note.md")
        try Data().write(to: file)

        let alternate = file.path.hasPrefix("/private")
            ? String(file.path.dropFirst("/private".count))
            : "/private" + file.path
        let selection = URL(fileURLWithPath: alternate)
        try #require(FileManager.default.fileExists(atPath: alternate))
        let entry = FileListEntry(url: file, kind: .file)
        try #require(entry.url != selection)

        let target = resolve(selection: selection, entries: [entry], currentDirectory: directory)
        #expect(target == .file)
    }

    @Test("選択が nil なら、一覧の有無にかかわらず現在ディレクトリの一覧を出す(navigateToFolder の指示)")
    func clearedSelectionAlwaysShowsCurrentDirectory() {
        for hasLoadedEntries in [true, false] {
            let target = resolve(selection: nil, entries: [], hasLoadedEntries: hasLoadedEntries)
            #expect(target == .folder(currentDirectory))
        }
    }

    @Test("解決はファイルシステムを読まない(渡された値だけで決まる)")
    func resolutionDoesNotDependOnDiskState() throws {
        // 一覧の行が指す実体を、解決の前後で作り替えても答えは変わらない。
        // 解決のたびに resolvingSymlinksInPath を呼んでいた頃は、選択が
        // シンボリックリンク経由だと同じ入力から別の答えが出ることがあった(TASK-278)。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewTargetResolverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = directory.appendingPathComponent("real.md")
        try Data().write(to: real)
        let link = directory.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let entry = FileListEntry(url: real, kind: .file)
        let index = FileListEntryIndex(entries: [entry])
        let selectionPathKey = link.normalizedPathKey
        let resolveLink = {
            PreviewTargetResolver.resolve(
                selection: link,
                selectionPathKey: selectionPathKey,
                entryIndex: index,
                currentDirectory: directory
            )
        }
        try #require(resolveLink() == .file)

        // リンク先を一覧に無いファイルへ張り替える。ディスクを読んでいれば答えが変わる。
        let other = directory.appendingPathComponent("other.md")
        try Data().write(to: other)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
        try #require(link.normalizedPathKey != selectionPathKey)

        #expect(resolveLink() == .file)
    }
}
