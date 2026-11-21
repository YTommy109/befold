// CSV/TSV のテーブル表示に git 差分を重ねる(TASK-483.2)。
//
// 差分は -U1000000 の全文差分で届く(GitDiffReader.wholeFileContextLines)ため、
// 差分本文だけから旧版・新版の全文を復元できる。チャンク読み込み中の content には
// 頼らず、表は常に差分から組む(段階読み込み中でも全レコードがそろう)。
//
// git diff は行単位、表はレコード単位なので、csvRecordLineRanges で行をレコードへ
// 引き当てる(引用符内の改行で 1 レコードが複数行を占めても色がずれない)。
// 削除行を含む旧レコードを削除、追加行を含む新レコードを追加とみなし、文書順に並べる。

import type { CsvColumnFormat } from './csv-columns.js';
import { analyzeCsvColumns } from './csv-columns.js';
import { csvCellHtml, csvRecordLineRanges, parseCsv } from './csv-html.js';
import { parseUnifiedDiff } from './diff-parse.js';
import type { DiffLine } from './diff-parse.js';
import { escapeHtml } from './encoding.js';

/// 表に並べる 1 レコード。side は旧版・新版のどちらのレコードか。
interface CsvDiffRecord {
  type: 'context' | 'add' | 'del';
  side: 'old' | 'new';
  index: number;
  block: number | null;
}

// 行番号(0 始まり)→ レコード番号の表。
function lineToRecord(ranges: [number, number][]): number[] {
  var map: number[] = [];
  for (var r = 0; r < ranges.length; r++) {
    for (var line = ranges[r]![0]; line < ranges[r]![1]; line++) {
      map.push(r);
    }
  }
  return map;
}

// 差分の行を文書順に辿り、表に並べるレコード列を作る。純関数(テストが直接呼ぶ)。
//
// 同じ位置では削除レコードを追加レコードより先に出す(ソース差分の並びと同じ)。
// 未変更の旧レコードは新レコードと同じものなので出さない。
// 変更ブロックは「削除の連なり + 直後の追加の連なり」を 1 つとして数える
// (assignChangeBlockIndexes と同じ畳み方。差分ジャンプの件数がソース差分と揃う)。
function orderCsvDiffRecords(
  lines: DiffLine[],
  oldRanges: [number, number][],
  newRanges: [number, number][],
): CsvDiffRecord[] {
  var oldOfLine = lineToRecord(oldRanges);
  var newOfLine = lineToRecord(newRanges);
  var oldChanged: boolean[] = oldRanges.map(() => false);
  var newChanged: boolean[] = newRanges.map(() => false);
  var oldLine = 0;
  var newLine = 0;
  lines.forEach(function (line) {
    if (line.type !== 'add') {
      if (line.type === 'del') oldChanged[oldOfLine[oldLine]!] = true;
      oldLine++;
    }
    if (line.type !== 'del') {
      if (line.type === 'add') newChanged[newOfLine[newLine]!] = true;
      newLine++;
    }
  });

  var records: CsvDiffRecord[] = [];
  var oldSeen = -1;
  var newSeen = -1;
  var block = -1;
  var previous: CsvDiffRecord['type'] = 'context';
  function emit(type: CsvDiffRecord['type'], side: 'old' | 'new', index: number): void {
    if (type !== 'context' && (previous === 'context' || (previous === 'add' && type === 'del'))) {
      block++;
    }
    records.push({
      type: type,
      side: side,
      index: index,
      block: type === 'context' ? null : block,
    });
    previous = type;
  }
  oldLine = 0;
  newLine = 0;
  lines.forEach(function (line) {
    if (line.type !== 'add') {
      var o = oldOfLine[oldLine++]!;
      if (o > oldSeen) {
        oldSeen = o;
        if (oldChanged[o]) emit('del', 'old', o);
      }
    }
    if (line.type !== 'del') {
      var n = newOfLine[newLine++]!;
      if (n > newSeen) {
        newSeen = n;
        emit(newChanged[n] ? 'add' : 'context', 'new', n);
      }
    }
  });
  return records;
}

function rowAttributes(record: CsvDiffRecord): string {
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
  var files = parseUnifiedDiff(diffText);
  if (files.length !== 1 || files[0]!.isBinary || files[0]!.hunks.length !== 1) {
    return null;
  }
  var hunk = files[0]!.hunks[0]!;
  // 全文差分なら旧版・新版とも 1 行目(新規・削除ファイルは 0)から始まる。
  if (hunk.oldStart > 1 || hunk.newStart > 1) {
    return null;
  }
  var lines = hunk.lines;
  var oldText = lines
    .filter((l) => l.type !== 'add')
    .map((l) => l.text)
    .join('\n');
  var newText = lines
    .filter((l) => l.type !== 'del')
    .map((l) => l.text)
    .join('\n');
  var oldRows = parseCsv(oldText, delimiter);
  var newRows = parseCsv(newText, delimiter);
  var records = orderCsvDiffRecords(
    lines,
    csvRecordLineRanges(oldText, delimiter),
    csvRecordLineRanges(newText, delimiter),
  );
  var rowOf = (r: CsvDiffRecord): string[] => (r.side === 'old' ? oldRows : newRows)[r.index]!;
  var header = records.find((r) => r.side === 'new' && r.index === 0);
  var body = records.filter((r) => r !== header);
  var headerRow = header ? rowOf(header) : [];
  var bodyRows = body.map((r) => rowOf(r));
  var formats = analyzeCsvColumns([headerRow, ...bodyRows]);
  var cols = Math.max(headerRow.length, ...bodyRows.map((row) => row.length));

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

export { orderCsvDiffRecords, buildCsvDiffTable };
