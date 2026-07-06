// viewer.js — テスト可能な純粋ロジック

var ZOOM_MIN = 0.5;
var ZOOM_MAX = 2.0;
var ZOOM_STEP = 0.25;
var ZOOM_DEFAULT = 1;
var BASE_SCALE = 0.75;
// ダイアグラム個別ズームの上限。全体ズーム(ZOOM_MAX)より広く取り、細部の確認に使う。
var DIAGRAM_ZOOM_MAX = 3.0;

function clampZoom(z, max) {
  if (max === undefined) { max = ZOOM_MAX; }
  return Math.max(ZOOM_MIN, Math.min(max, z));
}

function stepZoom(current, delta, max) {
  return clampZoom(Math.round((current + delta) * 100) / 100, max);
}

function wheelZoom(current, deltaY, max) {
  return clampZoom(Math.round((current - deltaY * 0.01) * 1000) / 1000, max);
}

function zoomLabel(zoom) {
  return Math.round(zoom * 100) + '%';
}

function effectiveZoom(zoom) {
  return zoom;
}

// .diagram-zoom-scroll(枠)の高さ。ズーム後の実寸とビューポート上限の小さい方。
// naturalHeight は 100% 時のレイアウト px。上限は .viewer の上下 padding(32px×2)を
// 差し引いたビューポート高で、レイアウト px は祖先の CSS zoom の影響を受けないため
// 実ピクセルの viewportHeight を全体ズームぶん割り戻して比較する。
function diagramScrollHeight(naturalHeight, diagramZoom, viewportHeight, globalZoom) {
  var viewportCap = (viewportHeight - 64) / effectiveZoom(globalZoom);
  return Math.min(naturalHeight * diagramZoom * BASE_SCALE, viewportCap);
}

function parseStoredZoom(raw) {
  var z = parseFloat(raw);
  return isNaN(z) ? ZOOM_DEFAULT : z;
}

var MACOS_DEFAULT_BODY = 13;
var WEB_BASELINE = 16;

function markdownFontSize(raw) {
  var s = parseFloat(raw);
  if (isNaN(s) || s <= 0) { return WEB_BASELINE; }
  return WEB_BASELINE * (s / MACOS_DEFAULT_BODY);
}

// OS のカラースキームに対応する mermaid テーマ名を返す。
// prefers-color-scheme: dark のとき 'dark'、それ以外は 'default'。
function mermaidTheme(prefersDark) {
  return prefersDark ? 'dark' : 'default';
}

// class 属性に埋め込める文字(英数字・_・+・-)だけを残す。
// hljs.getLanguage() を通過した言語名しか来ないはずだが、防御的に二重チェックする。
function sanitizeLang(lang) {
  return String(lang).replace(/[^\w+-]/g, '');
}

// Markdown コードブロックのシンタックスハイライト。
// markdown-it の highlight オプションから呼ばれる。hljs は依存注入
// (viewer.html ではグローバル hljs、テストでは npm の highlight.js)。
// 返り値が '<pre' で始まる場合 markdown-it はそれをそのまま採用し、
// '' の場合はデフォルトのエスケープ済み <pre><code> にフォールバックする。
function highlightCode(hljs, str, lang) {
  if (hljs && lang && hljs.getLanguage(lang)) {
    try {
      var result = hljs.highlight(str, { language: lang, ignoreIllegals: true });
      return '<pre><code class="hljs language-' + sanitizeLang(lang) + '">'
        + result.value + '</code></pre>';
    } catch (e) {
      // フォールバックへ
    }
  }
  return '';
}

// HTML 特殊文字をエスケープする(DOM 非依存の純粋関数)。
// viewer.html の _escapeHtml は DOM を使うため Node テストできない。
function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// 単一コードファイル全文のハイライト HTML を組み立てる。
// highlightCode() を再利用し、未対応言語・hljs 不在・例外時は
// エスケープ済みプレーン <pre><code> にフォールバックする。
function renderCodeHtml(hljs, str, lang) {
  var highlighted = highlightCode(hljs, str, lang);
  if (highlighted) { return highlighted; }
  return '<pre><code>' + escapeHtml(str) + '</code></pre>';
}

// RFC 4180 準拠の状態マシンベース CSV/TSV トークナイザー。
// クオート内のデリミタ・改行・エスケープされたクオート("")を正しく扱う。
// 各セルについて、デコード済みの値(value)とソース上の生テキスト(raw、
// クオート・エスケープされたクオートを含み、クオート内の改行もそのまま残る)
// の両方を返す。parseCsv(データ用)と renderCsvSourceHtml(ソース表示用)は
// この 1 本のトークナイザーを共有し、行またぎのクオートでも同じ列境界になる。
function tokenizeCsvRows(content, delimiter) {
  if (!content) { return []; }
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
        if (i + 1 < content.length && content[i + 1] === '"') {
          value += '"';
          raw += '""';
          i += 2;
        } else {
          raw += ch;
          inQuotes = false;
          i++;
        }
      } else {
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
        pushRow();
        i++;
        if (i < content.length && content[i] === '\n') { i++; }
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
  if (value !== '' || raw !== '' || row.length > 0) {
    pushRow();
  }
  return rows;
}

// tokenizeCsvRows のセルから value だけを取り出した、データ用の行配列。
function parseCsv(content, delimiter) {
  var tokenRows = tokenizeCsvRows(content, delimiter);
  var rows = [];
  for (var r = 0; r < tokenRows.length; r++) {
    var row = [];
    for (var c = 0; c < tokenRows[r].length; c++) {
      row.push(tokenRows[r][c].value);
    }
    rows.push(row);
  }
  return rows;
}

// CSV 行の配列から HTML テーブル文字列を組み立てる。1行目を <thead>、残りを <tbody> にする。
// 列数が揃っていない行は空セルでパディングする。
function buildTableHtml(rows) {
  if (rows.length === 0) { return ''; }
  var maxCols = 0;
  for (var r = 0; r < rows.length; r++) {
    if (rows[r].length > maxCols) { maxCols = rows[r].length; }
  }
  var html = '<table><thead><tr>';
  for (var c = 0; c < maxCols; c++) {
    html += '<th>' + escapeHtml(c < rows[0].length ? rows[0][c] : '') + '</th>';
  }
  html += '</tr></thead><tbody>';
  for (r = 1; r < rows.length; r++) {
    html += '<tr>';
    for (c = 0; c < maxCols; c++) {
      html += '<td>' + escapeHtml(c < rows[r].length ? rows[r][c] : '') + '</td>';
    }
    html += '</tr>';
  }
  html += '</tbody></table>';
  return html;
}

var CSV_COL_COUNT = 8;

// CSV/TSV のソース表示用 HTML。tokenizeCsvRows(parseCsv と共通のトークナイザー)
// が返す raw(クオート・エスケープされたクオートを含む生テキスト)を列ごとに
// Rainbow カラーで着色する。delimiter 自体は着色せずそのまま残す(クオート内の
// delimiter は列区切りとしない)。クオート内改行を含むセルも 1 つの span に
// まとまるため、テーブル表示(parseCsv)と同じ列割りで色が付く。
function renderCsvSourceHtml(content, delimiter) {
  if (!content) { return '<pre><code class="csv-source"></code></pre>'; }
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
  return '<pre><code class="csv-source">' + htmlLines.join('\n') + '</code></pre>';
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    ZOOM_MIN: ZOOM_MIN,
    ZOOM_MAX: ZOOM_MAX,
    ZOOM_STEP: ZOOM_STEP,
    ZOOM_DEFAULT: ZOOM_DEFAULT,
    BASE_SCALE: BASE_SCALE,
    DIAGRAM_ZOOM_MAX: DIAGRAM_ZOOM_MAX,
    MACOS_DEFAULT_BODY: MACOS_DEFAULT_BODY,
    WEB_BASELINE: WEB_BASELINE,
    clampZoom: clampZoom,
    stepZoom: stepZoom,
    wheelZoom: wheelZoom,
    zoomLabel: zoomLabel,
    effectiveZoom: effectiveZoom,
    parseStoredZoom: parseStoredZoom,
    mermaidTheme: mermaidTheme,
    sanitizeLang: sanitizeLang,
    highlightCode: highlightCode,
    diagramScrollHeight: diagramScrollHeight,
    markdownFontSize: markdownFontSize,
    escapeHtml: escapeHtml,
    renderCodeHtml: renderCodeHtml,
    tokenizeCsvRows: tokenizeCsvRows,
    parseCsv: parseCsv,
    buildTableHtml: buildTableHtml,
    renderCsvSourceHtml: renderCsvSourceHtml,
    CSV_COL_COUNT: CSV_COL_COUNT,
  };
}
