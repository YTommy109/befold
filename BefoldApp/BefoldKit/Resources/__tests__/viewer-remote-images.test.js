// リモート画像(http/https)のブロック。TASK-526。
//
// viewer.html の meta CSP(img-src 'self' data:)は file:// で読み込んだ文書では
// WebKit がこの取得を検査せず、実測でリモートバッジが naturalWidth 78 で
// デコードできていた。ここは JS 側の一次防御(挿入前に代替表示へ置換する)を
// 固定する。ネイティブ側の二次防御(RemoteLoadBlocker の WKContentRuleList)は
// scripts/webview-smoke.swift の checkExfilBlocked が測る。

const { JSDOM } = require('jsdom');
const createDOMPurify = require('dompurify');

// replaceRemoteImages は DOMParser と window を使う(ブラウザ実行が本番)。
// このリポジトリのテストは node 環境なので、JSDOM のものをグローバルへ載せる。
const dom = new JSDOM('');
global.window = dom.window;
global.DOMParser = dom.window.DOMParser;

const { replaceRemoteImages, sanitizeRenderedHtml } = require('../../../viewer-src/main.js');

const purify = createDOMPurify(new JSDOM('').window);

describe('replaceRemoteImages', () => {
  test('replaces an https image with the blocked placeholder', () => {
    const html = '<p><img src="https://img.shields.io/badge/license-MIT-blue" alt="badge"></p>';
    const out = replaceRemoteImages(html);
    expect(out).not.toMatch(/<img/iu);
    expect(out).toContain('mmd-blocked-image');
    // alt はテキストとして残す(何の画像だったかを失わない)
    expect(out).toContain('badge');
  });

  test('replaces a plain http image too', () => {
    const out = replaceRemoteImages('<img src="http://example.com/x.png">');
    expect(out).not.toMatch(/<img/iu);
    expect(out).toContain('mmd-blocked-image');
  });

  test('keeps the original URL in the title attribute', () => {
    const out = replaceRemoteImages('<img src="https://example.com/x.png" alt="a">');
    expect(out).toContain('https://example.com/x.png');
    // title 属性であって src ではない(取得の対象にならない)
    expect(out).not.toMatch(/src=/iu);
  });

  test('leaves data: URI images untouched (TASK-524 の埋め込み経路を壊さない)', () => {
    const html = '<img src="data:image/png;base64,iVBORw0KGgo=" alt="a" width="380">';
    expect(replaceRemoteImages(html)).toBe(html);
  });

  test('leaves relative and file: images untouched', () => {
    const html = '<img src="./local.png"><img src="file:///tmp/x.png">';
    expect(replaceRemoteImages(html)).toBe(html);
  });

  test('leaves markup without images untouched', () => {
    const html = '<p><a href="https://example.com">link</a></p>';
    expect(replaceRemoteImages(html)).toBe(html);
  });

  test('replaces every remote image, not just the first (README のバッジ列)', () => {
    const html =
      '<img src="https://a.example/1.svg">' +
      '<img src="https://b.example/2.svg">' +
      '<img src="https://c.example/3.svg">';
    const out = replaceRemoteImages(html);
    expect(out).not.toMatch(/<img/iu);
    expect(out.match(/mmd-blocked-image/gu)).toHaveLength(3);
  });

  test('matches src with whitespace and mixed case scheme', () => {
    // 早期 return の正規表現が取りこぼすと <img> が残る
    const out = replaceRemoteImages("<img alt='x' src = ' HTTPS://example.com/x.png'>");
    expect(out).not.toMatch(/<img/iu);
  });

  test('uses the injected localized label when present', () => {
    global.window._mmdImageStrings = { blockedRemote: 'ブロック済み' };
    try {
      expect(replaceRemoteImages('<img src="https://example.com/x.png">')).toContain(
        'ブロック済み',
      );
    } finally {
      delete global.window._mmdImageStrings;
    }
  });

  test('does not let alt text inject markup', () => {
    const out = replaceRemoteImages('<img src="https://e.example/x.png" alt="<b>x</b>">');
    expect(out).not.toMatch(/<b>/iu);
  });
});

describe('sanitizeRenderedHtml (リモート画像)', () => {
  // 生 HTML の <img> は markdown-it の validateLink を通らないため、
  // サニタイズ経路に置換が入っていることが唯一の担保になる。
  test('blocks remote images in raw HTML', () => {
    const out = sanitizeRenderedHtml(purify, '<img src="https://example.com/exfil.png">');
    expect(out).not.toMatch(/<img/iu);
    expect(out).toContain('mmd-blocked-image');
  });
});
