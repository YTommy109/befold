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
  return zoom * BASE_SCALE;
}

function parseStoredZoom(raw) {
  var z = parseFloat(raw);
  return isNaN(z) ? ZOOM_DEFAULT : z;
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    ZOOM_MIN: ZOOM_MIN,
    ZOOM_MAX: ZOOM_MAX,
    ZOOM_STEP: ZOOM_STEP,
    ZOOM_DEFAULT: ZOOM_DEFAULT,
    BASE_SCALE: BASE_SCALE,
    DIAGRAM_ZOOM_MAX: DIAGRAM_ZOOM_MAX,
    clampZoom: clampZoom,
    stepZoom: stepZoom,
    wheelZoom: wheelZoom,
    zoomLabel: zoomLabel,
    effectiveZoom: effectiveZoom,
    parseStoredZoom: parseStoredZoom,
    mermaidTheme: mermaidTheme,
    sanitizeLang: sanitizeLang,
    highlightCode: highlightCode,
  };
}
