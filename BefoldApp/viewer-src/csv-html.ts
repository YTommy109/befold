// CSV/TSV の解析と HTML 組み立て。テーブル表示(parseCsv 経由)とソース表示
// (csvSourceInnerHtml 経由)が 1 本のトークナイザーを共有する。

import { wrapWithLineNumbers } from './code-html.js';
import type { CsvColumnFormat } from './csv-columns.js';
import { analyzeCsvColumns, groupCsvNumber } from './csv-columns.js';
import { _mmdCsvNumberFormat } from './csv-number-format.js';
import { escapeHtml } from './encoding.js';

/// tokenizeCsvRows() が返す 1 セル。value はデコード済みの値、raw はソース上の
/// 生テキスト(クオート・エスケープされたクオートを含む)。
interface CsvCell {
  value: string;
  raw: string;
}

// RFC 4180 準拠の状態マシンベース CSV/TSV トークナイザー。
// クオート内のデリミタ・改行・エスケープされたクオート("")を正しく扱う。
// 各セルについて、デコード済みの値(value)とソース上の生テキスト(raw、
// クオート・エスケープされたクオートを含み、クオート内の改行もそのまま残る)
// の両方を返す。parseCsv(データ用)と renderCsvSourceHtml(ソース表示用)は
// この 1 本のトークナイザーを共有し、行またぎのクオートでも同じ列境界になる。
function tokenizeCsvRows(content: string, delimiter: string): CsvCell[][] {
  if (!content) {
    return [];
  }
  var rows: CsvCell[][] = [];
  var row: CsvCell[] = [];
  var value = '';
  var raw = '';
  var inQuotes = false;
  var i = 0;
  function pushField(): void {
    row.push({ value: value, raw: raw });
    value = '';
    raw = '';
  }
  function pushRow(): void {
    pushField();
    rows.push(row);
    row = [];
  }
  while (i < content.length) {
    // i < content.length のループ内なので必ず存在する。非 null 表明は
    // 実行時の振る舞いを変えずに noUncheckedIndexedAccess を通すため。
    var ch = content[i]!;
    if (inQuotes) {
      if (ch === '"') {
        // 直後にもう1つ " があれば RFC 4180 のエスケープされたクオート("" → ")。
        // value には 1 個の " だけを積み、raw には元の "" を丸ごと残す。
        if (i + 1 < content.length && content[i + 1] === '"') {
          value += '"';
          raw += '""';
          i += 2;
        } else {
          // エスケープでない単独の " はクオートフィールドの終端。
          raw += ch;
          inQuotes = false;
          i++;
        }
      } else {
        // クオート内ではデリミタ・改行もすべて通常文字として蓄積する
        // (行またぎのセルを1フィールドとして扱うための核心部分)。
        value += ch;
        raw += ch;
        i++;
      }
    } else if (ch === '"') {
      inQuotes = true;
      raw += ch;
      i++;
    } else if (ch === delimiter) {
      pushField();
      i++;
    } else if (ch === '\r') {
      // \r\n を1つの改行として扱うため、直後の \n を先読みして読み飛ばす。
      pushRow();
      i++;
      if (i < content.length && content[i] === '\n') {
        i++;
      }
    } else if (ch === '\n') {
      pushRow();
      i++;
    } else {
      value += ch;
      raw += ch;
      i++;
    }
  }
  // 末尾行の確定: ループ終了時点で未確定のフィールド/行が残っていれば push する。
  // ただし content が改行で終わっている場合は既に pushRow 済みで value/raw/row が
  // 空のため、ここでの再 push を条件付きでスキップし、末尾に幻の空行を作らない。
  if (value !== '' || raw !== '' || row.length > 0) {
    pushRow();
  }
  return rows;
}

// セル値に含まれる 2 文字のエスケープシーケンスを実際の制御文字へ展開する。
// 対象は \n / \t / \r / \\ の 4 つ。左から 1 パスで走査するため、\\n は
// 「エスケープされたバックスラッシュ + n」として解釈され、リテラルの \n が残る。
// 未知のシーケンス(\q など)と末尾の単独バックスラッシュはそのまま残す。
// テーブル表示のセルは style.css で white-space: pre-line なので、実改行を
// 入れるだけで追加の CSS なしにそのまま改行として表示される。ソース表示は
// raw を使うため影響を受けない(行番号と実ファイルの行がずれないようにするため)。
var CSV_ESCAPES: Record<string, string> = { n: '\n', t: '\t', r: '\r', '\\': '\\' };

function unescapeCellValue(value: string): string {
  if (!value.includes('\\')) {
    return value;
  }
  var out = '';
  var i = 0;
  while (i < value.length) {
    var ch = value[i]!;
    if (ch === '\\' && i + 1 < value.length) {
      var next = value[i + 1]!;
      if (Object.prototype.hasOwnProperty.call(CSV_ESCAPES, next)) {
        out += CSV_ESCAPES[next]!;
        i += 2;
        continue;
      }
    }
    out += ch;
    i++;
  }
  return out;
}

// tokenizeCsvRows のセルから value だけを取り出した、データ用の行配列。
// テーブル表示の唯一の入口なので、エスケープシーケンスの展開もここで行う
// (初回描画 buildTableHtml とチャンク追記 csvRowsHtml の両方に一度に効く)。
function parseCsv(content: string, delimiter: string): string[][] {
  var tokenRows = tokenizeCsvRows(content, delimiter);
  var rows: string[][] = [];
  for (var r = 0; r < tokenRows.length; r++) {
    var row: string[] = [];
    for (var c = 0; c < tokenRows[r]!.length; c++) {
      row.push(unescapeCellValue(tokenRows[r]![c]!.value));
    }
    rows.push(row);
  }
  return rows;
}

// 本文 1 セル分の <td>…</td>。列の書式(csv-columns.js の判定)に応じて
// class="csv-num"(右寄せ + tabular-nums)と整数部の桁区切りを付ける。
// 判定が 'text' の列、および判定の無い列(後続チャンクで増えた列)は素通しする。
//
// **ヘッダー(<th>)には使わない。** 見出しの寄せはブラウザ既定の中央のままにする。
function csvCellHtml(value: string, format: CsvColumnFormat | undefined): string {
  if (format === undefined || format === 'text') {
    return '<td>' + escapeHtml(value) + '</td>';
  }
  // 桁区切りと負の数の表記は grouped 列(第 2 段を通った量の列)のセルにのみ効かせる。
  // コードとみなされた列(numeric 止まり)は右寄せまでで、値の見た目は変えない。
  var className = 'csv-num';
  var shown = value;
  if (format === 'grouped') {
    var trimmed = value.trim();
    if (trimmed !== '') {
      var formatted = formatCsvNumber(trimmed);
      if (formatted.text !== trimmed) {
        shown = value.replace(trimmed, formatted.text);
      }
      if (formatted.negative) {
        className += ' csv-negative';
      }
    }
  }
  return '<td class="' + className + '">' + escapeHtml(shown) + '</td>';
}

// grouped 列の 1 セル分の見せ方を決める。桁区切りの有無と負の数の表記は
// アプリ全体の設定(csv-number-format.js)に従う。値そのものは書き換えず、
// 小数部は原文のまま残す。
//
// negative は「赤字クラスを付けるか」で、▲ 表記とは独立に返す。会計慣習の
// ▲ と赤字は組み合わせて選べる設定になっているため。
function formatCsvNumber(trimmed: string): { text: string; negative: boolean } {
  var style = _mmdCsvNumberFormat.negativeStyle();
  var isNegative = trimmed.startsWith('-');
  var text = _mmdCsvNumberFormat.grouping() ? groupCsvNumber(trimmed) : trimmed;
  if (isNegative && (style === 'triangle' || style === 'triangleRed')) {
    // 会計表記では符号そのものを ▲ へ置き換える(▲ と - を併記しない)。
    text = '\u25B2' + text.slice(1);
  }
  return { text: text, negative: isNegative && (style === 'red' || style === 'triangleRed') };
}

// CSV 行の配列から <tr><td>…</td></tr> 列(文字列連結)を組み立てる。
// 各行は max(minCols, 行の列数) まで空セルでパディングし、セルは escapeHtml する。
// buildTableHtml の <tbody> とチャンク追記(render.js の appendChunk)が共有する。
//
// formats は列ごとの書式判定。**省略可能にしていない**のは、渡し忘れが
// コンパイルエラーにならず「静かに全列 text 扱い」になり、初回描画と
// チャンク追記で見た目が食い違うため(TASK-319 と同型の穴)。
function csvRowsHtml(rows: string[][], minCols: number, formats: CsvColumnFormat[]): string {
  var html = '';
  for (var r = 0; r < rows.length; r++) {
    var cols = Math.max(minCols, rows[r]!.length);
    html += '<tr>';
    for (var c = 0; c < cols; c++) {
      html += csvCellHtml(c < rows[r]!.length ? rows[r]![c]! : '', formats[c]);
    }
    html += '</tr>';
  }
  return html;
}

// CSV 行の配列から HTML テーブル文字列を組み立てる。1行目を <thead>、残りを <tbody> にする。
// 列数が揃っていない行は空セルでパディングする。
//
// formats は列ごとの書式判定。呼び出し元(renderers.js の _renderCsv)は
// buildCsvTable を通してこれを受け取り、同じ判定をチャンク追記へ持ち越す。
// **ヘッダーは formats を見ない。** 見出しの寄せは数値列でも従来どおり
// ブラウザ既定の中央のままにする(寄せるのは本文のセルだけ)。
function buildTableHtml(rows: string[][], formats: CsvColumnFormat[]): string {
  if (rows.length === 0) {
    return '';
  }
  var maxCols = 0;
  for (var r = 0; r < rows.length; r++) {
    if (rows[r]!.length > maxCols) {
      maxCols = rows[r]!.length;
    }
  }
  var html = '<table><thead><tr>';
  for (var c = 0; c < maxCols; c++) {
    html += '<th>' + escapeHtml(c < rows[0]!.length ? rows[0]![c]! : '') + '</th>';
  }
  html += '</tr></thead><tbody>';
  html += csvRowsHtml(rows.slice(1), maxCols, formats);
  html += '</tbody></table>';
  return html;
}

// CSV/TSV 本文からテーブル HTML と列判定をまとめて作る。列判定は
// チャンク追記(render.js の appendChunk)が同じ書式を使うために返す。
// 判定と組み立てを 1 つの入口に閉じることで、片方だけ別の rows から
// 作られる経路を作らない。
function buildCsvTable(
  content: string,
  delimiter: string,
): { html: string; formats: CsvColumnFormat[] } {
  var rows = parseCsv(content, delimiter);
  var formats = analyzeCsvColumns(rows);
  return { html: buildTableHtml(rows, formats), formats: formats };
}

var CSV_COL_COUNT = 8;

// CSV/TSV のソース表示用の行別カラー HTML(行番号ラップ前の中身)。
// tokenizeCsvRows(parseCsv と共通のトークナイザー)が返す raw(クオート・
// エスケープされたクオートを含む生テキスト)を列ごとに Rainbow カラーで着色する。
// delimiter 自体は着色せずそのまま残す(クオート内の delimiter は列区切りとしない)。
// クオート内改行を含むセルも 1 つの span にまとまるため、テーブル表示(parseCsv)
// と同じ列割りで色が付く。renderCsvSourceHtml(初回描画)と appendChunk(チャンク
// 追記)の両方から呼ばれる。
function csvSourceInnerHtml(content: string, delimiter: string): string {
  if (!content) {
    return '';
  }
  var tokenRows = tokenizeCsvRows(content, delimiter);
  var htmlLines: string[] = [];
  for (var r = 0; r < tokenRows.length; r++) {
    var cells = tokenRows[r]!;
    var htmlParts: string[] = [];
    for (var c = 0; c < cells.length; c++) {
      var cls = 'csv-col-' + (c % CSV_COL_COUNT);
      htmlParts.push('<span class="' + cls + '">' + escapeHtml(cells[c]!.raw) + '</span>');
    }
    htmlLines.push(htmlParts.join(delimiter));
  }
  var body = htmlLines.join('\n');
  return content.endsWith('\n') ? body + '\n' : body;
}

// CSV/TSV のソース表示用 HTML。
function renderCsvSourceHtml(
  content: string,
  delimiter: string,
  showLineNumbers: boolean | undefined,
): string {
  if (!content) {
    return '<pre><code class="csv-source"></code></pre>';
  }
  var body = csvSourceInnerHtml(content, delimiter);
  if (showLineNumbers === true) {
    body = wrapWithLineNumbers(body, true);
  }
  return '<pre><code class="csv-source">' + body + '</code></pre>';
}

export {
  CSV_COL_COUNT,
  formatCsvNumber,
  unescapeCellValue,
  tokenizeCsvRows,
  parseCsv,
  csvCellHtml,
  csvRowsHtml,
  buildTableHtml,
  buildCsvTable,
  csvSourceInnerHtml,
  renderCsvSourceHtml,
};
