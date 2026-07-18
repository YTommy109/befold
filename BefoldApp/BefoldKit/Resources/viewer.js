// viewer.js — テスト可能な純粋ロジック

// Space の1ページスクロール量。表示領域(clientHeight)の90%とし、
// ウィンドウサイズが変わっても常に「ほぼ1画面分」になるようにする。
var PAGE_SCROLL_RATIO = 0.9;
// 行送り(矢印/vimキー)で行の高さを取得できなかった場合のフォールバック値。
var DEFAULT_LINE_SCROLL_STEP = 24;

// ページ単位のスクロール量(px)。表示領域の高さに対する比率で決まるため、
// ウィンドウサイズによらず「ほぼ1画面分」になる。
function pageScrollStep(clientHeight) {
  return clientHeight * PAGE_SCROLL_RATIO;
}

// 半ページ単位のスクロール量(px)。Shift 修飾時に使う。
function halfPageScrollStep(clientHeight) {
  return pageScrollStep(clientHeight) / 2;
}

// 行単位のスクロール量(px)。CSS の line-height 計算値(例: "22.4px")を渡す。
// 取得できない/数値でない場合は fallback を返す。
function lineScrollStep(lineHeightPx, fallback) {
  var lh = parseFloat(lineHeightPx);
  return isNaN(lh) ? fallback : lh;
}

// キーボードスクロールのキー→動作解決。Safari に合わせ、Space=下/Shift+Space=上(バックスクロール)は
// 同じフルページ量のまま方向だけ反転させ、矢印/vim キーは Shift でハーフページに切り替える。
// Backspace はバックスクロールとして扱わない(未対応キーとして null を返す)。
// ホスト機能フラグ(Swift 側が window._mmdHostFeatures として注入)を読む。
// 未注入、またはキー未指定の場合はその機能が有効であるとみなす
// (フラグを送らないホストは全機能サポートとして扱う後方互換のため)。
function isHostFeatureEnabled(hostFeatures, key) {
  if (!hostFeatures) { return true; }
  return hostFeatures[key] !== false;
}

function resolveScrollKey(key, shiftKey) {
  if (key === ' ') {
    return { down: !shiftKey, amount: 'page' };
  }
  var down;
  if (key === 'ArrowDown' || key === 'j') {
    down = true;
  } else if (key === 'ArrowUp' || key === 'k') {
    down = false;
  } else {
    return null;
  }
  return { down: down, amount: shiftKey ? 'half' : 'line' };
}

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

// ラスター画像の初期フィットサイズ。アスペクト比を保ったまま利用可能領域に
// 収まるよう縮小する(ナチュラルサイズより拡大はしない)。戻り値は px の
// 実数値(% ではない)。% で表現すると祖先の #diagram-wrap に適用される
// CSS zoom(全体ズーム)が相殺されてしまい、Cmd+/Cmd-/Cmd0 が効かなくなる
// (diagramScrollHeight と同様、レイアウト px は祖先の CSS zoom の影響を
// 受けないため、px 実数値であれば zoom がそのまま乗算されて効く)。
function imageFitSize(naturalWidth, naturalHeight, availWidth, availHeight) {
  if (naturalWidth <= 0 || naturalHeight <= 0 || availWidth <= 0 || availHeight <= 0) {
    return { width: naturalWidth, height: naturalHeight };
  }
  var scale = Math.min(1, availWidth / naturalWidth, availHeight / naturalHeight);
  return { width: naturalWidth * scale, height: naturalHeight * scale };
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

// markdown-it の validateLink 置き換え。既定は data:image/(gif|png|jpeg|webp)
// のみ許可するが、MarkdownImageEmbedder が生成する svg+xml / bmp / x-icon の
// data URI も表示できるよう data:image/* を全許可する。CSP は img-src 'self' data:
// のため data:image の <img> 表示は安全(SVG も <img> 経由ではスクリプト非実行)。
// javascript:/vbscript:/file:/画像以外の data: は既定どおり拒否し XSS を防ぐ。
function isSafeLinkURL(url) {
  var str = String(url).trim().toLowerCase();
  if (/^data:image\//.test(str)) { return true; }
  return !/^(vbscript|javascript|file|data):/.test(str);
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

// HTML を行ごとに分割し、各行を自己完結な HTML にする(未クローズ span が
// 後続行を壊すのを防ぐ)。highlight.js はブロックコメント等で改行をまたぐ
// <span> を出力するため、行末で開いたままの span を閉じ、次の行の先頭で
// 開き直す。buildLineNumberRows(行番号付与) と codeChunkInnerHtml
// (チャンク境界の前方文脈を落とす処理)の双方から使う。
function reflowSpanBalancedLines(codeHtml) {
  var lines = codeHtml.split('\n');
  // 末尾が空行の場合は除去する(highlight.js が末尾に \n を付けることがある)
  if (lines.length > 1 && lines[lines.length - 1] === '') {
    lines.pop();
  }
  var openSpans = [];
  var result = [];
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i] || '';
    var reopen = openSpans.join('');
    var tagRe = /<span\b[^>]*>|<\/span>/g;
    var tag;
    while ((tag = tagRe.exec(line)) !== null) {
      if (tag[0] === '</span>') {
        openSpans.pop();
      } else {
        openSpans.push(tag[0]);
      }
    }
    var close = '';
    for (var j = 0; j < openSpans.length; j++) {
      close += '</span>';
    }
    result.push(reopen + line + close);
  }
  return result;
}

// 行ごとに分割した HTML を行番号付き <tr> 列(文字列連結)に組み立てる。
// 行番号は startLine から振る(チャンク追記では既存行数 + 1 を渡す)。
function buildLineNumberRows(codeHtml, startLine) {
  var lines = reflowSpanBalancedLines(codeHtml);
  var rows = '';
  for (var i = 0; i < lines.length; i++) {
    rows += '<tr><td class="line-number">' + (startLine + i)
      + '</td><td class="line-content">' + lines[i] + '</td></tr>';
  }
  return rows;
}

// コード全文を行番号付き <table> で包む(初回描画用)。
function wrapWithLineNumbers(codeHtml) {
  return '<table class="code-table">' + buildLineNumberRows(codeHtml, 1) + '</table>';
}

// 単一コードファイル全文のハイライト HTML を組み立てる。
// highlightCode() を再利用し、未対応言語・hljs 不在・例外時は
// エスケープ済みプレーン <pre><code> にフォールバックする。
// showLineNumbers が true のとき、内容を行番号付き <table> で包む。
function renderCodeHtml(hljs, str, lang, showLineNumbers) {
  var highlighted = highlightCode(hljs, str, lang);
  if (showLineNumbers) {
    if (highlighted) {
      // <pre><code ...>CONTENT</code></pre> の CONTENT だけを行番号テーブルで包む
      var match = highlighted.match(/^(<pre><code[^>]*>)([\s\S]*)(<\/code><\/pre>)$/);
      if (match) {
        return match[1] + wrapWithLineNumbers(match[2]) + match[3];
      }
    }
    return '<pre><code>' + wrapWithLineNumbers(escapeHtml(str)) + '</code></pre>';
  }
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

// CSV 行の配列から <tr><td>…</td></tr> 列(文字列連結)を組み立てる。
// 各行は max(minCols, 行の列数) まで空セルでパディングし、セルは escapeHtml する。
// buildTableHtml の <tbody> とチャンク追記(viewer.html の appendChunk)が共有する。
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
// 追記、viewer.html)の両方から呼ばれる。
function csvSourceInnerHtml(content, delimiter) {
  if (!content) { return ''; }
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
  if (!content) { return '<pre><code class="csv-source"></code></pre>'; }
  var body = csvSourceInnerHtml(content, delimiter);
  if (showLineNumbers) {
    body = wrapWithLineNumbers(body);
  }
  return '<pre><code class="csv-source">' + body + '</code></pre>';
}

// --- Find ---

// クエリと3トグル(caseSensitive / wholeWord / useRegex)から RegExp を組み立てる。
// クエリが空、または正規表現として不正な場合は null を返す(呼び出し側はエラー表示に切り替える)。
function buildFindRegExp(query, options) {
  if (!query) { return null; }
  var source = options.useRegex ? query : query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (options.wholeWord) { source = '\\b(?:' + source + ')\\b'; }
  var flags = 'g' + (options.caseSensitive ? '' : 'i');
  try {
    return new RegExp(source, flags);
  } catch (e) {
    return null;
  }
}

// チャンク追記用のコード HTML。highlightCode の <pre><code…> ラッパーを剥がした
// 中身だけを返し、ハイライト不可(hljs 不在・未対応言語)の場合はエスケープ済み
// プレーンテキストにフォールバックする。DOM への挿入は viewer.html の appendChunk が行う。
// contextStr(改行終端済みの直前チャンクの末尾行、任意)を渡すと、
// contextStr + str をまとめて highlight.js にかけてから contextStr 分の
// 行を取り除いて返す。highlight.js はチャンクをまたいだ継続状態を持たない
// (v11 で continuation 引数は廃止済み)ため、ブロックコメントや複数行文字列が
// チャンク境界をまたぐと、文脈なしでは境界直後が通常コードとして誤ハイライト
// される。境界前の数百行を文脈として与えることで、hljs が正しい字句状態
// (コメント内/文字列内など)を自力で再構築できるようにする。
function codeChunkInnerHtml(hljs, str, lang, contextStr) {
  if (contextStr) {
    var highlightedWithContext = highlightCode(hljs, contextStr + str, lang);
    if (highlightedWithContext) {
      var inner = highlightedWithContext.replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '');
      var lines = reflowSpanBalancedLines(inner);
      var contextLineCount = (contextStr.match(/\n/g) || []).length;
      var body = lines.slice(contextLineCount).join('\n');
      return str.endsWith('\n') ? body + '\n' : body;
    }
  }
  var highlighted = highlightCode(hljs, str, lang);
  if (highlighted) {
    return highlighted.replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '');
  }
  return escapeHtml(str);
}

// str の末尾から改行終端済みの行を最大 maxLines 行分切り出す(文脈として
// highlight.js に渡す用)。全文をスキャンせず末尾から lastIndexOf を
// maxLines 回たどるだけなので、str が巨大でもコストは maxLines に比例する。
function lastLines(str, maxLines) {
  if (str.length === 0) { return ''; }
  var idx = str.length - 1;
  var count = 0;
  while (count < maxLines) {
    var nl = str.lastIndexOf('\n', idx - 1);
    if (nl === -1) { return str; }
    idx = nl;
    count++;
  }
  return str.slice(idx + 1);
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    PAGE_SCROLL_RATIO: PAGE_SCROLL_RATIO,
    DEFAULT_LINE_SCROLL_STEP: DEFAULT_LINE_SCROLL_STEP,
    pageScrollStep: pageScrollStep,
    halfPageScrollStep: halfPageScrollStep,
    lineScrollStep: lineScrollStep,
    resolveScrollKey: resolveScrollKey,
    isHostFeatureEnabled: isHostFeatureEnabled,
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
    isSafeLinkURL: isSafeLinkURL,
    highlightCode: highlightCode,
    diagramScrollHeight: diagramScrollHeight,
    imageFitSize: imageFitSize,
    markdownFontSize: markdownFontSize,
    escapeHtml: escapeHtml,
    renderCodeHtml: renderCodeHtml,
    wrapWithLineNumbers: wrapWithLineNumbers,
    buildLineNumberRows: buildLineNumberRows,
    reflowSpanBalancedLines: reflowSpanBalancedLines,
    csvRowsHtml: csvRowsHtml,
    codeChunkInnerHtml: codeChunkInnerHtml,
    lastLines: lastLines,
    tokenizeCsvRows: tokenizeCsvRows,
    parseCsv: parseCsv,
    buildTableHtml: buildTableHtml,
    renderCsvSourceHtml: renderCsvSourceHtml,
    csvSourceInnerHtml: csvSourceInnerHtml,
    CSV_COL_COUNT: CSV_COL_COUNT,
    buildFindRegExp: buildFindRegExp,
  };
}
