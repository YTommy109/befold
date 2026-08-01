import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import SwiftUI

/// テストで content ペイン(実 WKWebView)の代わりに使う空ビュー。
/// MockedViewerWindowManager / ViewerWindowControllerFixture の双方から使う。
@MainActor
func placeholderViewerContent() -> AnyView {
    AnyView(Color.clear)
}

/// ViewerWindowController を実 WKWebView 無しで組み立てるテスト用フィクスチャ。
/// 既定は InMemoryFileReader + MockFileWatcher(実 FS を踏まない)。
/// 実 FS の列挙・rename を検証する Integration は realFileSystem: true を渡す
/// (その場合 store は既定生成 = 実 FileWatcher + DefaultFileReader)。
@MainActor
struct ViewerWindowControllerFixture {
    let defaults: UserDefaults
    let zoomStore: ZoomStore
    let sourceModeStore: SourceModeStore
    let perFileState: PerFileStateStore
    let bookmarkStore: BookmarkStore
    let controller: ViewerWindowController

    init(
        file: URL,
        extraFiles: [URL] = [],
        contents: String = "graph TD;",
        realFileSystem: Bool = false,
        prefix: String = "ViewerWindowControllerFixture",
        defaults: UserDefaults? = nil,
        zoomStore: ZoomStore? = nil,
        sourceModeStore: SourceModeStore? = nil,
        bookmarkStore: BookmarkStore? = nil,
        hiddenFilesPreference: HiddenFilesPreference? = nil,
        initialFrameDescriptor: String? = nil,
        initialSortOrder: befold.SortOrder = .foldersFirst,
        showLineNumbersOverride: Bool? = nil,
        sourceModeOverride: Bool? = nil,
        openFileElsewhere: @escaping (URL, OpenDisposition, NSWindow?) -> Void = { _, _, _ in },
        externalOpener: @escaping (URL) -> Void = { _ in }
    ) {
        let defaults = defaults ?? makeIsolatedDefaults(prefix: prefix)
        let zoomStore = zoomStore ?? ZoomStore(defaults: defaults)
        let sourceModeStore = sourceModeStore ?? SourceModeStore(defaults: defaults)
        let perFileState = PerFileStateStore(
            zoom: zoomStore,
            sourceMode: sourceModeStore,
            scrollPosition: ScrollPositionStore(defaults: defaults),
            sidebar: SidebarStateStore(defaults: defaults),
            windowFrame: WindowFrameStore(defaults: defaults)
        )
        let bookmarkStore = bookmarkStore ?? BookmarkStore(defaults: defaults)
        self.defaults = defaults
        self.zoomStore = zoomStore
        self.sourceModeStore = sourceModeStore
        self.perFileState = perFileState
        self.bookmarkStore = bookmarkStore

        let store: ViewerStore?
        if realFileSystem {
            store = nil
        } else {
            var dict: [String: String] = [:]
            for url in [file] + extraFiles {
                dict[url.path] = contents
            }
            store = ViewerStore(
                watcherFactory: { _, _, _, _ in MockFileWatcher() },
                fileReader: InMemoryFileReader(files: dict),
                defaults: defaults
            )
        }

        controller = ViewerWindowController(
            fileURL: file,
            defaults: defaults,
            hiddenFilesPreference: hiddenFilesPreference ?? HiddenFilesPreference(defaults: defaults),
            perFileState: perFileState,
            bookmarkStore: bookmarkStore,
            initialFrameDescriptor: initialFrameDescriptor,
            initialSortOrder: initialSortOrder,
            showLineNumbersOverride: showLineNumbersOverride,
            sourceModeOverride: sourceModeOverride,
            store: store,
            makeContentView: placeholderViewerContent,
            openFileElsewhere: openFileElsewhere,
            externalOpener: externalOpener
        )
    }

    /// controller.close() の別名。テストは defer { fixture.close() } を置く。
    func close() {
        controller.close()
    }
}
