// markdown-it インスタンスの構成と、その利用口。
// インスタンスはこのモジュールに閉じ、描画側は markdownRenderer() 経由で触る。

import { highlightCode } from './code-html.js';
import { DOMPurify, hljs, markdownit } from './vendor.js';

/// 構成済み markdown-it インスタンスと、そのトークンの型。@types/markdown-it の
/// サブパス(markdown-it/lib/token.mjs 等)を直接 import せず、ファクトリの
/// 返り値から導出する(サブパスの構成は版で変わるが、この導出は変わらない)。
type MarkdownItInstance = ReturnType<typeof markdownit>;
type MarkdownToken = ReturnType<MarkdownItInstance['parse']>[number];

/// 依存注入されるサニタイザの最小インターフェース。実行時は vendor.js の
/// DOMPurify、テストでは jsdom 上に構築した DOMPurify が渡る。
interface HtmlSanitizer {
  sanitize(html: string): string;
}

// markdown-it の validateLink 置き換え。既定は data:image/(gif|png|jpeg|webp)
// のみ許可するが、MarkdownImageEmbedder が生成する svg+xml / bmp / x-icon の
// data URI も表示できるよう data:image/* を全許可する。CSP は img-src 'self' data:
// のため data:image の <img> 表示は安全(SVG も <img> 経由ではスクリプト非実行)。
// javascript:/vbscript:/file:/画像以外の data: は既定どおり拒否し XSS を防ぐ。
function isSafeLinkURL(url: string): boolean {
  // markdown-it 側の実行時値に対する防御的な文字列化。型の上では冗長だが、
  // 外すと型が破れたときに例外へ変わる（現在は文字列化で受け止める）。
  // oxlint-disable-next-line typescript/no-unnecessary-type-conversion
  var str = String(url).trim().toLowerCase();
  if (str.startsWith('data:image/')) {
    return true;
  }
  return !/^(vbscript|javascript|file|data):/u.test(str);
}

// markdown-it の html:true が通す生 HTML(md.render() 出力)を innerHTML 適用前にサニタイズする。
// purify は依存注入(実行時は vendor.js の DOMPurify、テストでは jsdom 上に構築した DOMPurify)。
// 自前の正規表現(on* 属性除去等)は個別のバイパス手法ごとにパッチを重ねる対症療法になるため、
// 実績のある DOMPurify にサニタイズそのものを委譲する。
function sanitizeRenderedHtml(purify: HtmlSanitizer, html: string): string {
  return replaceRemoteImages(purify.sanitize(html));
}

// リモート画像(http/https)を代替表示へ置き換える。TASK-526。
//
// viewer.html の meta CSP は img-src 'self' data: を宣言しているが、file:// で読み込んだ
// 文書では WebKit がこの取得を検査しない(実測: shields.io のバッジが naturalWidth 78 で
// デコードでき、securitypolicyviolation は 1 件も発火しない)。放置すると文書を開くだけで
// 外部ホストへ IP・User-Agent・閲覧時刻が渡る。
//
// 置換は DOMParser が作る**切り離された文書**の上で行う。この文書は閲覧コンテキストを
// 持たないため、img の src を読んだだけでは取得が始まらない。innerHTML へ入れてから
// 直すのでは、挿入した時点で既にリクエストが出てしまう。
//
// ネイティブ側(RemoteLoadBlocker)の WKContentRuleList が二層目として同じ取得を
// 遮断する。こちらは JS を通らない直接 HTML モードとサニタイザの漏れを塞ぐ。
function replaceRemoteImages(html: string): string {
  // 当たりを付けるための正規表現による早期 return は置かない(TASK-548)。
  // かつては /<img[^>]+src\s*=\s*["']?\s*https?:/iu で DOM の往復を省いていたが、
  // この形は「非 ASCII を 1 文字でも含む長い文書」で JSC が事実上停止する。
  // 実測(WKWebView、<img> 1 つの中の文字数を変えて test を 1 回):
  // 非 ASCII を 1 文字でも含むと 24,000 字 379ms / 48,000 字 1,512ms /
  // 96,000 字 5,991ms / 192,000 字 23,666ms(文字数の二乗)。同じ 192,000 字でも
  // 全 ASCII なら 1ms。site/content/medical-expenses.ja.md(画像 4 枚を data URI 化して
  // 772KB)は 60 秒を超えても返らず、本文が空白のまま固まる。
  // 引き金は u フラグで、外すと同じ入力が 1ms で終わる(JSC が 16bit 文字列 + u では
  // Yarr JIT に載せられず、[^>]+ のバックトラックを解釈実行するため)。
  //
  // 省ける DOM の往復は、その 772KB の文書でも実測 8ms しかない。バックトラックの
  // 効かない別の判定式へ置き換えるのではなく判定そのものを外し、常に DOM 走査に
  // 委ねる(正規表現で HTML の当たりを付けない形にすれば、同型の停止は再発しない)。
  var doc = new DOMParser().parseFromString(html, 'text/html');
  var images = doc.querySelectorAll('img');
  for (var i = 0; i < images.length; i += 1) {
    var img = images[i]!;
    if (!/^\s*https?:/iu.test(img.getAttribute('src') || '')) {
      continue;
    }
    img.replaceWith(blockedImageElement(doc, img));
  }
  return doc.body.innerHTML;
}

// ブロックしたリモート画像の代替要素。文言は ViewerBridge.imageStringsScript(bundle:) が
// 注入する(未注入時は英語のフォールバック)。alt と元 URL は textContent / title に
// 入れるため、マークアップとしては解釈されない。
function blockedImageElement(doc: Document, img: Element): Element {
  var strings: ViewerImageStrings = window._mmdImageStrings || {};
  var label = strings.blockedRemote || 'External image blocked';
  var alt = img.getAttribute('alt') || '';
  var span = doc.createElement('span');
  span.className = 'mmd-blocked-image';
  span.textContent = alt ? label + ': ' + alt : label;
  span.setAttribute('title', img.getAttribute('src') || '');
  return span;
}

// 見出しの表示テキストを取り出す。inline トークンの children から text / code_inline の
// 中身だけを連結するため、`## **太字**の見出し` のような装飾は記号を含まないテキストになる
// (`inline.content` を使うと `**` が残り、GitHub の slug とずれる)。
function headingTextOf(inlineToken: MarkdownToken | undefined): string {
  if (!inlineToken) {
    return '';
  }
  var children = inlineToken.children;
  if (!children || children.length === 0) {
    // oxlint-disable-next-line typescript/no-unnecessary-type-conversion
    return String(inlineToken.content || '');
  }
  var text = '';
  for (var i = 0; i < children.length; i += 1) {
    var child = children[i]!;
    if (child.type === 'text' || child.type === 'code_inline') {
      text += child.content;
    }
  }
  return text;
}

// GitHub 互換の見出し slug。小文字化し、記号を捨て、空白をハイフンにする。
// 文字・数字・結合文字・連結記号(_)・ハイフン・空白だけを残すため、日本語などの
// 非 ASCII は**そのまま**残る。ここで percent-encode しないこと。クリック側
// (reference-clicks.js)は href を decodeURIComponent してから getElementById する。
// id を encode 済みにすると、その decode 済みキーと一致しなくなる。
function slugifyHeading(text: string): string {
  // markdown-it 側の実行時値に対する防御的な文字列化。型の上では冗長だが、
  // 外すと型が破れたときに例外へ変わる（現在は文字列化で受け止める）。
  // oxlint-disable-next-line typescript/no-unnecessary-type-conversion
  return String(text)
    .trim()
    .toLowerCase()
    .replaceAll(/[^\p{L}\p{N}\p{M}\p{Pc}\- ]/gu, '')
    .replaceAll(' ', '-');
}

// 1 回の描画で使う slug を一意化する。GitHub と同じく、2 回目以降の重複には
// -1 / -2 … の連番を付ける。used は呼び出し側が描画ごとに用意する Map。
function uniqueHeadingSlug(slug: string, used: Map<string, number>): string {
  var base = slug || 'section';
  var seen = used.get(base);
  if (seen === undefined) {
    used.set(base, 0);
    return base;
  }
  var next = seen + 1;
  var candidate = base + '-' + next;
  // 連番付きの候補が、別の見出しの素の slug と衝突することがある
  // (`# Foo` / `# Foo` / `# Foo 1` の 3 本目)。空いている番号まで送る。
  while (used.has(candidate)) {
    next += 1;
    candidate = base + '-' + next;
  }
  used.set(base, next);
  used.set(candidate, 0);
  return candidate;
}

// heading_open トークンへ id を振る core ルール。描画ごとに Map を作り直すので、
// 連番の状態が前の描画へ漏れない。
function assignHeadingIds(state: { tokens: MarkdownToken[] }): void {
  var used = new Map<string, number>();
  var tokens = state.tokens;
  for (var i = 0; i < tokens.length; i += 1) {
    if (tokens[i]!.type !== 'heading_open') {
      continue;
    }
    var slug = uniqueHeadingSlug(slugifyHeading(headingTextOf(tokens[i + 1])), used);
    tokens[i]!.attrSet('id', slug);
  }
}

// 構成済みの markdown-it。ベンダーはバンドル同梱(vendor.js)のため常に構成済みで、
// 「未ロード」状態は存在しない。
function markdownRenderer(): MarkdownItInstance {
  return md;
}

// 構成関数の宣言はこの下にあるが、関数宣言なので巻き上げられて評価時には解決済み。
var md = buildMarkdownRenderer();

// markdown-it の構成。モジュール評価時に 1 度だけ走る。
// 初期化関数に切り出して _mmdInit() から呼ぶ形にしないのは、ベンダーが
// バンドル同梱になり「読み込みを待つ」対象が無くなったため。呼び忘れや
// 「init 前に render された」経路を作らないよう、構成済みの md だけが存在する状態にする。
function buildMarkdownRenderer(): MarkdownItInstance {
  var instance = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function (str: string, lang: string): string {
      return highlightCode(hljs, str, lang);
    },
  });
  // md.render() 出力を DOMPurify でサニタイズする後処理を追加。html:true で .md 内の
  // 生 HTML を許可しているため、<img onerror=...> 等の XSS ベクタを innerHTML 適用前に
  // 無害化する(sanitizeRenderedHtml は純粋関数、実処理は DOMPurify に委譲)。
  var _mdRenderOriginal = instance.render.bind(instance);
  instance.render = function (src, env) {
    return sanitizeRenderedHtml(DOMPurify, _mdRenderOriginal(src, env));
  };
  // fuzzyLink(scheme なしのドメイン風文字列の自動リンク化)を無効化する。
  // .md(モルドバ)や .sh(セントヘレナ)は実在の ccTLD のため、素のファイル名
  // (setup.md 等)が http:// の外部リンクに化けてブラウザが開いてしまう。
  // scheme 付き URL(https://...)の自動リンク化と [text](url) 形式は影響なし。
  instance.linkify.set({ fuzzyLink: false });
  // 見出しに id を振る(TASK-466)。文書内アンカーリンク([…](#見出し))のクリックは
  // reference-clicks.js が getElementById で解決するため、id が無いと黙って何も
  // 起きない。core チェーンの最後に置き、inline 解析後の children を読む。
  instance.core.ruler.push('befold_heading_ids', assignHeadingIds);
  instance.validateLink = isSafeLinkURL;
  var defaultFence = instance.renderer.rules.fence;
  instance.renderer.rules.fence = function (tokens, idx, options, env, self) {
    var token = tokens[idx]!;
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

export {
  isSafeLinkURL,
  replaceRemoteImages,
  sanitizeRenderedHtml,
  markdownRenderer,
  slugifyHeading,
  uniqueHeadingSlug,
};
