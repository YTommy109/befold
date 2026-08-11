import Foundation

/// viewer.html のロード完了ゲート。
///
/// 「準備できていなければ保留し、できたら 1 回だけ実行する」という判断を 1 型へ閉じる。
/// 保留の書き込み点が散っていると、後勝ちで前の保留更新が黙って消える形になっても
/// 気づけない(分離前は 4 箇所から書かれていた)。
@MainActor
final class ViewerReadinessGate {
    private(set) var isReady = false
    private var pendingWork: (() -> Void)?

    /// viewer.html の読み直しを開始した。以後の実行は準備完了まで保留する。
    func markNotReady() {
        isReady = false
    }

    /// 準備が整った。保留していた実行を 1 回だけ流す。
    func markReady() {
        isReady = true
        let work = pendingWork
        pendingWork = nil
        work?()
    }

    /// 準備できていれば即実行し、まだなら準備完了まで保留する。
    func run(_ work: @escaping () -> Void) {
        if isReady {
            work()
        } else {
            pendingWork = work
        }
    }

    /// 保留中の実行を、準備完了を待たずにいま流す(ナビゲーション失敗時の復帰)。
    func flushPending() {
        markReady()
    }
}
