import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ウィンドウ生成経路(ViewerWindowManager)が差分まわりの共有インスタンスを配線しているか、
/// および窓をまたぐ挙動を確かめる。コントローラ単体テストでは捕まえられない層。
///
/// 差分の着地待ちは壁時計予算を持たない `waitForDeliveryOnMainActor` で行い、上限は
/// スイートの `testTimeLimit()` が担う。予算付きのポーリングに戻すと、full suite では
/// 予算が「操作にかかった時間」ではなく「順番待ちの時間」を測ることになり、実行全体が
/// 長引いただけで落ちる(TASK-354。TSan 付き CI で 3 件が同時に予算切れした)。
@Suite(testTimeLimit())
@MainActor
struct ViewerWindowManagerDiffTests {
    private let file = URL(fileURLWithPath: "/mock/note.swift")
    private let first = URL(fileURLWithPath: "/mock/first.swift")
    private let second = URL(fileURLWithPath: "/mock/second.swift")

    /// 差分表示を離れたら、以前の取得結果が残っていても差分は出さない。
    /// 表示モードはファイル単位なので、反転はコントローラ自身が行う。
    @Test("差分表示から離れると本文が捨てられる")
    func clearsDiffTextWhenLeavingDiffMode() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "DiffTests.clear")
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.allControllers.first)
        presentDocument(in: controller, file: file)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        controller.setDisplayMode(.source)

        #expect(!controller.isDiffShown)
        #expect(controller.store.diffText == nil)
    }

    /// 差分表示はファイル単位の表示モードなので、片方のウィンドウで差分にしても
    /// 他方のウィンドウ(別ファイル)は巻き込まれない。以前はアプリ全体の設定だったため、
    /// 1 枚での切替が全ウィンドウへ波及していた(TASK-356 で粒度を揃えた)。
    @Test("片方のウィンドウの差分表示は他方のウィンドウへ波及しない")
    func diffModeStaysWithinWindow() async {
        let fixture = MockedViewerWindowManager(
            files: [first, second], prefix: "DiffTests.broadcast",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: StubDiffReader(result: .diff("DIFF"))
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)
        for controller in controllers {
            controller.fileListModel.entries = [FileListEntry(url: controller.fileURL, kind: .file)]
            controller.fileListModel.selection = controller.fileURL
            controller.store.displayMode = .source
        }

        // 1 枚目のウィンドウのメニュー操作(⌘3)を再現する。
        controllers[0].setDisplayMode(.diff)

        #expect(controllers[0].isDiffShown)
        #expect(!controllers[1].isDiffShown)
        await waitForDeliveryOnMainActor {
            controllers[0].store.diffText == "DIFF"
        }
        #expect(controllers[1].store.diffText == nil)
    }

    /// 生成経路が共有インスタンスを渡していることの固定。
    /// 窓をまたぐ設定なのでコントローラ単体テストでは捕まえられない。
    /// レイアウトはアプリ全体の粒度のままなので、ここで共有が切れると 2 窓で
    /// 上下/左右がずれる(デフォルト引数を撤去した理由でもある = TASK-319)。
    @Test("生成したウィンドウは差分レイアウト設定を共有する")
    func openViewerSharesDiffDisplayPreference() {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)

        // 共有インスタンスを動かして観測する。
        fixture.diffDisplayPreference.layout = .sideBySide

        #expect(controllers.filter(\.isDiffLayoutSideBySide).count == controllers.count)
        let shared = controllers.filter { $0.diffDisplayPreference === fixture.diffDisplayPreference }
        #expect(shared.count == controllers.count)
    }

    /// AC#1: 生成経路が共有の取得元を渡していることの固定。窓ごとに生成すると
    /// 畳み込みが窓の中でしか効かず、1 回の保存で git が窓の数だけ起動する(TASK-325)。
    /// 非 nil のスタブを注入して測る。既定(ゲート依存)のままだと、無効ビルドでは
    /// 両方 nil で一致してしまい、共有していなくても通る。
    @Test("生成したウィンドウは差分の取得元を共有する")
    func openViewerSharesDiffLoader() throws {
        let fixture = MockedViewerWindowManager(
            files: [first, second], prefix: "DiffTests.sharedLoader",
            diffReader: StubDiffReader(result: .noChanges)
        )
        defer { fixture.closeAll() }
        let loader = try #require(fixture.diffLoader)
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)

        let shared = controllers.filter { $0.diffLoader === loader }
        #expect(shared.count == controllers.count)
    }

    /// AC#1(結合): 同じファイルを 2 窓で開いた状態で 1 回のファイル変更イベントが来ても、
    /// `git diff` の起動は 1 回に合流する。窓ごとの取得元へ戻す・チケットを取得直前に取る、
    /// のどちらでも窓の数だけ起動してここが落ちる(TASK-325)。
    @Test("同じファイルを 2 窓で開いても git diff は 1 回に合流する")
    func sharesOneFetchAcrossWindowsShowingTheSameFile() async throws {
        let shared = URL(fileURLWithPath: "/mock/shared.swift")
        let other = URL(fileURLWithPath: "/mock/other.swift")
        // 取得のたびに違う本文を返す。合流していれば 2 窓は同じ本文を受け取り、
        // 合流に失敗していれば食い違う。待ち時間ではなく本文の一致で判定できるため、
        // 負荷でどれだけ実行順がずれても結論が変わらない(TASK-346)。
        // 末尾に張り付くと別々の取得が同じ本文になり、食い違いを見逃す。セットアップの
        // 契機は数回で収まるため、余裕を持って使い切らない長さにしておく。
        let reader = SequenceDiffReader(results: (1 ... 20).map { .diff("取得\($0)") })
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DiffTests.oneFetch",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: reader
        )
        defer { fixture.closeAll() }
        // openViewer は同じファイルの重複ウィンドウを作らない(既存を前面化する)ため、
        // 2 窓目は別ファイルで開いてからウィンドウ内で切り替える。実際に同一ファイルが
        // 2 窓に並ぶのもこの経路。
        fixture.manager.openViewer(for: shared)
        fixture.manager.openViewer(for: other)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)
        try #require(controllers.first { $0.fileURL == other }).switchFile(to: shared)
        for controller in controllers {
            presentDocument(in: controller, file: shared)
        }
        #expect(controllers.allSatisfy { $0.fileURL == shared })
        // ウィンドウ生成・切替そのものも差分を取りに行くため、本文が入るまで待つ。
        await waitForDeliveryOnMainActor {
            controllers.allSatisfy { $0.store.diffText != nil }
        }
        let before = controllers.map(\.store.diffText)

        // 1 回のファイル変更イベントが全ウィンドウへ配られる経路と同じ形。
        for controller in controllers {
            controller.refreshDiff()
        }

        // まず両窓が取り直しの結果を受け取るまで待つ。合流の成否に関わらずここは満たされる
        // (合流しなければ別々の結果を、合流すれば同じ結果を受け取る)。
        await waitForDeliveryOnMainActor {
            zip(before, controllers).allSatisfy { $0 != $1.store.diffText }
        }

        // 合流の成否はここで分かれる。1 回の取得に合流していれば 2 窓は同じ本文を受け取り、
        // 窓ごとに取得が走れば別々の本文になる。
        //
        // 取得回数では測らない。セットアップ由来の取得が何回走るかは契機の重なり方で変わり、
        // 「静止した」と言える瞬間が無いため、回数の算術は実行順に左右される(CI で実際に
        // 落ちた = TASK-346)。取得回数そのものの検証は GitDiffLoaderTests が決定的に行う。
        let texts = controllers.map(\.store.diffText)
        #expect(texts[0] == texts[1])
    }

    /// AC#2: 取得元はマネージャが握っているため、1 窓を閉じても残る窓の取得は動く。
    /// ウィンドウ側が所有する形へ戻すと、閉じた窓と一緒に取得元が消えてここが落ちる。
    @Test("ウィンドウを閉じても他窓の差分取得に影響しない")
    func closingWindowDoesNotAffectOtherWindows() async throws {
        let fixture = MockedViewerWindowManager(
            files: [first, second], prefix: "DiffTests.closeIndependence",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: StubDiffReader(result: .diff("DIFF"))
        )
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)
        for controller in controllers {
            presentDocument(in: controller, file: controller.fileURL)
        }
        let survivor = try #require(controllers.first { $0.fileURL == second })

        controllers[0].close()
        survivor.refreshDiff()

        await waitForDeliveryOnMainActor {
            survivor.store.diffText == "DIFF"
        }
    }
}
