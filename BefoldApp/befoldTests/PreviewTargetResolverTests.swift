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
}
