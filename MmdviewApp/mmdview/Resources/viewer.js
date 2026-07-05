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

// RFC 4180 準拠の状態マシンベース CSV/TSV パーサー。
// クオート内のデリミタ・改行・エスケープされたクオート("")を正しく扱う。
function parseCsv(content, delimiter) {
  if (!content) { return []; }
  var rows = [];
  var row = [];
  var field = '';
  var inQuotes = false;
  var i = 0;
  while (i < content.length) {
    var ch = content[i];
    if (inQuotes) {
      if (ch === '"') {
        if (i + 1 < content.length && content[i + 1] === '"') {
          field += '"';
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        field += ch;
        i++;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
        i++;
      } else if (ch === delimiter) {
        row.push(field);
        field = '';
        i++;
      } else if (ch === '\r') {
        row.push(field);
        field = '';
        rows.push(row);
        row = [];
        i++;
        if (i < content.length && content[i] === '\n') { i++; }
      } else if (ch === '\n') {
        row.push(field);
        field = '';
        rows.push(row);
        row = [];
        i++;
      } else {
        field += ch;
        i++;
      }
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
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

// 1 行を delimiter で分割する。parseCsv と異なりクオート文字自体を結果に残し、
// ソース表示(Rainbow 着色)で生テキストの見た目を保つ。
function splitCsvSourceLine(line, delimiter) {
  var parts = [];
  var current = '';
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    var ch = line[i];
    if (inQuotes) {
      current += ch;
      if (ch === '"') {
        if (i + 1 < line.length && line[i + 1] === '"') {
          current += '"';
          i += 2;
        } else {
          inQuotes = false;
          i++;
        }
      } else {
        i++;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
        current += ch;
        i++;
      } else if (ch === delimiter) {
        parts.push(current);
        current = '';
        i++;
      } else {
        current += ch;
        i++;
      }
    }
  }
  parts.push(current);
  return parts;
}

// CSV/TSV のソース表示用 HTML。行ごとに列を Rainbow カラーで着色し、
// delimiter 自体は着色せずそのまま残す(クオート内の delimiter は列区切りとしない)。
function renderCsvSourceHtml(content, delimiter) {
  if (!content) { return '<pre><code class="csv-source"></code></pre>'; }
  var lines = content.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') { lines.pop(); }
  var htmlLines = [];
  for (var l = 0; l < lines.length; l++) {
    var line = lines[l];
    if (line.charAt(line.length - 1) === '\r') { line = line.slice(0, -1); }
    var parts = splitCsvSourceLine(line, delimiter);
    var htmlParts = [];
    for (var c = 0; c < parts.length; c++) {
      var cls = 'csv-col-' + (c % CSV_COL_COUNT);
      htmlParts.push('<span class="' + cls + '">' + escapeHtml(parts[c]) + '</span>');
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
    parseCsv: parseCsv,
    buildTableHtml: buildTableHtml,
    renderCsvSourceHtml: renderCsvSourceHtml,
    CSV_COL_COUNT: CSV_COL_COUNT,
  };
}
