import Foundation

/// **新しいウィンドウの出発点になる寸法**を 1 個だけ持つ（アプリ全体の好み / ADR 0002）。
/// ユーザーが最後にリサイズしたフレームを覚え、次に開く窓へそのまま渡す。
/// フレームは `NSWindow.frameDescriptor` 形式の文字列。
///
/// **ファイル単位では持たない。** かつては `WindowFrames`（正規化パス → 記述子）の辞書を
/// 持ち、「そのファイル自身の保存値 → 直近アクティブ窓の値 → この値」の順で解決していたが、
/// ウィンドウを開いた時点で解決結果を各ファイルへ書き戻していたため、一度開いたファイルは
/// 以後ずっと自分の古い値で開き、あとから調整した寸法が永久に届かなかった
/// （実測 2026-09-01: 記録 104 件のうち、最後に調整した寸法と一致するのは 1 件だけ）。
/// TASK-583 でファイル単位の記憶をやめ、この 1 個に畳んだ。判断の経緯は
/// `docs/adr/0010-window-frame-app-wide-default.md` を参照。
///
/// **URL を引数に取る API を置かない。** 置くとファイル単位で読む書き方が復活しうるので、
/// 粒度を doc コメントではなく型の形で守る。再起動時に窓ごとの寸法を戻すのは
/// この型ではなく `SessionLayout.TabGroup.frame`（窓の状態）の仕事。
@MainActor
final class WindowFrameStore {
    private static let lastUserAdjustedKey = "WindowFrameLastUserAdjusted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// ユーザーがウィンドウをリサイズし終えたときに呼ぶ。
    ///
    /// **閉じたときには呼ばない。** 複数の窓を一括で閉じると `windowWillClose` の到達順は
    /// AppKit 任せで、どの窓の寸法が残るかを制御できない。「最後に調整した寸法」という
    /// 意味に素直な契機はリサイズの確定だけ。
    func recordUserAdjustedFrame(_ descriptor: String) {
        defaults.set(descriptor, forKey: Self.lastUserAdjustedKey)
    }

    /// ユーザーが最後に調整したフレーム記述子。未調整なら nil
    /// （呼び出し側が既定のサイズとカスケード配置へ縮退する）。
    var lastUserAdjustedFrameDescriptor: String? {
        defaults.string(forKey: Self.lastUserAdjustedKey)
    }
}
