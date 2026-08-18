import BefoldKit
import Foundation

/// 文書内ジャンプで目印にする見出しレベルの**アプリ全体の既定値**を UserDefaults に永続化する。
///
/// 保持する値の意味は「次に開くウィンドウの出発点」であって、開いている窓の現在値ではない
/// （ADR 0002「窓の状態」。`SidebarDisplayDefaults` と同じ形）。ライブ値は窓ごとの viewer が
/// 持ち、窓はこの型を参照しない——窓の内側へ渡すのは書き戻し専用の
/// `HeadingJumpLevelRecording` だけ。
///
/// 保存はキー 1 本。Bool 3 本にすると `UserDefaults.bool(forKey:)` が未設定時 false を返すため、
/// 「初回（未設定）」と「ユーザーが 3 つとも OFF にした」を区別できず、後者が次の窓で
/// 既定へ戻ってしまう（TASK-485.2 の設計判断）。
///
/// **アプリ全体で 1 インスタンス。**生成するのは `AppStores` だけで、
/// `ViewerWindowManager` / `ViewerWindowController` はこれを必須引数で受け取る
/// （デフォルト引数を置くと、呼び出し側が黙って窓ごとのストアを作れてしまう。
/// TASK-485.15）。
@MainActor
final class HeadingJumpLevelDefaults: HeadingJumpLevelRecording {
    private let defaults: UserDefaults
    private static let levelsKey = "HeadingJumpLevels"

    /// 新しく開くウィンドウの初期値。**読むのは窓の生成時の 1 回だけ。**
    private(set) var levels: HeadingJumpLevels

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // stringArray はキーが無ければ nil を返す。nil（未設定）は既定へ、
        // 空配列（3 つとも OFF）はそのまま尊重する。
        levels = HeadingJumpLevels.stored(defaults.stringArray(forKey: Self.levelsKey))
    }

    /// 窓へ渡す設定一式。読むのは窓の生成時の 1 回だけ。
    var binding: HeadingJumpLevelBinding {
        HeadingJumpLevelBinding(initialLevels: levels, recording: self)
    }

    func record(_ levels: HeadingJumpLevels) {
        guard levels != self.levels else { return }
        self.levels = levels
        defaults.set(levels.storedValue, forKey: Self.levelsKey)
    }
}
