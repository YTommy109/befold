import AppKit
@testable import befold
import BefoldKit
import BefoldTestSupport
import Foundation
import Testing

/// ウィンドウ生成経路(ViewerWindowManager)が差分まわりの共有インスタンスを配線しているか、
/// および窓をまたぐ挙動を確かめる。コントローラ単体テストでは捕まえられない層。
@Suite
@MainActor
struct ViewerWindowManagerDiffTests {
    private let file = URL(fileURLWithPath: "/mock/note.swift")
    private let first = URL(fileURLWithPath: "/mock/first.swift")
    private let second = URL(fileURLWithPath: "/mock/second.swift")

    /// 設定が OFF なら、以前の取得結果が残っていても差分は出さない。
    /// 反転は ViewerWindowManager 経由なので、そこから駆動して確かめる。
    @Test("差分表示を OFF にすると本文が捨てられる")
    func clearsDiffTextWhenDisabled() throws {
        let fixture = MockedViewerWindowManager(files: [file], prefix: "DiffTests.clear")
        defer { fixture.closeAll() }
        fixture.diffDisplayPreference.isEnabled = true
        fixture.manager.openViewer(for: file)
        let controller = try #require(fixture.manager.allControllers.first)
        presentDocument(in: controller, file: file)
        controller.store.diffText = "@@ -1 +1 @@\n-a\n+b\n"

        fixture.manager.toggleSourceDiff()

        #expect(fixture.diffDisplayPreference.isEnabled == false)
        #expect(controller.store.diffText == nil)
    }

    /// 共有設定なので、片方のウィンドウの ⌘D は他方の差分まで取り直させる。
    /// 反転したウィンドウだけが取り直すと、他方はメニューのチェックだけ変わる(TASK-330)。
    @Test("片方のウィンドウのトグルが全ウィンドウの差分に届く")
    func toggleReachesEveryWindow() async {
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
            presentDocument(in: controller, file: controller.fileURL)
        }

        // 1 枚目のウィンドウのメニュー操作(⌘D)を再現する。
        controllers[0].toggleSourceDiff(nil)

        #expect(fixture.diffDisplayPreference.isEnabled)
        // 2 窓ぶんの取得が detached の utility タスクを経由するため長めに待つ。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controllers.allSatisfy { $0.store.diffText == "DIFF" }
        }
    }

    /// 生成経路が共有インスタンスを渡していることの固定。
    /// 窓をまたぐ設定なのでコントローラ単体テストでは捕まえられない。
    @Test("生成したウィンドウは差分表示設定を共有する")
    func openViewerSharesDiffDisplayPreference() {
        let fixture = MockedViewerWindowManager(files: [first, second])
        defer { fixture.closeAll() }
        fixture.manager.openViewer(for: first)
        fixture.manager.openViewer(for: second)
        let controllers = fixture.manager.allControllers
        #expect(controllers.count == 2)

        // 共有インスタンスを動かして観測する。メニュー操作(toggleSourceDiff)経由だと
        // フィーチャーゲート無効時に両方 false のまま一致し、共有していなくても通る。
        fixture.diffDisplayPreference.isEnabled = true

        let enabled = controllers.filter(\.isDiffShown)
        #expect(enabled.count == controllers.count)
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
        let reader = SequenceDiffReader(
            results: [.diff("取得1"), .diff("取得2"), .diff("取得3"), .diff("取得4")]
        )
        let fixture = MockedViewerWindowManager(
            files: [shared, other], prefix: "DiffTests.oneFetch",
            contents: "let a = 1", repositoryRoot: URL(fileURLWithPath: "/mock"),
            diffReader: reader
        )
        defer { fixture.closeAll() }
        fixture.diffDisplayPreference.isEnabled = true
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
        // ウィンドウ生成・切替そのものも差分を取りに行くため、それが片付くまで待つ。
        // 走行中の取得が残ったまま測ると、合流できたかどうかと区別が付かない。
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controllers.allSatisfy { $0.store.diffText != nil }
        }
        let before = reader.calls

        // 1 回のファイル変更イベントが全ウィンドウへ配られる経路と同じ形。
        for controller in controllers {
            controller.refreshDiff()
        }

        // 2 窓ぶんの要求が 1 回の取得へ合流する。窓ごとにローダーを持つ形へ戻すと 2 回になる。
        let expected = "取得\(before + 1)"
        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            controllers.allSatisfy { $0.store.diffText == expected }
        }
        // 合流していなければ 2 窓は別々の本文を受け取るため、上の待機が揃わずに落ちる。
        // 取得回数でも裏を取る(本文が偶然揃う経路を残さない)。
        #expect(reader.calls == before + 1)
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
        fixture.diffDisplayPreference.isEnabled = true
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

        await waitUntilOnMainActor(timeout: testTimeout(fallback: 60)) {
            survivor.store.diffText == "DIFF"
        }
    }
}
