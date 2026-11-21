// CSV/TSV のテーブル表示に git 差分を重ねる(TASK-483.2)。
//
// 旧版・新版の復元と単位の並べ替えは Markdown と共通(diff-units.ts)。
//
// git diff は行単位、表はレコード単位なので、csvRecordLineRanges で行をレコードへ
// 引き当てる(引用符内の改行で 1 レコードが複数行を占めても色がずれない)。

import type { CsvColumnFormat } from './csv-columns.js';
import { analyzeCsvColumns } from './csv-columns.js';
import { csvCellHtml, csvRecordLineRanges, parseCsv } from './csv-html.js';
import { orderDiffUnits, wholeFileDiffSides } from './diff-units.js';
import type { DiffUnit } from './diff-units.js';
import { escapeHtml } from './encoding.js';

function rowAttributes(record: DiffUnit): string {
  if (record.type === 'context') return '';
  return ' class="diff-' + record.type + '" data-diff-block="' + record.block + '"';
}

// 差分から CSV テーブルを組む。描けない差分(本文なし・バイナリ・複数ファイル・
// 全文でない差分)では null を返し、呼び出し側が通常のテーブル表示へ落とす。
//
// - ヘッダは新版の 1 行目。旧ヘッダが変わっていれば tbody の先頭に削除行として置く
//   (csv-resize.ts が tHead.rows[0] を見出しとして扱うため、thead は 1 行に保つ)
// - 削除行も表に実在する行なので、列幅の測定・数値書式の判定・検索の対象になる
function buildCsvDiffTable(
  diffText: string,
  delimiter: string,
): { html: string; formats: CsvColumnFormat[] } | null {
  var sides = wholeFileDiffSides(diffText);
  if (sides === null) {
    return null;
  }
  var oldText = sides.oldText;
  var newText = sides.newText;
  var oldRows = parseCsv(oldText, delimiter);
  var newRows = parseCsv(newText, delimiter);
  var records = orderDiffUnits(
    sides.lines,
    csvRecordLineRanges(oldText, delimiter),
    csvRecordLineRanges(newText, delimiter),
  );
  var rowOf = (r: DiffUnit): string[] => (r.side === 'old' ? oldRows : newRows)[r.index]!;
  var header = records.find((r) => r.side === 'new' && r.index === 0);
  var body = records.filter((r) => r !== header);
  var headerRow = header ? rowOf(header) : [];
  var bodyRows = body.map((r) => rowOf(r));
  // 旧ヘッダ(本文先頭の削除行)は見出しの文字列なので、列の書式判定に混ぜない
  // (数値の列が文字列の列と判定されて右寄せ・桁区切りが外れる)。
  var formats = analyzeCsvColumns([
    headerRow,
    ...bodyRows.filter((_, i) => !(body[i]!.side === 'old' && body[i]!.index === 0)),
  ]);
  // 行ごとに引数を広げる Math.max(...rows) は、大きな表で引数の上限を超えて投げる。
  var cols = headerRow.length;
  for (var r = 0; r < bodyRows.length; r++) {
    if (bodyRows[r]!.length > cols) cols = bodyRows[r]!.length;
  }

  var html = '<table><thead><tr' + (header ? rowAttributes(header) : '') + '>';
  for (var c = 0; c < cols; c++) {
    html += '<th>' + escapeHtml(headerRow[c] ?? '') + '</th>';
  }
  html += '</tr></thead><tbody>';
  body.forEach(function (record, i) {
    var row = bodyRows[i]!;
    html += '<tr' + rowAttributes(record) + '>';
    for (var k = 0; k < cols; k++) {
      html += csvCellHtml(row[k] ?? '', formats[k]);
    }
    html += '</tr>';
  });
  html += '</tbody></table>';
  return { html: html, formats: formats };
}

export { buildCsvDiffTable };
