@testable import befold
import BefoldTestSupport
import Foundation
import Testing

/// ルート一覧とプレビューのフォルダー一覧が、列挙失敗を「空」として確定表示しないこと
/// (TASK-410 の AC#1 / AC#2)。判定そのものは SidebarEmptyStateTests が押さえるので、
/// ここは **本番の経路でその判定材料が届くか** を測る。
///
/// `SidebarNavigator` は host を weak 参照する。テストが host を捨てると
/// `refreshFileList` の `guard host != nil` で列挙自体が走らず、何も測らないまま
/// 通ってしまう(実際に一度そうなった)。各テストは host を最後まで握ること。
@MainActor
struct SidebarListingFailureTests {
    private let directory = URL(fileURLWithPath: "/tmp/befold-listing-failure")

    private func makeNavigator(
        listing: @escaping @Sendable (URL) -> DirectoryListing
    ) -> (SidebarNavigator, SidebarNavigatorStubHost) {
        let navigator = SidebarNavigator(
            currentDirectory: directory,
            entries: [],
            selection: nil,
            sidebarDisplayPreference: SidebarDisplayPreference(
                defaults: makeIsolatedDefaults(prefix: "SidebarListingFailureTests")
            ),
            directoryLister: { url, _, _ in listing(url) },
            resolveGitRoot: { _ in nil }
        )
        let host = SidebarNavigatorStubHost(
            currentFileURL: directory.appendingPathComponent("open.md")
        )
        navigator.attach(to: host)
        return (navigator, host)
    }

    /// ルート一覧には失敗を出す開閉三角が無いため、失敗は空状態の文言で伝えるほかない。
    /// ここが届かないと、権限の無いフォルダーが「対応ファイルがありません」になる。
    @Test("ルート列挙の失敗が、空状態の理由まで届く")
    func rootListingFailureReachesEmptyState() async {
        let (navigator, host) = makeNavigator { _ in .failed() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value

        #expect(navigator.fileListModel.didFailListing)
        let context = SidebarEmptyContext(model: navigator.fileListModel)
        #expect(SidebarEmptyState.reason(for: context) == .enumerationFailed)
        withExtendedLifetime(host) {}
    }

    /// 読めて空だったフォルダーは従来どおり「対応ファイルがありません」。
    /// 失敗側だけを見て両方を失敗にすると、空フォルダーの案内が消える。
    @Test("読めて空だったルート一覧は、従来どおり「対応ファイルなし」のまま")
    func emptyRootListingKeepsNoSupportedFiles() async {
        let (navigator, host) = makeNavigator { _ in [] }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value

        #expect(!navigator.fileListModel.didFailListing)
        let context = SidebarEmptyContext(model: navigator.fileListModel)
        #expect(SidebarEmptyState.reason(for: context) == .noSupportedFiles)
        withExtendedLifetime(host) {}
    }

    /// 失敗したフォルダーを読めるようになったら、表示も戻らなければならない。
    /// `didFailListing` を `setEntries` 以外の経路で書くと、ここが true のまま残る。
    @Test("読めるようになったら、失敗の状態は次の一覧で解除される")
    func failureClearsOnNextSuccessfulListing() async {
        let entry = FileListEntry(url: directory.appendingPathComponent("a.md"), kind: .file)
        let failing = LockedBox(true)
        let (navigator, host) = makeNavigator { _ in
            failing.value ? .failed() : DirectoryListing(rows: [entry])
        }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        #expect(navigator.fileListModel.didFailListing)

        failing.value = false
        navigator.refreshFileList()
        await navigator.pendingListingTask?.value

        #expect(!navigator.fileListModel.didFailListing)
        withExtendedLifetime(host) {}
    }

    /// 行だけを組み直す経路(展開・畳み)が失敗の事実を落とすと、子フォルダを 1 つ畳んだ
    /// だけで「読めなかった」が「空だった」に変わる。
    @Test("行の組み直しでは、列挙失敗の事実が落ちない")
    func rebuildingRowsKeepsFailure() async {
        let (navigator, host) = makeNavigator { _ in .failed() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value
        navigator.rebuildRows()

        #expect(navigator.fileListModel.didFailListing)
        withExtendedLifetime(host) {}
    }

    /// プレビューのフォルダー一覧(FolderListingView)は、サイドバーが揃えた一覧を
    /// `.shared` で受け取る。ここに失敗が乗らないと、同じフォルダーがサイドバーでは
    /// 「読み取れません」、プレビューでは「空のフォルダー」になる(TASK-320 と同型の片側修正)。
    @Test("サイドバーが渡すプレビュー用の一覧にも、列挙失敗が乗る")
    func sharedListingCarriesFailure() async {
        let (navigator, host) = makeNavigator { _ in .failed() }

        navigator.refreshFileList()
        await navigator.pendingListingTask?.value

        let model = navigator.fileListModel
        guard case let .shared(shared) = model.listingSource(for: model.currentDirectory) else {
            Issue.record("listingSource が .shared ではない")
            return
        }
        #expect(shared?.didFailEnumeration == true)
        withExtendedLifetime(host) {}
    }

    /// 行の同一性だけで比べると、読めなかった一覧と空だった一覧はどちらも 0 行で
    /// 等しくなり、読めるようになってもプレビューが描き直されない。
    @Test("プレビューの供給元の比較は、列挙の成否の違いを見落とさない")
    func sharedSourceEqualityDistinguishesFailure() {
        #expect(FolderListingSource.shared(.failed()) != .shared([]))
    }

    /// プレビューが自前で列挙する経路(選択中のサブフォルダー)でも、失敗は空一覧へ
    /// 畳まれずに残る。`.task` は SwiftUI を起動しないと動かせないため、
    /// 供給元を解決する純粋関数の側で固定する。
    @Test("自前列挙のプレビューでも、列挙失敗は空一覧に畳まれない")
    func ownListingKeepsFailure() {
        let resolved = FolderListingView.resolveListing(
            source: .ownListing, cached: .failed()
        )

        #expect(resolved?.didFailEnumeration == true)
        #expect(resolved?.entries.isEmpty == true)
    }
}

/// 列挙結果を差し替えるための可変の箱。`directoryLister` は `@Sendable` なクロージャで
/// 呼ばれるため、テスト側の可変状態はここへ閉じる。
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }
}
