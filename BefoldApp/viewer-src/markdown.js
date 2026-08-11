// markdown-it インスタンスの構成と、その利用口。
// インスタンスはこのモジュールに閉じ、描画側は markdownRenderer() 経由で触る。

import { highlightCode } from './code-html.js';

var md;

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

// markdown-it の html:true が通す生 HTML(md.render() 出力)を innerHTML 適用前にサニタイズする。
// purify は依存注入(viewer.html ではグローバル DOMPurify、テストでは jsdom 上に構築した DOMPurify)。
// 自前の正規表現(on* 属性除去等)は個別のバイパス手法ごとにパッチを重ねる対症療法になるため、
// 実績のある DOMPurify にサニタイズそのものを委譲する。
function sanitizeRenderedHtml(purify, html) {
  return purify.sanitize(html);
}

// 構成済みの markdown-it。未ロード時(下記参照)は undefined を返し、
// 呼び出し側が Markdown 経路だけを縮退させる。
function markdownRenderer() {
  return md;
}

// markdown-it.min.js の読み込み失敗時は markdownit 未定義 → md も未定義のままにし、
// Markdown 描画経路(render の md.render 呼び出し)だけが機能しない縮退にとどめる。
function _mmdInitMarkdown() {
  if (typeof markdownit === 'undefined') { return; }
  md = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    // highlight.min.js の読み込み失敗時は hljs 未定義 → highlightCode が '' を
    // 返し、ハイライトなしの従来表示に縮退する。
    highlight: function(str, lang) {
      return highlightCode(typeof hljs !== 'undefined' ? hljs : null, str, lang);
    },
  });
  // md.render() 出力を DOMPurify でサニタイズする後処理を追加。html:true で .md 内の
  // 生 HTML を許可しているため、<img onerror=...> 等の XSS ベクタを innerHTML 適用前に
  // 無害化する(sanitizeRenderedHtml は純粋関数、実処理は DOMPurify に委譲)。
  var _mdRenderOriginal = md.render.bind(md);
  md.render = function(src, env) {
    return sanitizeRenderedHtml(DOMPurify, _mdRenderOriginal(src, env));
  };
  // fuzzyLink(scheme なしのドメイン風文字列の自動リンク化)を無効化する。
  // .md(モルドバ)や .sh(セントヘレナ)は実在の ccTLD のため、素のファイル名
  // (setup.md 等)が http:// の外部リンクに化けてブラウザが開いてしまう。
  // scheme 付き URL(https://...)の自動リンク化と [text](url) 形式は影響なし。
  md.linkify.set({ fuzzyLink: false });
  md.validateLink = isSafeLinkURL;
  var defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = function(tokens, idx, options, env, self) {
    var token = tokens[idx];
    if (token.info.trim() === 'mermaid') {
      return '<pre class="mermaid">' + md.utils.escapeHtml(token.content) + '</pre>';
    }
    if (defaultFence) {
      return defaultFence(tokens, idx, options, env, self);
    }
    return '<pre><code>' + md.utils.escapeHtml(token.content) + '</code></pre>';
  };
}

export { isSafeLinkURL, sanitizeRenderedHtml, markdownRenderer, _mmdInitMarkdown };
