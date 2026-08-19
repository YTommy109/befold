import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 新しい窓が、起点の窓の列挙結果を出発点として引き継ぐこと(TASK-532)。
///
/// 引き継ぎが無いと、同じフォルダのファイルを新規タブで開いたときサイドバーが必ず
/// 「空 → 列挙 → 描画」の 2 段階を通る。実測(修正前): 2 枚目の窓は生成直後に
/// `hasLoadedEntries == false` / 0 行で、列挙が着地して 4 行になった。しかもその 4 行は
/// 1 枚目とまったく同じだった——作り直す必要が無かったということ。
@Suite
@MainActor
struct SidebarListingSeedTests {
    private func makeDirectory() throws -> TempDir {
        let base = try makeHomeTempDir()
        for name in ["a.md", "b.md", "c.md", "d.md"] {
            try "# \(name)".write(
                to: base.url.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
        return base
    }

    private func makeController(
        file: URL, seed: SidebarListingSeed?, prefix: String
    ) -> ViewerWindowController {
        ViewerWindowControllerFixture(
            file: file, realFileSystem: true, prefix: prefix, initialListing: seed
        ).controller
    }

    @Test("同じフォルダの新しい窓は、空の一覧を経由せず一覧を持って始まる")
    func adoptedListingSkipsEmptyStage() async throws {
        let base = try makeDirectory()
        defer { withExtendedLifetime(base) {} }

        let first = makeController(
            file: base.url.appendingPathComponent("a.md"), seed: nil, prefix: "SeedTests1"
        )
        defer { first.close() }
        await first.sidebar.awaitSettled()
        let seed = SidebarListingSeed(
            directory: first.fileListModel.entriesDirectory,
            listing: first.sidebar.lastListing,
            sortOrder: first.fileListModel.sortOrder,
            showHiddenFiles: first.fileListModel.showHiddenFiles
        )

        let second = makeController(
            file: base.url.appendingPathComponent("b.md"), seed: seed, prefix: "SeedTests2"
        )
        defer { second.close() }

        // 生成直後、まだ自分では何も列挙していない時点で既に一覧を持っている。
        #expect(second.fileListModel.hasLoadedEntries)
        #expect(second.fileListModel.entries.map(\.url) == first.fileListModel.entries.map(\.url))

        // 直後に走る取り直しは同じ結果を返すので、行は変わらない。
        await second.sidebar.awaitSettled()
        #expect(second.fileListModel.entries.map(\.url) == first.fileListModel.entries.map(\.url))
    }

    /// 引き継ぎが無い場合の従来の振る舞い。これが「修正前の姿」で、上のテストと対になる。
    @Test("引き継がない窓は、従来どおり空の一覧から始まる")
    func withoutSeedStartsEmpty() async throws {
        let base = try makeDirectory()
        defer { withExtendedLifetime(base) {} }

        let controller = makeController(
            file: base.url.appendingPathComponent("a.md"), seed: nil, prefix: "SeedTests3"
        )
        defer { controller.close() }

        #expect(!controller.fileListModel.hasLoadedEntries)
        #expect(controller.fileListModel.entries.isEmpty)

        await controller.sidebar.awaitSettled()
        #expect(controller.fileListModel.hasLoadedEntries)
        #expect(!controller.fileListModel.entries.isEmpty)
    }

    /// 列挙の入力が食い違う窓へは引き継がない。素通しすると、取り直しが着地するまでの
    /// 間だけ「不可視ファイルが出ている一覧」が新しい窓に見える。
    @Test("並び順・不可視ファイルの設定が違えば引き継がない")
    func rejectsSeedWithDifferentListingInputs() throws {
        let base = try makeDirectory()
        defer { withExtendedLifetime(base) {} }
        let model = FileListModel(
            currentDirectory: base.url, entries: [], selection: nil
        )
        let seed = SidebarListingSeed(
            directory: base.url,
            listing: DirectoryListing(rootChildren: []),
            sortOrder: model.sortOrder,
            showHiddenFiles: !model.showHiddenFiles
        )

        #expect(!seed.canApply(to: model))
    }

    /// 列挙に失敗した結果は引き継がない。失敗は「読めなかった」という事実であり、
    /// 写すと新しい窓が自分では試していないのに失敗表示から始まる(TASK-410)。
    @Test("列挙に失敗した結果は引き継がない")
    func rejectsFailedListing() throws {
        let base = try makeDirectory()
        defer { withExtendedLifetime(base) {} }
        let model = FileListModel(currentDirectory: base.url, entries: [], selection: nil)
        let seed = SidebarListingSeed(
            directory: base.url,
            listing: DirectoryListing(rootChildren: [], didFailEnumeration: true),
            sortOrder: model.sortOrder,
            showHiddenFiles: model.showHiddenFiles
        )

        #expect(!seed.canApply(to: model))
    }

    /// 別フォルダの一覧は引き継がない。
    @Test("別のフォルダの一覧は引き継がない")
    func rejectsSeedFromDifferentDirectory() throws {
        let base = try makeDirectory()
        defer { withExtendedLifetime(base) {} }
        let model = FileListModel(currentDirectory: base.url, entries: [], selection: nil)
        let seed = SidebarListingSeed(
            directory: base.url.appendingPathComponent("elsewhere"),
            listing: DirectoryListing(rootChildren: []),
            sortOrder: model.sortOrder,
            showHiddenFiles: model.showHiddenFiles
        )

        #expect(!seed.canApply(to: model))
    }

    /// 配線の検証。上のテストはフィクスチャへ直接 seed を渡しており、`openViewer` が
    /// 起点ウィンドウから seed を組み立てて渡していることまでは測れない。
    /// ここが落ちたら、値型とコントローラは正しいのに配線だけ切れている状態。
    @Test("openViewer が起点ウィンドウの一覧を新しいタブへ引き継ぐ")
    func openViewerPassesSeedFromSourceWindow() async throws {
        let base = try makeDirectory()
        defer { withExtendedLifetime(base) {} }
        let first = base.url.appendingPathComponent("a.md")
        let second = base.url.appendingPathComponent("b.md")
        let fixture = MockedViewerWindowManager(
            files: [first, second], prefix: "SidebarListingSeedWiring"
        )
        defer { fixture.closeAll() }

        let firstController = try #require(fixture.manager.openViewer(for: first))
        await firstController.sidebar.awaitSettled()
        let firstWindow = fixture.manager.window(forPath: first.normalizedPathKey)

        let secondController = try #require(
            fixture.manager.openViewer(for: second, disposition: .newTab, relativeTo: firstWindow)
        )

        // 生成直後。まだ自分では列挙していない。
        #expect(secondController.fileListModel.hasLoadedEntries)
        #expect(
            secondController.fileListModel.entries.map(\.url)
                == firstController.fileListModel.entries.map(\.url)
        )
    }
}
