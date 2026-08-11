import BefoldKit
import WebKit

/// 直近に描画した表示状態のミラー。呼び出し側 content の全文を保持せず、
/// contentRevision の整数比較で再描画要否を判定することで重複バッファを避ける。
/// viewer.html 再ロード時は全値を必ずセットで破棄する必要があるため、
/// 個別フィールドではなく 1 つの struct にまとめている。破棄は
/// `DirectHTMLModeController.exit` が `recordRendered(RenderedStateMirror())` で
/// 空のミラーを丸ごと確定させる形で行う(唯一の破棄点)。
/// Equatable にしているのは「描画済みの状態と今回の入力が違うか」を
/// フィールドの列挙ではなく型の比較で判定するため(updateContent 参照)。
/// ここへフィールドを足すと再描画の判定にも自動で入る。
struct RenderedStateMirror: Equatable {
    /// 直近に描画した content の世代番号。
    var contentRevision: Int?
    var fileType: FileType?
    var filePath: URL?
    var showLineNumbers: Bool?
    var isSourceMode: Bool?
    /// 最後に _mmdSetTruncated へ送った切り詰め状態と表示行数
    /// (再読込での行数だけの変化もバナー更新できるよう両方をセットで保持する)。
    var truncation: TruncationState?
    /// 最後に setDiff / setDiffLayout へ送った差分表示の状態。
    var diffState: DiffState?
}

/// 段階読み込み(loadMoreLines)でステージされた次チャンク。実際の増分描画は
/// @Observable 変更が駆動する updateContent(唯一の描画 sink)が消費して行う。
/// revision は追記後の世代番号で、updateContent の contentRevision と一致した
/// ときだけ増分描画する(不一致=別更新に追い越された場合は破棄し全文 render に倒す)。
struct PendingAppend {
    let chunk: String
    let revision: Int
}

extension RenderedStateMirror {
    /// pendingAppend(段階読み込みでステージされた次チャンク)を全文 render せず増分描画して
    /// よいかどうかを判定する。
    ///
    /// 追記経路が JS へ送るのはチャンクと切り詰め状態だけで、行番号・モード・差分などの
    /// 注入は行わない。よって「追記が正しく更新できる 2 つ(contentRevision と truncation)を
    /// 除いて、更新後の状態が描画済みと一致している」ときだけ消費してよい。
    ///
    /// 比較する条件を並べず、ミラー同士を丸ごと突き合わせる形にしているのは、
    /// 列挙にするとミラーへフィールドを足したときにここへの追加だけ漏れ、その状態変化が
    /// 追記経路に吸収されて 1 周期失われるため(行番号トグルで一度、差分トグルで
    /// もう一度起きた形 = TASK-320)。
    nonisolated static func canConsume(
        _ pending: PendingAppend, incoming: RenderedStateMirror, rendered: RenderedStateMirror
    ) -> Bool {
        guard pending.revision == incoming.contentRevision else { return false }
        var comparable = incoming
        comparable.contentRevision = rendered.contentRevision
        comparable.truncation = rendered.truncation
        return comparable == rendered
    }

    /// 今回の render() がファイル/モードの実際の切替かどうかを判定する。
    /// 切替時のみ永続化済みスクロール位置(最大 200ms 古い可能性がある)で復元し、
    /// 同一ファイル・同一モードでの再描画(ライブリロード・行番号トグル等)では
    /// ライブの現在スクロール位置を優先させる(JS 側フォールバック。applyRender 参照)。
    nonisolated static func isFileOrModeSwitch(
        filePath: URL?, isSourceMode: Bool,
        lastRenderedFilePath: URL?, lastIsSourceMode: Bool?
    ) -> Bool {
        filePath != lastRenderedFilePath || isSourceMode != lastIsSourceMode
    }
}
