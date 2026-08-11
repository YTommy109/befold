// Swift が注入したフォント設定を CSS 変数へ反映する。

var MACOS_DEFAULT_BODY = 13;
var WEB_BASELINE = 16;

// システム本文フォントサイズ(pt)を Markdown 表示の基準サイズ(px)へ換算する。
// 受け取る値は 3 通りある。Swift の注入は number、未注入は undefined、
// 文字列も許容する（viewer.test.js が '13' / 'abc' で呼んでいる）。
// parseFloat の型宣言は string しか受けないが、非文字列を渡したときの
// NaN 化に依存した既存の縮退（NaN なら WEB_BASELINE）をそのまま使うため、
// 実行時の形を変えずにキャストで通す。
function markdownFontSize(raw: number | string | undefined): number {
  var s = parseFloat(raw as string);
  if (isNaN(s) || s <= 0) { return WEB_BASELINE; }
  return WEB_BASELINE * (s / MACOS_DEFAULT_BODY);
}

// 適用先は style.css の #diagram-wrap.markdown-body(Markdown 表示のみ)。
function _mmdInitFontSize() {
  document.documentElement.style.setProperty(
    '--mmd-markdown-font-size',
    markdownFontSize(window._mmdSystemFontSize) + 'px'
  );
}

// Swift が注入した等幅フォント設定を CSS 変数へ反映する。
//  --mmd-mono-font-family: ソースビュー＋プレビュー内コード両方（ファミリーのみ）
//  --mmd-code-font-size:   ソースビューのみ（絶対サイズ、px）
function _mmdInitCodeFont() {
  var root = document.documentElement;
  var family = window._mmdMonoFontFamily || '';
  if (family) {
    // CSS quoted-string 内で壊れないよう " と \ をエスケープする。
    var safe = family.replace(/[\\"]/g, '\\$&');
    root.style.setProperty('--mmd-mono-font-family',
      '"' + safe + '", ui-monospace, SFMono-Regular, "SF Mono", Menlo, monospace');
  } else {
    root.style.removeProperty('--mmd-mono-font-family');
  }
  var pt = window._mmdCodeFontSize;
  if (typeof pt === 'number' && pt > 0) {
    root.style.setProperty('--mmd-code-font-size', (pt * 16 / 13) + 'px');
  } else {
    root.style.removeProperty('--mmd-code-font-size');
  }
}

export { MACOS_DEFAULT_BODY, WEB_BASELINE, markdownFontSize, _mmdInitFontSize, _mmdInitCodeFont };
