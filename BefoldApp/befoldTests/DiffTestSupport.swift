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
    private let result: GitFileDiff?
    private let delay: TimeInterval

    init(result: GitFileDiff? = .noChanges, delay: TimeInterval = 0) {
        self.result = result
        self.delay = delay
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }; return calls
    }

    func diff(forFileAt _: URL, in _: URL) -> GitFileDiff? {
        lock.lock()
        calls += 1
        lock.unlock()
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return result
    }
}

/// 差分をトグルできる状態(文書を提示していて選択も現在ファイル)を作る。
@MainActor
func presentDocument(in controller: ViewerWindowController, file: URL) {
    controller.fileListModel.entries = [FileListEntry(url: file, kind: .file)]
    controller.fileListModel.selection = file
    controller.store.isSourceMode = true
}
