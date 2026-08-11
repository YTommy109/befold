// markdown-it インスタンスの構成と、その利用口。
// インスタンスはこのモジュールに閉じ、描画側は markdownRenderer() 経由で触る。

import { highlightCode } from './code-html.js';
import { DOMPurify, hljs, markdownit } from './vendor.js';


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
// purify は依存注入(実行時は vendor.js の DOMPurify、テストでは jsdom 上に構築した DOMPurify)。
// 自前の正規表現(on* 属性除去等)は個別のバイパス手法ごとにパッチを重ねる対症療法になるため、
// 実績のある DOMPurify にサニタイズそのものを委譲する。
function sanitizeRenderedHtml(purify, html) {
  return purify.sanitize(html);
}

// 構成済みの markdown-it。ベンダーはバンドル同梱(vendor.js)のため常に構成済みで、
// 「未ロード」状態は存在しない。
function markdownRenderer() {
  return md;
}

// 構成関数の宣言はこの下にあるが、関数宣言なので巻き上げられて評価時には解決済み。
var md = buildMarkdownRenderer();

// markdown-it の構成。モジュール評価時に 1 度だけ走る。
// 初期化関数に切り出して _mmdInit() から呼ぶ形にしないのは、ベンダーが
// バンドル同梱になり「読み込みを待つ」対象が無くなったため。呼び忘れや
// 「init 前に render された」経路を作らないよう、構成済みの md だけが存在する状態にする。
function buildMarkdownRenderer() {
  var instance = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function(str, lang) {
      return highlightCode(hljs, str, lang);
    },
  });
  // md.render() 出力を DOMPurify でサニタイズする後処理を追加。html:true で .md 内の
  // 生 HTML を許可しているため、<img onerror=...> 等の XSS ベクタを innerHTML 適用前に
  // 無害化する(sanitizeRenderedHtml は純粋関数、実処理は DOMPurify に委譲)。
  var _mdRenderOriginal = instance.render.bind(instance);
  instance.render = function(src, env) {
    return sanitizeRenderedHtml(DOMPurify, _mdRenderOriginal(src, env));
  };
  // fuzzyLink(scheme なしのドメイン風文字列の自動リンク化)を無効化する。
  // .md(モルドバ)や .sh(セントヘレナ)は実在の ccTLD のため、素のファイル名
  // (setup.md 等)が http:// の外部リンクに化けてブラウザが開いてしまう。
  // scheme 付き URL(https://...)の自動リンク化と [text](url) 形式は影響なし。
  instance.linkify.set({ fuzzyLink: false });
  instance.validateLink = isSafeLinkURL;
  var defaultFence = instance.renderer.rules.fence;
  instance.renderer.rules.fence = function(tokens, idx, options, env, self) {
    var token = tokens[idx];
    if (token.info.trim() === 'mermaid') {
      return '<pre class="mermaid">' + instance.utils.escapeHtml(token.content) + '</pre>';
    }
    if (defaultFence) {
      return defaultFence(tokens, idx, options, env, self);
    }
    return '<pre><code>' + instance.utils.escapeHtml(token.content) + '</code></pre>';
  };
  return instance;
}

export { isSafeLinkURL, sanitizeRenderedHtml, markdownRenderer };
