@testable import befold
import BefoldKit
import Foundation

// 差分テストで共有する取得器のスタブと、提示状態を作るヘルパー。
// コントローラ単体(ViewerWindowControllerDiffTests)とウィンドウ生成経路
// (ViewerWindowManagerDiffTests)の双方から使う。

/// 常に同じ結果を返す取得器。git は起こさない。
struct StubDiffReader: GitDiffReading {
    let result: GitFileDiff?

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        result
    }
}

/// 呼び出し回数を数える取得器。「取得そのものを走らせない」ことと
/// 「何回起動したか」の検証に使う。
final class RecordingDiffReader: GitDiffReading, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var requested: [URL] = []
    private let result: GitFileDiff?
    private let delay: TimeInterval

    init(result: GitFileDiff? = .noChanges, delay: TimeInterval = 0) {
        self.result = result
        self.delay = delay
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }; return calls
    }

    /// 取得を要求されたファイル。件数だけでは「どのファイルに git を起こしたか」が
    /// 分からず、種別ゲートの検証が無関係な取得まで数えてしまう(TASK-347)。
    var requestedFiles: [URL] {
        lock.lock(); defer { lock.unlock() }; return requested
    }

    func diff(forFileAt url: URL, in _: URL) -> GitFileDiff? {
        lock.lock()
        calls += 1
        requested.append(url)
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return result
    }
}

/// 呼ばれるたびに次の結果を返す取得器。「取得のたびに作業ツリーが変わっている」状況を作る。
/// 用意した結果を使い切ったら最後の値を返し続ける。
///
/// 合流の検証では、これを使うと**待ち時間に頼らずに**合流の成否が読める。合流していれば
/// 相乗りした全員が同じ値を受け取り、合流に失敗していれば受け取る値が食い違う。
final class SequenceDiffReader: GitDiffReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [GitFileDiff?]
    private var index = 0

    /// 呼び出し回数。用意した結果を使い切っても増え続けるため、
    /// 「取り直したか」を結果の中身と独立に測れる。
    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }

    init(results: [GitFileDiff?]) {
        self.results = results
    }

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        lock.lock()
        defer { lock.unlock() }
        let result = results[min(index, results.count - 1)]
        index += 1
        return result
    }
}

/// 文書を提示している状態(選択も現在ファイル)を作り、**発行済みの非同期仕事が
/// 残らないところまで**進める。表示モードは呼び出し側の指定のまま変えない。
///
/// 待ち合わせをここに置くのは、差分系テストが個別に await を足す形にしないため
/// (TASK-512)。コントローラ構築時に `SidebarNavigator` が必ず基準ディレクトリの
/// 解決タスクを飛ばすため、それを待たずに測ると、着地時の
/// `gitContextDidChange()` → `refreshDiff()` が確定済みの `.unavailable` を
/// `.pending` へ戻し、負荷の高いマシン(CI)でだけ後続の期待が落ちる。
@MainActor
func preparePresentedDocument(in controller: ViewerWindowController, file: URL) async {
    controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
    controller.fileListModel.selection = file
    await settleDiffTestController(controller)
}

/// 発行済みのコンテンツロード・サイドバー更新・差分取得を待ち切る。
///
/// 順序に意味がある。サイドバーの解決が着地すると `gitContextDidChange()` 経由で
/// 差分の取り直しが**新たに**飛ぶため、`awaitSettled()` の後に差分取得を待つ。
/// 壁時計予算(waitUntilOnMainActor)は使わない。予算はスイート全体の混雑時間まで
/// 測ってしまい、TSan ジョブでは操作の成否と無関係に切れる(TASK-437)。
@MainActor
func settleDiffTestController(_ controller: ViewerWindowController) async {
    await controller.store.loadTask?.value
    await controller.sidebar.awaitSettled()
    await controller.diffRefreshTask?.value
}

/// 差分を表示している状態(文書を提示していて選択も現在ファイル)を作る。
@MainActor
func presentDocument(in controller: ViewerWindowController, file: URL) async {
    await presentDocument(in: [controller], file: file)
}

/// 複数ウィンドウに同じ文書の差分表示を作る。
///
/// **提示は全ウィンドウぶんを同じターンで行う**。`GitDiffLoader` の畳み込みは
/// 「同じ契機(1 ターン)から出た要求」だけを合流させる契約なので、1 窓ずつ提示して
/// 待ち切ると兄弟要求が別ターンへ散り、合流の検証が成立しなくなる。
@MainActor
func presentDocument(in controllers: [ViewerWindowController], file: URL) async {
    for controller in controllers {
        controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
        controller.fileListModel.selection = file
        // 差分表示への切替そのものが取得を起こすため、待ち合わせはモードを変えた後に行う。
        controller.store.displayMode = .diff
    }
    for controller in controllers {
        await settleDiffTestController(controller)
    }
}
