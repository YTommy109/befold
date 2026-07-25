import AppKit
@testable import befold
import BefoldTestSupport
import Foundation

/// ViewerWindowManager を実 FS へ触れさせずに組み立てるテスト用フィクスチャ。
///
/// openViewer が生成する ViewerWindowController は既定では実 FileWatcher・実ファイル読込・
/// 実ディレクトリ列挙を踏むため、そのままでは Integration にせざるを得なかった。
/// ViewerWindowManager の makeStore / directoryLister シーム(TASK-116.13)へ
/// InMemoryFileReader + MockFileWatcher + 空の列挙を渡すことで、生成パイプラインごと unit 化する。
///
/// サイドバーの entries を検証するテストには使えない(列挙は常に空)。
/// 実列挙そのものが対象のテストは Integration に残すこと。
@MainActor
struct MockedViewerWindowManager {
    let defaults: UserDefaults
    let fileReader: InMemoryFileReader
    let sessionStore: SessionStore
    let recentDocumentsStore: RecentDocumentsStore
    let perFileState: PerFileStateStore
    let hiddenFilesPreference: HiddenFilesPreference
    let manager: ViewerWindowManager

    /// - Parameter files: 存在するものとして扱う URL。VWM の存在ガードと、
    ///   生成される ViewerStore の読込の双方が同じ InMemoryFileReader を共有する。
    init(files: [URL], prefix: String = "ViewerWindowManagerTests", contents: String = "graph TD;") {
        let defaults = makeIsolatedDefaults(prefix: prefix)
        let fileReader = InMemoryFileReader(
            files: Dictionary(uniqueKeysWithValues: files.map { ($0.path, contents) })
        )
        self.defaults = defaults
        self.fileReader = fileReader
        sessionStore = SessionStore(defaults: defaults)
        recentDocumentsStore = RecentDocumentsStore(defaults: defaults)
        perFileState = PerFileStateStore(defaults: defaults)
        hiddenFilesPreference = HiddenFilesPreference(defaults: defaults)
        manager = ViewerWindowManager(
            sessionStore: sessionStore,
            recentDocumentsStore: recentDocumentsStore,
            hiddenFilesPreference: hiddenFilesPreference,
            perFileState: perFileState,
            fileReader: fileReader,
            makeStore: { _ in
                ViewerStore(
                    watcherFactory: { _, _, _ in MockFileWatcher() },
                    fileReader: fileReader,
                    defaults: defaults
                )
            },
            directoryLister: { _, _, _ in [] }
        )
    }

    /// テスト終了時にウィンドウを閉じる。openViewer した全テストで呼ぶこと。
    func closeAll() {
        manager.controllers.values.forEach { $0.close() }
    }
}
