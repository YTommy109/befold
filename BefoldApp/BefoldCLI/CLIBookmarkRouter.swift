import AppKit
import Foundation

/// `befold --bookmark <path>` のブックマーク追加を、どのプロセスが書くかを決めて実行する。
///
/// ブックマークは UserDefaults の配列を read-modify-write で更新するため、CLI と GUI が
/// 別プロセスから同時に書くと後勝ちで片方の追加が消える。起動中の befold.app があるときは
/// 追加要求を GUI へ転送し、GUI プロセスを唯一の writer にすることでこの競合を無くす。
/// 起動中インスタンスが無ければ writer は CLI だけなので、そのまま直接書く
/// (`--bookmark` は GUI を起動しない従来の挙動を保つ)。
public enum CLIBookmarkRouter {
    /// ブックマークを追加する。追加できたら true を返す。
    ///
    /// 転送に失敗した場合はローカル書き込みへフォールバックしない。遅れて届いた要求を
    /// GUI が処理すると二重書き込みになり、この経路で防いでいる競合が復活するため
    /// (転送失敗時に成功扱いしない方針は CLIAppLauncher と同じ)。
    @MainActor
    public static func add(
        _ url: URL,
        addLocally: @MainActor (URL) -> Void,
        findRunningInstance: @MainActor () -> NSRunningApplication? = { CLIRequestForwarder.runningInstance() },
        forward: @MainActor ([String]) async -> Bool = { await CLIRequestForwarder.forwardBookmark(paths: $0) }
    ) async -> Bool {
        guard findRunningInstance() != nil else {
            addLocally(url)
            return true
        }
        return await forward([url.path])
    }
}
