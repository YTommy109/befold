import AppKit
import BefoldKit
import Foundation

/// ソース表示へ重ねる git 差分の取得と切り替え。
/// 本体(ViewerWindowController.swift)の行数上限を超えないよう extension に分けている。
@MainActor
extension ViewerWindowController {
    /// 差分の取得元。機能が無効なら nil を返し、git diff を一切実行しない。
    static func makeDiffLoader() -> GitDiffLoader? {
        FeatureGate.isSourceDiffEnabled ? GitDiffLoader() : nil
    }

    /// 表示中ファイルの差分を取り直して store へ反映する。
    ///
    /// 取得は非同期のため、戻ってきた時点で表示対象が変わっていないかを URL で確認する
    /// (遅れて着地した結果が現在の表示を壊すのを防ぐ)。切替時に古い差分を捨てる側は
    /// `ViewerStore.openFile` が担う(着地時の確認だけでは切替直後の残留を防げない)。
    ///
    /// リポジトリルートの解決も差分取得と同じ detached タスクの中で行う。キャッシュに
    /// 無いディレクトリでは `git rev-parse` のサブプロセスが起きるため、メインアクター上で
    /// 同期に呼ぶとコンテンツ再読込のたびに UI が止まりうる(遅いボリュームでは
    /// GitCommandRunner のタイムアウト分まで)。
    func refreshDiff() {
        guard let loader = diffLoader, diffDisplayPreference.isEnabled else {
            store.diffText = nil
            return
        }
        let url = fileURL
        let directory = url.deletingLastPathComponent()
        let index = gitFileIndex
        Task { @MainActor [weak self] in
            let root = await Task.detached(priority: .utility) {
                index.repositoryRoot(forDirectoryAt: directory)
            }.value
            guard let root else {
                guard let self, fileURL == url else { return }
                store.diffText = nil
                return
            }
            let result = await loader.diff(forFileAt: url, in: root)
            guard let self, fileURL == url else { return }
            store.diffText = Self.displayableDiff(result)
        }
    }

    /// 取得結果のうち、差分として描けるのは本文があるものだけ。
    /// それ以外(未追跡・バイナリ・変更なし・大きすぎる・取得できない)は nil にして
    /// 通常のソース表示へ戻す。理由ごとの表示分けは行わない(TASK-315 の次段)。
    static func displayableDiff(_ result: GitFileDiff?) -> String? {
        guard case let .diff(text) = result else { return nil }
        return text
    }

    /// View メニュー > 差分を表示。ソース表示に git 差分を重ねるかを切り替える。
    @objc func toggleSourceDiff(_ sender: Any?) {
        guard capabilities.canToggleDiff else { return }
        diffDisplayPreference.isEnabled.toggle()
        refreshDiff()
    }

    /// View メニュー > 差分を左右に並べる。インラインと左右分割を切り替える。
    @objc func toggleDiffLayout(_ sender: Any?) {
        guard capabilities.canToggleDiff else { return }
        diffDisplayPreference.layout = diffDisplayPreference.layout == .sideBySide ? .inline : .sideBySide
    }

    /// 差分表示が ON かどうか(メニューのチェック表示に使う)。
    var isSourceDiffEnabled: Bool {
        diffDisplayPreference.isEnabled
    }

    /// 差分レイアウトが左右分割かどうか(メニューのチェック表示に使う)。
    var isDiffLayoutSideBySide: Bool {
        diffDisplayPreference.layout == .sideBySide
    }
}
