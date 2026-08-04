@testable import befold
import Foundation
import Testing

@Suite
struct PreviewTargetResolverTests {
    private let currentDirectory = URL(fileURLWithPath: "/tmp/PreviewTargetResolverTests")

    @Test("選択が nil のときは現在のディレクトリの一覧を対象にする")
    func nilSelectionResolvesToCurrentDirectory() {
        let target = PreviewTargetResolver.resolve(
            selection: nil, entries: [], currentDirectory: currentDirectory
        )
        #expect(target == .folder(currentDirectory))
    }

    @Test("選択がファイルのときはファイル表示を対象にする")
    func fileSelectionResolvesToFile() {
        let file = FileListEntry(url: currentDirectory.appendingPathComponent("a.mmd"), kind: .file)
        let target = PreviewTargetResolver.resolve(
            selection: file.id, entries: [file], currentDirectory: currentDirectory
        )
        #expect(target == .file)
    }

    @Test("選択がフォルダーのときはそのフォルダーの一覧を対象にする")
    func folderSelectionResolvesToThatFolder() {
        let folder = FileListEntry(url: currentDirectory.appendingPathComponent("sub"), kind: .folder)
        let target = PreviewTargetResolver.resolve(
            selection: folder.id, entries: [folder], currentDirectory: currentDirectory
        )
        #expect(target == .folder(folder.url))
    }

    @Test("選択が親ナビゲーション行のときはその行の URL の一覧を対象にする")
    func parentNavigationSelectionResolvesToParentFolder() {
        let parent = FileListEntry(url: currentDirectory.deletingLastPathComponent(), kind: .parentNavigation)
        let target = PreviewTargetResolver.resolve(
            selection: parent.id, entries: [parent], currentDirectory: currentDirectory
        )
        #expect(target == .folder(parent.url))
    }

    @Test("選択が一覧に存在しない(古い状態)ときは現在のディレクトリの一覧を対象にする")
    func staleSelectionFallsBackToCurrentDirectory() {
        let target = PreviewTargetResolver.resolve(
            selection: currentDirectory.appendingPathComponent("gone.mmd"),
            entries: [],
            currentDirectory: currentDirectory
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
        let target = PreviewTargetResolver.resolve(
            selection: currentDirectory.appendingPathComponent("opening.mmd"),
            entries: [],
            currentDirectory: currentDirectory,
            hasLoadedEntries: false
        )
        #expect(target == .undetermined)
    }

    @Test("一覧が届いた後に選択が見つからなければ、従来どおり現在ディレクトリの一覧へ落とす")
    func staleSelectionAfterListingFallsBackToFolder() {
        let target = PreviewTargetResolver.resolve(
            selection: currentDirectory.appendingPathComponent("gone.mmd"),
            entries: [FileListEntry(url: currentDirectory.appendingPathComponent("other.mmd"), kind: .file)],
            currentDirectory: currentDirectory,
            hasLoadedEntries: true
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

        let target = PreviewTargetResolver.resolve(
            selection: selection,
            entries: [entry],
            currentDirectory: directory,
            hasLoadedEntries: true
        )
        #expect(target == .file)
    }

    @Test("選択が nil なら、一覧の有無にかかわらず現在ディレクトリの一覧を出す(navigateToFolder の指示)")
    func clearedSelectionAlwaysShowsCurrentDirectory() {
        for hasLoadedEntries in [true, false] {
            let target = PreviewTargetResolver.resolve(
                selection: nil,
                entries: [],
                currentDirectory: currentDirectory,
                hasLoadedEntries: hasLoadedEntries
            )
            #expect(target == .folder(currentDirectory))
        }
    }
}
