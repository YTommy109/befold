import Foundation

/// 文書内ジャンプで目印にする見出しレベルの集合（TASK-485.2）。
///
/// 値の意味は「h1 / h2 / h3 のうちどれを目印にするか」で、**空も正当な値**
/// （ユーザーが 3 つとも OFF にした状態）。文書に見出しが無いことと区別する。
public struct HeadingJumpLevels: Equatable, Sendable {
    /// ユーザーが選べるレベルの全体。ここが**この集合の単一の情報源**で、
    /// 既定値もフィルタ域もこれを見る（かつて `[1, 2, 3]` と `(1 ... 3)` が
    /// 別々に書かれており、片方だけ広げると黙って落ちる形だった）。
    ///
    /// JS 側の `HEADING_LEVELS`（viewer-src/jump-providers.ts）と一致していなければ
    /// ならず、ずれは `ViewerBridgeContractTests` が落として知らせる。
    /// ジャンプバーのトグルはこの JS 定数から生成されるので、HTML 側に
    /// 同じ集合は残っていない。
    public static let selectableLevels = [1, 2, 3]

    /// 目印にするレベル。`selectableLevels` の要素のみを持ち、常に昇順で重複しない。
    public let levels: [Int]

    /// 保存値が無いときの既定。選べるレベルすべてを目印にする。
    public static let `default` = HeadingJumpLevels(levels: selectableLevels)

    public init(levels: [Int]) {
        self.levels = Array(Set(levels.filter { Self.selectableLevels.contains($0) })).sorted()
    }

    /// UserDefaults / JS へ渡す表現（`["h1", "h2", "h3"]`）。
    /// 空配列は「3 つとも OFF」を表し、キーそのものが無い状態（未設定）と区別できる。
    public var storedValue: [String] {
        levels.map { "h\($0)" }
    }

    /// 保存表現から復元する。`nil`（キーが無い＝未設定）は既定へ倒し、
    /// 空配列は「3 つとも OFF」として尊重する。
    /// この 2 つを取り違えると、ユーザーが 3 つとも OFF にした状態が
    /// 次に窓を開いたとき勝手に既定へ戻る。
    public static func stored(_ value: [String]?) -> HeadingJumpLevels {
        guard let value else { return .default }
        return HeadingJumpLevels(levels: value.compactMap(levelNumber(from:)))
    }

    private static func levelNumber(from token: String) -> Int? {
        guard token.hasPrefix("h"), let number = Int(token.dropFirst()) else { return nil }
        return number
    }
}

/// 見出しレベルの既定値を**記録するだけ**の口。
///
/// 読み取り API が無いことで「生きている窓が保存値を読み直す」経路をコンパイル時に
/// 作れなくする（ADR 0002「窓の状態の規則」。`SidebarDisplayDefaultsRecording` と同じ形）。
/// ライブ値は窓ごとの viewer（WebView）が持ち、ここに保存されるのは
/// **次に開く窓の出発点**であって、開いている窓の現在値ではない。
@MainActor
public protocol HeadingJumpLevelRecording: AnyObject {
    /// 最新のレベル集合を既定値として記録する。窓が値を変えるたびに呼ばれ、後勝ちでよい。
    func record(_ levels: HeadingJumpLevels)
}

/// 窓へ渡す見出しジャンプの設定一式。
///
/// 「窓の生成時に読んだ出発点」と「変更を書き戻す口」は必ず対で要るため、
/// 別々の引数で持ち回らずここで束ねる（層をまたぐたびに 2 引数が増えるのを避ける）。
/// 記録口は読み取り API を持たないので、束ねても窓が保存値を読み直す経路はできない。
@MainActor
public struct HeadingJumpLevelBinding {
    /// この窓の出発点。生成時に 1 回だけ読んだ値。
    public let initialLevels: HeadingJumpLevels
    /// 変更を既定値へ書き戻す口。
    public let recording: any HeadingJumpLevelRecording

    public init(initialLevels: HeadingJumpLevels, recording: any HeadingJumpLevelRecording) {
        self.initialLevels = initialLevels
        self.recording = recording
    }
}
