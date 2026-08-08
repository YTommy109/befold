import Foundation

/// プレビューエリアの表示モード。ツールバーの 3 択セグメントおよび ⌘1〜⌘3 と 1 対 1 に対応する。
///
/// 差分は「ソース表示中にだけ成立する」従属状態であり、以前は
/// 「ソース表示 Bool（ファイル単位）」と「差分 ON/OFF Bool（アプリ全体）」の 2 値で持っていた。
/// 2 値だと `.rendered` 表示なのに差分だけ ON という不整合が**状態として表現できてしまい**、
/// 実行時のガードで握り潰すしかなかった。1 値の列挙にすることで、その組み合わせを
/// 型として作れなくする（この不変条件を守るためのテストは不要になる）。
///
/// レンダラ（BefoldRenderKit）へはこの型を渡さない。RenderKit と QuickLook 拡張は
/// `isSourceMode: Bool` + `DiffState?` の 2 入力で表示を決めており、差分の有無は
/// 既に `DiffState?` が表現している。3 値をあちらへ押し込むと appex まで巻き込むため、
/// この型は本体アプリ層に閉じる。
enum ViewerDisplayMode: String, CaseIterable, Sendable {
    /// レンダリング表示（Markdown/Mermaid などを描画した状態）。
    case rendered
    /// ソース表示（原文をシンタックスハイライトして出した状態）。
    case source
    /// ソース表示に git 差分を重ねた状態。
    case diff

    /// ソース相当の内容を出しているか。RenderKit 境界へ渡す Bool はこれ 1 箇所で導出する。
    var isSourceMode: Bool {
        self != .rendered
    }

    /// git 差分を重ねているか。
    var showsDiff: Bool {
        self == .diff
    }

    /// View メニューの ⌘1〜⌘3 が「どのモードを選ぶ項目か」を運ぶためのタグ。
    /// NSMenuItem.tag の既定値は 0 で「未設定」と区別できないため 1 から振る。
    var menuItemTag: Int {
        switch self {
        case .rendered: 1
        case .source: 2
        case .diff: 3
        }
    }

    /// View メニューの項目名のローカライズキー。
    var menuLabelKey: String.LocalizationValue {
        switch self {
        case .rendered: "menu.view.showRendered"
        case .source: "menu.view.showSource"
        case .diff: "menu.view.showDiff"
        }
    }

    /// メニュー項目のタグからモードを復元する。該当が無ければ nil（他の項目のタグ）。
    init?(menuItemTag tag: Int) {
        guard let mode = Self.allCases.first(where: { $0.menuItemTag == tag }) else { return nil }
        self = mode
    }
}
