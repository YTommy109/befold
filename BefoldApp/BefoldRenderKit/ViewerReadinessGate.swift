import Foundation

/// viewer.html のロード完了ゲート。
///
/// 「準備できていなければ保留し、できたら 1 回だけ実行する」という判断を 1 型へ閉じる。
/// 保留の書き込み点が散っていると、後勝ちで前の保留更新が黙って消える形になっても
/// 気づけない(分離前は 4 箇所から書かれていた)。
@MainActor
final class ViewerReadinessGate {
    private(set) var isReady = false
    /// 保留中の実行。1 スロットで持つと後から来た保留が前の保留を黙って上書きし、
    /// 描画要求が消える(TASK-446: 直接 HTML ロードの失敗で走る viewer.html 読み直しが、
    /// その間に積まれた別ファイルの描画要求を空 completion で置き換えていた)。
    /// 積まれた順に全て流すことでこの取りこぼしを構造的に無くす。
    private var pendingWork: [() -> Void] = []

    /// viewer.html の読み直しを開始した。以後の実行は準備完了まで保留する。
    func markNotReady() {
        isReady = false
    }

    /// 準備が整った。保留していた実行を積まれた順に 1 回ずつ流す。
    /// 流している最中に markNotReady + run で積み直された分は次の準備完了まで持ち越す
    /// (先にスロットを空にしてから実行するため、この場で消えることはない)。
    func markReady() {
        isReady = true
        let work = pendingWork
        pendingWork = []
        for item in work {
            item()
        }
    }

    /// 準備できていれば即実行し、まだなら準備完了まで保留する。
    func run(_ work: @escaping () -> Void) {
        if isReady {
            work()
        } else {
            pendingWork.append(work)
        }
    }

    /// 保留中の実行を、準備完了を待たずにいま流す(ナビゲーション失敗時の復帰)。
    func flushPending() {
        markReady()
    }
}
