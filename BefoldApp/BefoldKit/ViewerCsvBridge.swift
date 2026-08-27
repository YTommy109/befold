import Foundation

/// CSV/TSV の数値表示設定を JS へ渡す注入スクリプト。
///
/// `ViewerBridge` の extension ではなく**兄弟の型**にしてある。extension は
/// ファイルを分けても型グループの行数(scripts/check-type-group-size.sh)には
/// 合算されるため、責務を分けたことにならない。逆方向のメッセージを
/// `ViewerBridgeMessage` が、git 差分の呼び出しを `ViewerDiffBridge` が持つのと
/// 同じ並び。
///
/// 負の数の表記の rawValue は `CsvNegativeStyle` が唯一の情報源で、JS 側の
/// 受理リストとの一致は `ViewerBridgeContractTests` が検証する。
public enum ViewerCsvBridge {
    /// ロード時に CSV/TSV の桁区切り設定を注入するスクリプト。
    public static func csvNumberGroupingScript(_ grouping: Bool) -> String {
        ViewerBridge.assignGlobalScript(
            "window._mmdCsvGrouping", grouping, fallback: ViewerBridge.defaultingFallback
        )
    }

    /// ロード時に CSV/TSV の負の数の表記設定を注入するスクリプト。
    public static func csvNegativeStyleScript(_ style: CsvNegativeStyle) -> String {
        ViewerBridge.assignGlobalScript(
            "window._mmdCsvNegativeStyle", style.rawValue, fallback: "\"plain\""
        )
    }

    /// 設定変更時に数値表示設定を注入し直して即時反映するスクリプト。
    /// viewer 側は _mmdInitCsvNumberFormat() が注入値を読んで描き直す。
    public static func applyCsvNumberFormatScript(
        grouping: Bool, negativeStyle: CsvNegativeStyle
    ) -> String {
        csvNumberGroupingScript(grouping) + " " + csvNegativeStyleScript(negativeStyle) + " "
            + ViewerBridge.PlainFunction.initCsvNumberFormat.callScript + ";"
    }
}
