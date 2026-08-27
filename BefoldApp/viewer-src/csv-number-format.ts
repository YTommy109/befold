// CSV/TSV テーブル表示の数値の見せ方(アプリ全体の設定)。Swift 側の
// CsvNumberFormatPreference が唯一の情報源で、ここは注入された値を保持し、
// 変更されたら現在の文書を描き直す。
//
// **view-options.ts へ相乗りさせていない**理由: あちらは「状態を持つだけで
// 再描画はしない(呼び出し側の Swift が直後に必ず render を送る)」という約束で
// 揃えてある。数値の見せ方は表示モードと違って Swift 側が render を送り直す
// 契機を持たない(設定窓での変更が唯一の契機)ため、ここは逆に**自分で
// 描き直す**。約束が逆のものを同じ入れ物へ入れると、どちらの規則で読めば
// よいか分からなくなる。
//
// このモジュールは**何も import しない**。csv-html.ts が状態を読み、
// 再描画を伴う入口(_mmdInitCsvNumberFormat)は render.ts が持つ。ここから
// render.js を import すると render → csv-html → csv-number-format → render の
// 循環になり、scripts/check-viewer-cycles.mjs が落ちる。

/// 負の数の見せ方。Swift の CsvNegativeStyle と同じ文字列を使う
/// (BefoldKit/CsvNegativeStyle.swift が唯一の情報源)。
type CsvNegativeStyle = 'plain' | 'triangle' | 'red' | 'triangleRed';

var CSV_NEGATIVE_STYLES: CsvNegativeStyle[] = ['plain', 'triangle', 'red', 'triangleRed'];

function _createCsvNumberFormat() {
  // 既定は Swift の CsvNumberFormatPreference と揃える。注入しないホスト
  // (QuickLook 拡張)はこの既定のまま描く。
  var grouping = true;
  var negativeStyle: CsvNegativeStyle = 'plain';
  return {
    grouping: function (): boolean {
      return grouping;
    },
    negativeStyle: function (): CsvNegativeStyle {
      return negativeStyle;
    },
    // 注入値を読み直す。未注入・未知の値は既定へ倒す(型の上で undefined を
    // 消さないのは viewer-globals.d.ts の方針どおり)。
    adopt: function (rawGrouping: unknown, rawStyle: unknown): void {
      grouping = rawGrouping === undefined ? true : rawGrouping !== false;
      negativeStyle = 'plain';
      for (var i = 0; i < CSV_NEGATIVE_STYLES.length; i++) {
        if (CSV_NEGATIVE_STYLES[i] === rawStyle) {
          negativeStyle = CSV_NEGATIVE_STYLES[i]!;
        }
      }
    },
  };
}

var _mmdCsvNumberFormat = _createCsvNumberFormat();

export type { CsvNegativeStyle };
export { CSV_NEGATIVE_STYLES, _mmdCsvNumberFormat };
