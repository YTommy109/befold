@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 開いている文書の URL(store.currentURL)は、出所を問わず native 裏打ちで保持する。
/// CLI 引数・セッション復元・Quick Open・フォルダー解決(resolveFileToOpen)と入口は多いが、
/// URL の保持先は pendingURL 一箇所なので、そこで揃っていることを見る(TASK-279)。
@Suite
@MainActor
struct ViewerStoreURLBackingTests {
    /// NSString 裏打ちの URL は FileManager の列挙からしか得られないため、実ファイルを使う。
    /// 合成した URL(URL(fileURLWithPath:))は初めから連続 UTF-8 で、判定にならない。
    private func listedFile(named name: String, in directory: TempDir) throws -> URL {
        _ = try directory.file(named: name, contents: "graph TD; A-->B")
        let listed = try FileManager.default.contentsOfDirectory(
            at: directory.url, includingPropertiesForKeys: nil
        )
        return try #require(listed.first { $0.lastPathComponent == name })
    }

    private func makeStore(onRenameBox: LockedBox<(@MainActor @Sendable (URL) -> Void)?>) -> ViewerStore {
        ViewerStore(
            watcherFactory: { _, _, _, onRename in
                onRenameBox.set(onRename)
                return MockFileWatcher()
            },
            defaults: makeIsolatedDefaults(prefix: "ViewerStoreURLBackingTests")
        )
    }

    @Test("FileManager 由来の URL で開いても、保持する URL は native 裏打ちに揃う")
    func openFileNormalizesBacking() throws {
        let directory = try TempDir(prefix: "viewer-store-backing")
        defer { withExtendedLifetime(directory) {} }
        let source = try listedFile(named: "日本語ファイル.mmd", in: directory)

        let store = makeStore(onRenameBox: LockedBox(nil))
        store.openFile(source)

        let backing = try URLBackingSupport.observed()
        let current = try #require(store.currentURL)
        #expect(current.path.isContiguousUTF8 == backing.rebuiltPathIsContiguousUTF8)
        // 裏打ちだけを差し替え、指すファイルは変えない。
        #expect(current == source)
        store.close()
    }

    @Test("監視が検知したリネーム後の URL も native 裏打ちに揃う")
    func renameNormalizesBacking() throws {
        let directory = try TempDir(prefix: "viewer-store-backing")
        defer { withExtendedLifetime(directory) {} }
        let source = try listedFile(named: "日本語ファイル.mmd", in: directory)

        let onRenameBox = LockedBox<(@MainActor @Sendable (URL) -> Void)?>(nil)
        let store = makeStore(onRenameBox: onRenameBox)
        store.openFile(source)

        let renamed = try listedFile(named: "改名後のファイル.mmd", in: directory)
        let onRename = try #require(onRenameBox.get())
        onRename(renamed)

        let backing = try URLBackingSupport.observed()
        let current = try #require(store.currentURL)
        #expect(current.path.isContiguousUTF8 == backing.rebuiltPathIsContiguousUTF8)
        #expect(current == renamed)
        store.close()
    }
}
