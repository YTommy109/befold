import AppKit

/// ツールバーアイテム 1 つの identity(識別子・シンボル・ラベル・アクション・状態反映規則)を
/// 1 箇所で宣言する記述。生成(makeItem)と再同期(refreshToolbarState)の双方がこの記述だけを見るため、
/// アイテムを追加・変更するときに触る箇所は ViewerToolbarController.layout の 1 行で済む。
///
/// internal なのは ViewerToolbarController+ToolbarDelegate がアイテム生成に使うため。
/// 生成・状態反映の実装以外から参照しない。
@MainActor
struct ToolbarItemSpec {
    /// アイテムの view の種類と、その生成に必要なシンボル・アクション。
    enum ViewKind {
        /// 単一シンボルのボタン(行番号・ブックマーク)。
        case button(symbol: String, action: Selector)
        /// 履歴ナビゲーション用ボタン。primaryOffset の符号で戻る/進むを決める。
        case historyButton(symbol: String, offset: Int)
        /// レンダリング/ソース/差分のモード切替セグメント。
        case modeSegments
    }

    let identifier: NSToolbarItem.Identifier
    /// アイテムのラベル(および多くのアイテムのツールチップ)のローカライズキー。
    let labelKey: String.LocalizationValue
    let view: ViewKind
    /// オーバーフロー(»)メニュー項目に割り当てるアクション。
    /// nil なら menuFormRepresentation を作らない(セグメントコントロールは分解できないため対象外)。
    let menuAction: Selector?
    /// ナビゲーション項目としてウィンドウタイトルより先頭側へ配置するか。
    var isNavigational = false
    /// 生成済みアイテムへ現在の状態(有効/無効・アイコン・色・ツールチップ)を反映する規則。
    let applyState: (ViewerToolbarController, NSToolbarItem) -> Void
}

/// ツールバーの構成要素。順序をそのまま既定の表示順として使うため、
/// アイテムと AppKit 標準アイテム(サイドバー開閉・スペーサー)を同じ並びで表現する。
///
/// internal なのは ToolbarItemSpec と同じ理由(分割した extension から参照するため)。
@MainActor
enum ToolbarEntry {
    case system(NSToolbarItem.Identifier)
    case item(ToolbarItemSpec)

    var identifier: NSToolbarItem.Identifier {
        switch self {
        case let .system(identifier): identifier
        case let .item(spec): spec.identifier
        }
    }

    var spec: ToolbarItemSpec? {
        switch self {
        case .system: nil
        case let .item(spec): spec
        }
    }
}
