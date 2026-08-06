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

// markdown-it の html:true が通す生 HTML(md.render() 出力)を innerHTML 適用前にサニタイズする。
// purify は依存注入(viewer.html ではグローバル DOMPurify、テストでは jsdom 上に構築した DOMPurify)。
// 自前の正規表現(on* 属性除去等)は個別のバイパス手法ごとにパッチを重ねる対症療法になるため、
// 実績のある DOMPurify にサニタイズそのものを委譲する。
function sanitizeRenderedHtml(purify, html) {
  return purify.sanitize(html);
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

// href がローカルパス候補か。#アンカー・http(s) 等スキーム付きは除外する。
// file.md:12 が scheme="file.md" と誤解釈される都合、ドットを含むスキームは許可する。
function isLocalPathHref(href) {
  if (!href) { return false; }
  if (href.charAt(0) === '#') { return false; }
  var m = href.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*):/);
  if (m && m[1].indexOf('.') === -1) { return false; } // http:, mailto:, tel: 等
  return true;
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

// SVG テキストを <img> の src に使える data URI にする。
// btoa は Latin-1 しか扱えないため、encodeURIComponent + unescape で
// UTF-8 バイト列を 1 バイト 1 文字の文字列へ均してから base64 化する。
function svgDataURI(svgText) {
  return 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svgText)));
}

// base64 の画像データを <img> の src に使える data URI にする。
// mimeType は Swift 側(ViewerBridge)が渡す実際の MIME。未指定時は
// 従来どおり image/png とみなす。
function imageDataURI(base64, mimeType) {
  return 'data:' + (mimeType || 'image/png') + ';base64,' + base64;
}

// base64 文字列をバイト列へ復号する(PDF の Blob 生成用)。
function base64ToBytes(base64) {
  var binary = atob(base64);
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
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

// インデントガイド(縦線)の桁幅。ガイドはこの桁数ごとに 1 本引く。
// style.css の tab-size と必ず一致させること。
var CODE_TAB_SIZE = 4;

// プレーンな文字列の先頭空白をタブ幅換算の桁数に変換する。タブは次の
// tab-stop まで、スペースは +1。非空白に達したら打ち切る。
function indentColumns(text, tabSize) {
  var cols = 0;
  for (var i = 0; i < text.length; i++) {
    var ch = text[i];
    if (ch === '\t') {
      cols += tabSize - (cols % tabSize);
    } else if (ch === ' ') {
      cols += 1;
    } else {
      break;
    }
  }
  return cols;
}

// ハイライト済みの 1 行 HTML から、インデントガイド描画用の情報を求める。
// reflow が前置する開き <span> タグを飛ばしてから先頭空白を桁数換算する。
// cols=先頭インデント桁数、depth=引くガイド本数(floor(cols/tabSize))。
// 非空白を含まない行(空行・空白のみ)はガイドを引かない(depth 0)。
function leadingIndentInfo(lineHtml, tabSize) {
  var rest = lineHtml;
  var openTag = /^<span\b[^>]*>/;
  var match;
  while ((match = openTag.exec(rest)) !== null) {
    rest = rest.slice(match[0].length);
  }
  var cols = 0;
  var hasContent = false;
  for (var i = 0; i < rest.length; i++) {
    var ch = rest[i];
    if (ch === '\t') {
      cols += tabSize - (cols % tabSize);
    } else if (ch === ' ') {
      cols += 1;
    } else {
      hasContent = true;
      break;
    }
  }
  if (!hasContent) { return { cols: 0, depth: 0 }; }
  return { cols: cols, depth: Math.floor(cols / tabSize) };
}

// 1 行分の <td class="line-content"> を組み立てる。インデントがある行には
// ハンギングインデントとガイド描画用の CSS 変数を付与する(depth 0 の行は付けない)。
function lineContentCell(lineHtml) {
  var info = leadingIndentInfo(lineHtml, CODE_TAB_SIZE);
  var style = info.depth > 0
    ? ' style="--indent-cols:' + info.cols + ';--indent-depth:' + info.depth + '"'
    : '';
  return '<td class="line-content"' + style + '>' + lineHtml + '</td>';
}

// 行ごとに分割した HTML を <tr> 列(文字列連結)に組み立てる。
// 行番号セルは showLineNumbers === true のときだけ付ける(省略時は付けない)。
// この「明示的に true のときだけ」という規則を行番号系の関数すべてで共有する
// (省略時の解釈が関数ごとに違うと、呼び出し漏れが表示差になって現れるため)。
// 行番号は startLine から振る(チャンク追記では既存行数 + 1 を渡す)。
function buildLineNumberRows(codeHtml, startLine, showLineNumbers) {
  var withNumbers = showLineNumbers === true;
  var lines = reflowSpanBalancedLines(codeHtml);
  var rows = '';
  for (var i = 0; i < lines.length; i++) {
    var numberCell = withNumbers
      ? '<td class="line-number">' + (startLine + i) + '</td>'
      : '';
    rows += '<tr>' + numberCell + lineContentCell(lines[i]) + '</tr>';
  }
  return rows;
}

// コード全文を行単位の <table> で包む(初回描画用)。
// 行番号有無に関わらず常にこの行単位構造を使い、インデントガイドを描けるようにする。
function wrapWithLineNumbers(codeHtml, showLineNumbers) {
  return '<table class="code-table">'
    + buildLineNumberRows(codeHtml, 1, showLineNumbers) + '</table>';
}

// 単一コードファイル全文のハイライト HTML を組み立てる。
// highlightCode() を再利用し、未対応言語・hljs 不在・例外時は
// エスケープ済みプレーンへフォールバックする。行番号有無に関わらず、内容は常に
// 行単位 <table> で包む(インデントガイドを両パスで描くため)。
function renderCodeHtml(hljs, str, lang, showLineNumbers) {
  // 省略時は行番号なし(従来の既定)。行番号セルの有無だけが変わり、行単位構造は共通。
  var withNumbers = showLineNumbers === true;
  var highlighted = highlightCode(hljs, str, lang);
  if (highlighted) {
    // <pre><code ...>CONTENT</code></pre> の CONTENT だけを行単位テーブルで包む
    var match = highlighted.match(/^(<pre><code[^>]*>)([\s\S]*)(<\/code><\/pre>)$/);
    if (match) {
      return match[1] + wrapWithLineNumbers(match[2], withNumbers) + match[3];
    }
  }
  return '<pre><code>' + wrapWithLineNumbers(escapeHtml(str), withNumbers) + '</code></pre>';
}

// ── git 差分表示 ──

// unified diff の 1 ハンクのヘッダー。`@@ -12,7 +12,9 @@ ...` の数値部だけを見る。
var DIFF_HUNK_HEADER = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;

// unified diff をファイル → ハンク → 行の構造へ分解する。
// 行の種別は 'context' / 'add' / 'del' の 3 つで、旧側・新側の行番号を各行に付ける
// (描画側で 2 本のガターに出すため。片側にしか無い行はもう一方が null)。
// `\ No newline at end of file` は直前の行に対する注記であり、行としては数えない。
function parseUnifiedDiff(text) {
  var files = [];
  var file = null;
  var hunk = null;
  var oldNumber = 0;
  var newNumber = 0;
  var lines = String(text == null ? '' : text).split('\n');
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.indexOf('diff --git ') === 0) {
      file = { oldPath: null, newPath: null, isBinary: false, hunks: [] };
      files.push(file);
      hunk = null;
      continue;
    }
    if (file === null) { continue; }
    // ヘッダ類はハンクが始まる前にしか現れない。ハンク内で同じ接頭辞を持つ行は
    // 本文（`-- ` で始まる SQL コメントの削除など）なので、ここで消費しない。
    if (hunk === null) {
      if (line.indexOf('--- ') === 0) { file.oldPath = diffPath(line.slice(4)); continue; }
      if (line.indexOf('+++ ') === 0) { file.newPath = diffPath(line.slice(4)); continue; }
      if (line.indexOf('Binary files ') === 0 || line.indexOf('GIT binary patch') === 0) {
        file.isBinary = true;
        continue;
      }
    }
    var header = line.match(DIFF_HUNK_HEADER);
    if (header) {
      oldNumber = parseInt(header[1], 10);
      newNumber = parseInt(header[3], 10);
      hunk = { oldStart: oldNumber, newStart: newNumber, lines: [] };
      file.hunks.push(hunk);
      continue;
    }
    if (hunk === null) { continue; }
    if (line.indexOf('\\') === 0) { continue; }
    var marker = line.charAt(0);
    var body = line.slice(1);
    if (marker === '+') {
      hunk.lines.push({ type: 'add', text: body, oldNumber: null, newNumber: newNumber });
      newNumber += 1;
    } else if (marker === '-') {
      hunk.lines.push({ type: 'del', text: body, oldNumber: oldNumber, newNumber: null });
      oldNumber += 1;
    } else if (marker === ' ') {
      // 空文字列の行は本文ではない(git は空の文脈行も先頭 1 文字の空白を付けて出す)。
      // 末尾の改行で生じる空要素を文脈行として数えると、以降の行番号が 1 つずれる。
      hunk.lines.push({ type: 'context', text: body, oldNumber: oldNumber, newNumber: newNumber });
      oldNumber += 1;
      newNumber += 1;
    }
  }
  return files;
}

// `a/path/to/file.swift` の接頭辞を落とす。`/dev/null` はそのまま返す(新規・削除の印)。
function diffPath(raw) {
  var path = raw.split('\t')[0];
  if (path === '/dev/null') { return path; }
  return path.replace(/^[ab]\//, '');
}

// 添字の並び(旧側 or 新側)の本文をまとめてハイライトし、行ごとの HTML 配列で返す。
// 1 行ずつ hljs へ渡すとブロックコメントや複数行文字列で字句状態が切れるため、
// 片側分をまとめて 1 ブロックとして扱う(行をまたぐトークンは側の中で閉じる)。
// reflowSpanBalancedLines は highlight.js が付ける末尾の \n を落とす作りなので、
// 最終行が空行(末尾が空行のファイル)だと本物の行まで消える。足りない分は空で埋める。
function highlightedSideLines(hljs, lines, indexes, lang) {
  var texts = [];
  for (var i = 0; i < indexes.length; i++) { texts.push(lines[indexes[i]].text); }
  var joined = texts.join('\n');
  var lineHtmls = null;
  var highlighted = highlightCode(hljs, joined, lang);
  if (highlighted) {
    var match = highlighted.match(/^<pre><code[^>]*>([\s\S]*)<\/code><\/pre>$/);
    if (match) { lineHtmls = reflowSpanBalancedLines(match[1]); }
  }
  if (lineHtmls === null) { lineHtmls = reflowSpanBalancedLines(escapeHtml(joined)); }
  while (lineHtmls.length < indexes.length) { lineHtmls.push(''); }
  return lineHtmls.slice(0, indexes.length);
}

// ハンク 1 つ分をハイライトし、行ごとの HTML 配列で返す。
// 旧版(文脈行 + 削除行)と新版(文脈行 + 追加行)を別々にハイライトする。
// 両者を 1 ブロックに連結すると、変更行の旧版と新版が隣接して字句状態が壊れ
// (文字列リテラルやコメントの開始・終了が二重になる)、以降の行の色が総崩れになる。
// GitDiffReader は -U1000000 でファイル全体を 1 ハンクにするため、崩れは末尾まで及ぶ。
// 戻り値は必ず hunk.lines と同じ長さにする。呼び出し側は行 HTML を添字で引く
// (左右分割は対の添字で引く)ため、長さがずれると undefined を掴んで落ちる。
// 文脈行は両側に現れるが、色は同じになるので新版側の結果を採用する。
function highlightedDiffLines(hljs, hunk, lang) {
  var lines = hunk.lines;
  var oldIndexes = [];
  var newIndexes = [];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].type !== 'add') { oldIndexes.push(i); }
    if (lines[i].type !== 'del') { newIndexes.push(i); }
  }
  var result = [];
  for (var n = 0; n < lines.length; n++) { result.push(''); }
  var oldHtmls = highlightedSideLines(hljs, lines, oldIndexes, lang);
  for (var o = 0; o < oldIndexes.length; o++) { result[oldIndexes[o]] = oldHtmls[o]; }
  var newHtmls = highlightedSideLines(hljs, lines, newIndexes, lang);
  for (var w = 0; w < newIndexes.length; w++) { result[newIndexes[w]] = newHtmls[w]; }
  return result;
}

// 1 行分の <tr>。種別クラスと、色に依存しない記号セルを必ず持たせる
// (背景色だけだと色覚特性やハイコントラスト設定で追加・削除を区別できない)。
function diffRow(line, lineHtml, showLineNumbers) {
  var marker = line.type === 'add' ? '+' : (line.type === 'del' ? '-' : ' ');
  var numbers = '';
  if (showLineNumbers === true) {
    numbers = '<td class="line-number diff-old">' + (line.oldNumber === null ? '' : line.oldNumber)
      + '</td><td class="line-number diff-new">' + (line.newNumber === null ? '' : line.newNumber)
      + '</td>';
  }
  return '<tr class="diff-line diff-' + line.type + '">' + numbers
    + '<td class="diff-marker" aria-hidden="true">' + marker + '</td>'
    + lineContentCell(lineHtml) + '</tr>';
}

// ハンクの区切り行。`@@ -1,3 +1,4 @@` の位置情報は出さず、連続していない範囲の
// 境目だけを示す。どこの行かは両側のガターが持っているため、位置情報は重複した情報になる。
// 桁数はレイアウトと行番号ガターの有無で変わるため、colspan は呼び出し側が決める。
function diffHunkSeparatorRow(colspan) {
  return '<tr class="diff-hunk" aria-hidden="true">'
    + '<td class="diff-hunk-separator" colspan="' + colspan + '"></td></tr>';
}

// unified diff を 1 列(インライン)の差分表示 HTML へ組み立てる。
// 既存のソース表示と同じ <table class="code-table"> 構造に載せるため、行番号・
// インデントガイド・シンタックスハイライト・検索がそのまま効く。
// 差分が 1 つも無ければ空文字列を返し、呼び出し側は通常のソース表示へ戻す。
function renderInlineDiffHtml(hljs, diffText, lang, showLineNumbers) {
  var files = parseUnifiedDiff(diffText);
  var rows = '';
  for (var f = 0; f < files.length; f++) {
    var hunks = files[f].hunks;
    for (var h = 0; h < hunks.length; h++) {
      var hunk = hunks[h];
      var lineHtmls = highlightedDiffLines(hljs, hunk, lang);
      // 先頭には区切りを置かない(境目が無いところに帯だけが出るため)。
      if (rows !== '') { rows += diffHunkSeparatorRow(showLineNumbers === true ? 4 : 2); }
      for (var i = 0; i < hunk.lines.length; i++) {
        rows += diffRow(hunk.lines[i], lineHtmls[i], showLineNumbers);
      }
    }
  }
  if (rows === '') { return ''; }
  return '<pre><code class="hljs"><table class="code-table diff-table">' + rows + '</table></code></pre>';
}

// 左右分割表示のために、ハンクの行を「旧側 / 新側」の対へ畳む。
// 連続する削除と追加は同じ行に並べる(エディタの差分表示と同じ見え方)。
// 返すのは行オブジェクトではなく `hunk.lines` の添字。ハイライト済み HTML を
// 添字で引くため(ハンク単位でまとめてハイライトする方針を崩さない)。
function pairDiffLines(lines) {
  var pairs = [];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].type === 'context') {
      pairs.push({ left: i, right: i });
      i += 1;
      continue;
    }
    var dels = [];
    var adds = [];
    while (i < lines.length && lines[i].type === 'del') { dels.push(i); i += 1; }
    while (i < lines.length && lines[i].type === 'add') { adds.push(i); i += 1; }
    var count = Math.max(dels.length, adds.length);
    for (var k = 0; k < count; k++) {
      pairs.push({
        left: k < dels.length ? dels[k] : null,
        right: k < adds.length ? adds[k] : null,
      });
    }
  }
  return pairs;
}

// 左右分割の片側 1 マス分(行番号・記号・内容)。行が無い側は空マスで埋める
// (対応する行が無いことを見せるため、行自体を詰めない)。
function diffSideCells(line, lineHtml, showLineNumbers, side) {
  var numberClass = side === 'left' ? 'diff-old' : 'diff-new';
  if (line === null) {
    var emptyNumber = showLineNumbers === true
      ? '<td class="line-number ' + numberClass + '"></td>' : '';
    return emptyNumber + '<td class="diff-marker diff-empty" aria-hidden="true"></td>'
      + '<td class="line-content diff-empty"></td>';
  }
  var number = showLineNumbers === true
    ? '<td class="line-number ' + numberClass + '">'
      + (side === 'left' ? line.oldNumber : line.newNumber) + '</td>'
    : '';
  var marker = line.type === 'add' ? '+' : (line.type === 'del' ? '-' : ' ');
  return number + '<td class="diff-marker" aria-hidden="true">' + marker + '</td>'
    + lineContentCell(lineHtml);
}

// 左右分割(side-by-side)の差分表示 HTML。インライン表示と同じ code-table 構造・
// 同じハイライト結果を使い、行の並べ方だけが違う。
function renderSideBySideDiffHtml(hljs, diffText, lang, showLineNumbers) {
  var files = parseUnifiedDiff(diffText);
  // 外側の diff-split テーブルは 1 行あたり左右 2 セルしか持たない(行番号・記号・
  // 内容は各側の diff-side-table に入る)。区切り行だけ 6 列にすると表全体が 6 列と
  // みなされ、.diff-split .diff-side { width: 50% } が効かず左右のペインが潰れる。
  var span = 2;
  var rows = '';
  for (var f = 0; f < files.length; f++) {
    var hunks = files[f].hunks;
    for (var h = 0; h < hunks.length; h++) {
      var hunk = hunks[h];
      var lineHtmls = highlightedDiffLines(hljs, hunk, lang);
      if (rows !== '') { rows += diffHunkSeparatorRow(span); }
      var pairs = pairDiffLines(hunk.lines);
      for (var p = 0; p < pairs.length; p++) {
        var left = pairs[p].left;
        var right = pairs[p].right;
        var leftClass = left === null ? 'diff-empty' : 'diff-' + hunk.lines[left].type;
        var rightClass = right === null ? 'diff-empty' : 'diff-' + hunk.lines[right].type;
        rows += '<tr class="diff-line">'
          + '<td class="diff-side diff-side-left ' + leftClass + '"><table class="diff-side-table"><tr>'
          + diffSideCells(
            left === null ? null : hunk.lines[left], left === null ? '' : lineHtmls[left],
            showLineNumbers, 'left'
          )
          + '</tr></table></td>'
          + '<td class="diff-side diff-side-right ' + rightClass + '"><table class="diff-side-table"><tr>'
          + diffSideCells(
            right === null ? null : hunk.lines[right], right === null ? '' : lineHtmls[right],
            showLineNumbers, 'right'
          )
          + '</tr></table></td></tr>';
      }
    }
  }
  if (rows === '') { return ''; }
  return '<pre><code class="hljs"><table class="code-table diff-table diff-split">'
    + rows + '</table></code></pre>';
}

// レイアウト名から差分表示 HTML を組み立てる。呼び出し側(viewer-main.js)が
// レイアウトごとに分岐を持たないよう、選択をここへ閉じる。
function renderDiffHtml(hljs, diffText, lang, showLineNumbers, layout) {
  return layout === 'side-by-side'
    ? renderSideBySideDiffHtml(hljs, diffText, lang, showLineNumbers)
    : renderInlineDiffHtml(hljs, diffText, lang, showLineNumbers);
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
  // 末尾行の確定: ループ終了時点で未確定のフィールド/行が残っていれば push する。
  // ただし content が改行で終わっている場合は既に pushRow 済みで value/raw/row が
  // 空のため、ここでの再 push を条件付きでスキップし、末尾に幻の空行を作らない。
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
  if (showLineNumbers === true) {
    body = wrapWithLineNumbers(body, true);
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

// 検索ヒット間の移動先インデックス。件数 0 のときはどれも -1(選択なし)を返す。
// 末尾の次は先頭、先頭の前は末尾へ循環する。

function nextMatchIndex(currentIndex, count) {
  if (count <= 0) { return -1; }
  return (currentIndex + 1) % count;
}

function prevMatchIndex(currentIndex, count) {
  if (count <= 0) { return -1; }
  return (currentIndex - 1 + count) % count;
}

// 再検索(_mmdFindRefresh)で維持する現在位置。再検索でヒット数が減っても
// 範囲外を指さないようクランプする。負値(未選択)は先頭に寄せる。
function keptMatchIndex(previousIndex, count) {
  if (count <= 0) { return -1; }
  return Math.min(Math.max(previousIndex, 0), count - 1);
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
    sanitizeRenderedHtml: sanitizeRenderedHtml,
    isSafeLinkURL: isSafeLinkURL,
    isLocalPathHref: isLocalPathHref,
    highlightCode: highlightCode,
    diagramScrollHeight: diagramScrollHeight,
    imageFitSize: imageFitSize,
    markdownFontSize: markdownFontSize,
    escapeHtml: escapeHtml,
    svgDataURI: svgDataURI,
    imageDataURI: imageDataURI,
    base64ToBytes: base64ToBytes,
    renderCodeHtml: renderCodeHtml,
    wrapWithLineNumbers: wrapWithLineNumbers,
    buildLineNumberRows: buildLineNumberRows,
    indentColumns: indentColumns,
    leadingIndentInfo: leadingIndentInfo,
    lineContentCell: lineContentCell,
    CODE_TAB_SIZE: CODE_TAB_SIZE,
    reflowSpanBalancedLines: reflowSpanBalancedLines,
    csvRowsHtml: csvRowsHtml,
    codeChunkInnerHtml: codeChunkInnerHtml,
    lastLines: lastLines,
    tokenizeCsvRows: tokenizeCsvRows,
    parseCsv: parseCsv,
    buildTableHtml: buildTableHtml,
    renderCsvSourceHtml: renderCsvSourceHtml,
    parseUnifiedDiff: parseUnifiedDiff,
    highlightedDiffLines: highlightedDiffLines,
    renderInlineDiffHtml: renderInlineDiffHtml,
    pairDiffLines: pairDiffLines,
    renderSideBySideDiffHtml: renderSideBySideDiffHtml,
    renderDiffHtml: renderDiffHtml,
    csvSourceInnerHtml: csvSourceInnerHtml,
    CSV_COL_COUNT: CSV_COL_COUNT,
    buildFindRegExp: buildFindRegExp,
    nextMatchIndex: nextMatchIndex,
    prevMatchIndex: prevMatchIndex,
    keptMatchIndex: keptMatchIndex,
  };
}
