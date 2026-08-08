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

/// 差分を表示している状態(文書を提示していて選択も現在ファイル)を作る。
@MainActor
func presentDocument(in controller: ViewerWindowController, file: URL) {
    controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
    controller.fileListModel.selection = file
    controller.store.displayMode = .diff
}
