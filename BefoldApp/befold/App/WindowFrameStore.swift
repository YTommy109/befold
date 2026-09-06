import Foundation

/// **新しいウィンドウの出発点になる寸法**を**窓の種別ごとに 1 個**持つ
/// （アプリ全体の好み / ADR 0002・ADR 0010）。ユーザーが最後にリサイズしたフレームを覚え、
/// 次に開く**同じ種別の**窓へそのまま渡す。フレームは `NSWindow.frameDescriptor` 形式の文字列。
///
/// **種別で分けるのは、用途ごとに欲しい寸法が違うため**(TASK-593.5)。スライド窓は画面共有や
/// プロジェクターへ映すので 16:9 に寄せたく、通常窓は文書を読む形にしたい。分けないと、
/// プレゼン用に広げた寸法が次に開く通常窓へそのまま漏れる（種別の帰結が全体の既定を汚す、
/// という `SidebarStateStore` の折りたたみと同じ型の事故）。
///
/// **ADR 0010 が禁じた「ファイル単位」とは軸が違う。** あちらの失敗は、記憶の個数が
/// ファイル数だけ増えて後からの調整が過去のファイルへ永久に届かないことだった（実測 104 件中
/// 一致 1 件）。種別は閉じた 2 値で、同じ種別の窓を 1 回リサイズすれば次から必ずそれで開く。
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
    /// 種別ごとの保存キー。**通常窓は既存のキーをそのまま使う**——変えると利用者が
    /// 今まで調整してきた寸法が黙って失われる（新設はスライド窓の側だけ）。
    private static func lastUserAdjustedKey(for kind: ViewerWindowKind) -> String {
        switch kind {
        case .viewer: "WindowFrameLastUserAdjusted"
        case .slide: "WindowFrameLastUserAdjustedSlide"
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// ユーザーがウィンドウをリサイズし終えたときに呼ぶ。
    ///
    /// **閉じたときには呼ばない。** 複数の窓を一括で閉じると `windowWillClose` の到達順は
    /// AppKit 任せで、どの窓の寸法が残るかを制御できない。「最後に調整した寸法」という
    /// 意味に素直な契機はリサイズの確定だけ。
    ///
    /// - Parameter kind: 記録先の種別。**既定値を持たせない**——渡し忘れが静かに
    ///   通常窓の壺へ倒れ、分けた意味が消える。
    func recordUserAdjustedFrame(_ descriptor: String, for kind: ViewerWindowKind) {
        defaults.set(descriptor, forKey: Self.lastUserAdjustedKey(for: kind))
    }

    /// その種別で最後に調整されたフレーム記述子。未調整なら nil
    /// （呼び出し側が種別ごとの既定サイズと中央配置へ縮退する）。
    ///
    /// **別の種別の値へはフォールバックしない。** スライド窓が未調整のときに通常窓の値を
    /// 借りると、まさに避けたい「文書用の寸法でプレゼンが始まる」が初回に起きる。
    func lastUserAdjustedFrameDescriptor(for kind: ViewerWindowKind) -> String? {
        defaults.string(forKey: Self.lastUserAdjustedKey(for: kind))
    }
}
