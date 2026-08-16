// CSV/TSV の解析と HTML 組み立て。テーブル表示(parseCsv 経由)とソース表示
// (csvSourceInnerHtml 経由)が 1 本のトークナイザーを共有する。

import { wrapWithLineNumbers } from './code-html.js';
import { escapeHtml } from './encoding.js';

// RFC 4180 準拠の状態マシンベース CSV/TSV トークナイザー。
// クオート内のデリミタ・改行・エスケープされたクオート("")を正しく扱う。
// 各セルについて、デコード済みの値(value)とソース上の生テキスト(raw、
// クオート・エスケープされたクオートを含み、クオート内の改行もそのまま残る)
// の両方を返す。parseCsv(データ用)と renderCsvSourceHtml(ソース表示用)は
// この 1 本のトークナイザーを共有し、行またぎのクオートでも同じ列境界になる。
function tokenizeCsvRows(content, delimiter) {
  if (!content) {
    return [];
  }
  var rows = [];
  var row = [];
  var value = '';
  var raw = '';
  var inQuotes = false;
  var i = 0;
  function pushField() {
    row.push({ value: value, raw: raw });
    value = '';
    raw = '';
  }
  function pushRow() {
    pushField();
    rows.push(row);
    row = [];
  }
  while (i < content.length) {
    var ch = content[i];
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
    } else {
      if (ch === '"') {
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
var CSV_ESCAPES = { n: '\n', t: '\t', r: '\r', '\\': '\\' };

function unescapeCellValue(value) {
  if (value.indexOf('\\') === -1) {
    return value;
  }
  var out = '';
  var i = 0;
  while (i < value.length) {
    var ch = value[i];
    if (ch === '\\' && i + 1 < value.length) {
      var next = value[i + 1];
      if (Object.prototype.hasOwnProperty.call(CSV_ESCAPES, next)) {
        out += CSV_ESCAPES[next];
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
function parseCsv(content, delimiter) {
  var tokenRows = tokenizeCsvRows(content, delimiter);
  var rows = [];
  for (var r = 0; r < tokenRows.length; r++) {
    var row = [];
    for (var c = 0; c < tokenRows[r].length; c++) {
      row.push(unescapeCellValue(tokenRows[r][c].value));
    }
    rows.push(row);
  }
  return rows;
}

// CSV 行の配列から <tr><td>…</td></tr> 列(文字列連結)を組み立てる。
// 各行は max(minCols, 行の列数) まで空セルでパディングし、セルは escapeHtml する。
// buildTableHtml の <tbody> とチャンク追記(render.js の appendChunk)が共有する。
function csvRowsHtml(rows, minCols) {
  var html = '';
  for (var r = 0; r < rows.length; r++) {
    var cols = Math.max(minCols, rows[r].length);
    html += '<tr>';
    for (var c = 0; c < cols; c++) {
      html += '<td>' + escapeHtml(c < rows[r].length ? rows[r][c] : '') + '</td>';
    }
    html += '</tr>';
  }
  return html;
}

// CSV 行の配列から HTML テーブル文字列を組み立てる。1行目を <thead>、残りを <tbody> にする。
// 列数が揃っていない行は空セルでパディングする。
function buildTableHtml(rows) {
  if (rows.length === 0) {
    return '';
  }
  var maxCols = 0;
  for (var r = 0; r < rows.length; r++) {
    if (rows[r].length > maxCols) {
      maxCols = rows[r].length;
    }
  }
  var html = '<table><thead><tr>';
  for (var c = 0; c < maxCols; c++) {
    html += '<th>' + escapeHtml(c < rows[0].length ? rows[0][c] : '') + '</th>';
  }
  html += '</tr></thead><tbody>';
  html += csvRowsHtml(rows.slice(1), maxCols);
  html += '</tbody></table>';
  return html;
}

var CSV_COL_COUNT = 8;

// CSV/TSV のソース表示用の行別カラー HTML(行番号ラップ前の中身)。
// tokenizeCsvRows(parseCsv と共通のトークナイザー)が返す raw(クオート・
// エスケープされたクオートを含む生テキスト)を列ごとに Rainbow カラーで着色する。
// delimiter 自体は着色せずそのまま残す(クオート内の delimiter は列区切りとしない)。
// クオート内改行を含むセルも 1 つの span にまとまるため、テーブル表示(parseCsv)
// と同じ列割りで色が付く。renderCsvSourceHtml(初回描画)と appendChunk(チャンク
// 追記)の両方から呼ばれる。
function csvSourceInnerHtml(content, delimiter) {
  if (!content) {
    return '';
  }
  var tokenRows = tokenizeCsvRows(content, delimiter);
  var htmlLines = [];
  for (var r = 0; r < tokenRows.length; r++) {
    var cells = tokenRows[r];
    var htmlParts = [];
    for (var c = 0; c < cells.length; c++) {
      var cls = 'csv-col-' + (c % CSV_COL_COUNT);
      htmlParts.push('<span class="' + cls + '">' + escapeHtml(cells[c].raw) + '</span>');
    }
    htmlLines.push(htmlParts.join(delimiter));
  }
  var body = htmlLines.join('\n');
  return content.endsWith('\n') ? body + '\n' : body;
}

// CSV/TSV のソース表示用 HTML。
function renderCsvSourceHtml(content, delimiter, showLineNumbers) {
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
  unescapeCellValue,
  tokenizeCsvRows,
  parseCsv,
  csvRowsHtml,
  buildTableHtml,
  csvSourceInnerHtml,
  renderCsvSourceHtml,
};
