import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// 参照(ドキュメント内リンク)の解決そのものを検証する unit テスト。
/// 対象は、実在パスだけを解決済み絶対パスで返すこと、git 索引アクセスが
/// MainActor 上で行われないこと、表示時解決とクリック時解決が同じ入力に一致すること。
/// 解決結果をどう開くか(disposition の伝搬・外部 URL)は
/// ViewerWindowControllerReferenceOpenTests が受け持つ。
@Suite("ViewerWindowController の参照解決")
@MainActor
struct ViewerWindowControllerRefResolutionTests {
    @Test("resolveReferences は実在パスのみ解決済み絶対パスで返す")
    func resolveReferencesReturnsResolvedOnly() async {
        // 常に固定の追跡ファイル索引を返すフェイク。相対解決で見つからないパスの
        // git サフィックス一致フォールバックを検証するために使う。
        struct FakeGitIndex: GitFileIndexing {
            let tracked: URL
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                SuffixPathIndex(candidates: [tracked])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let tracked = URL(fileURLWithPath: "/mock/src/utils.swift")
        let controller = makeMockedViewerWindowController(primary: base, contents: "# doc")
        defer { controller.close() }
        // utils.swift は書かれた相対位置(/mock/docs/utils.swift)には存在せず、
        // 追跡ファイルの実体(/mock/src/utils.swift)だけが存在する状態にする。
        // git サフィックス一致でのみ解決でき、かつ一致先は実在するという経路。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc", tracked.path: "// utils"]),
            gitIndex: FakeGitIndex(tracked: tracked)
        )

        let map = await controller.resolveReferences(["utils.swift", "https://example.com", "nope.swift"])

        #expect(map == ["utils.swift": tracked.path])
    }

    /// 表示時解決はキャッシュ未命中時に `git ls-files` の subprocess を待つ。
    /// MainActor 上で走ると大きなリポジトリで UI が数百 ms 止まるため、
    /// git 索引に触れるのがメインスレッド外であることを索引側から観測して固定する。
    @Test("表示時解決の git 索引アクセスはメインスレッド上で行われない")
    func resolveReferencesTouchesGitIndexOffMainThread() async {
        // 呼ばれたスレッドを記録するだけのフェイク索引。
        struct ThreadRecordingGitIndex: GitFileIndexing {
            let wasMainThread: LockedBox<Bool?>
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                wasMainThread.set(Thread.isMainThread)
                return SuffixPathIndex(candidates: [])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let wasMainThread = LockedBox<Bool?>(nil)
        let controller = makeMockedViewerWindowController(
            primary: base, contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "ResolveOffMain")
        )
        defer { controller.close() }
        // 相対解決では見つからないパスを渡し、必ず git 索引フォールバックへ入らせる。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc"]),
            gitIndex: ThreadRecordingGitIndex(wasMainThread: wasMainThread)
        )

        _ = await controller.resolveReferences(["utils.swift"])

        #expect(wasMainThread.get() == false, "git 索引を MainActor 上で触っている")
    }

    /// クリック時解決(handleOpenReference)も表示時解決と同じく、キャッシュ未命中時は
    /// `git ls-files` の subprocess を待つ。resolveReferences と同じ方針で MainActor を
    /// 離して解決することを、git 索引側から観測して固定する(task-222 の回帰テスト)。
    @Test("クリック時解決の git 索引アクセスはメインスレッド上で行われない")
    func handleOpenReferenceTouchesGitIndexOffMainThread() async {
        struct ThreadRecordingGitIndex: GitFileIndexing {
            let wasMainThread: LockedBox<Bool?>
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                wasMainThread.set(Thread.isMainThread)
                return SuffixPathIndex(candidates: [])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let wasMainThread = LockedBox<Bool?>(nil)
        let controller = makeMockedViewerWindowController(
            primary: base, contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "OpenReferenceOffMain")
        )
        defer { controller.close() }
        // 相対解決では見つからないパスを渡し、必ず git 索引フォールバックへ入らせる。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc"]),
            gitIndex: ThreadRecordingGitIndex(wasMainThread: wasMainThread)
        )

        controller.handleOpenReference(href: "utils.swift", disposition: .currentTab)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(wasMainThread.get() == false, "git 索引を MainActor 上で触っている")
    }

    /// 表示時解決とクリック時解決が同じ入力に一致することを固定する。
    /// 「リンク化したものは必ずそのリンク先へ開ける」がこの機能の中心的な不変条件であり、
    /// 現状は同じ pathResolver を通ることで成立しているが、片方だけを変える将来の変更で
    /// 静かに壊れうるため、実際の 2 経路を突き合わせて押さえる。
    @Test("表示時にリンク化した参照は、クリック時も同じ URL へ解決される")
    func resolveReferencesAndOpenReferenceAgreeOnGitFallback() async {
        struct FakeGitIndex: GitFileIndexing {
            let tracked: URL
            func trackedFileIndex(forFileAt url: URL) -> SuffixPathIndex? {
                SuffixPathIndex(candidates: [tracked])
            }
        }
        let base = URL(fileURLWithPath: "/mock/docs/guide.md")
        let tracked = URL(fileURLWithPath: "/mock/src/utils.swift")
        var openedInNewWindow: [URL] = []
        let controller = makeMockedViewerWindowController(
            primary: base, contents: "# doc",
            defaults: makeIsolatedDefaults(prefix: "ResolveAgreement"),
            openFileElsewhere: { url, _, _ in openedInNewWindow.append(url) }
        )
        defer { controller.close() }
        // 相対解決では見つからず、git 追跡ファイルのサフィックス一致でのみ解決できる状態。
        controller.referenceCoordinator.resolver = TrackedPathResolver(
            fileReader: InMemoryFileReader(files: [base.path: "# doc", tracked.path: "// utils"]),
            gitIndex: FakeGitIndex(tracked: tracked)
        )

        let resolved = await controller.resolveReferences(["utils.swift"])["utils.swift"]
        // disposition: .newWindow でクリックすると、開く先の URL がそのまま観測できる。
        controller.handleOpenReference(href: "utils.swift", disposition: .newWindow)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value

        #expect(resolved == tracked.path)
        #expect(openedInNewWindow.map(\.path) == [tracked.path])
        // 表示時にリンク化しなかった参照は、クリックしても遷移しない(逆方向の一致)。
        let unresolved = await controller.resolveReferences(["nope.swift"])
        #expect(unresolved.isEmpty)
        controller.handleOpenReference(href: "nope.swift", disposition: .newWindow)
        await controller.referenceCoordinator.pendingOpenReferenceTask?.value
        #expect(openedInNewWindow.map(\.path) == [tracked.path])
    }
}
