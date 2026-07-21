import Foundation

/// CLIInstanceRouter.forward() の再送(ACK ロスト時の回復のための同一requestIDでの再通知)により、
/// 受信側で同じ要求が複数回処理されるのを防ぐ。
struct CLIRequestDeduplicator {
    private var seenRequestIDs: Set<String> = []

    /// requestID が初めて見るものなら true(処理してよい)を返し、以後同じ requestID を記憶する。
    /// 既に見た requestID なら false(スキップすべき)を返す。
    /// requestID が無い(nil)場合は常に true として扱う。
    mutating func shouldProcess(requestID: String?) -> Bool {
        guard let requestID else { return true }
        return seenRequestIDs.insert(requestID).inserted
    }
}
