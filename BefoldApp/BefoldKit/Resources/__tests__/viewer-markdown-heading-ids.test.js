// 見出しへの id 付与と、文書内アンカーリンクの解決（TASK-466）。
//
// 対象は viewer-src の**実インスタンス**（markdownRenderer()）。slug 生成を
// テスト側で組み直すと、core ルールが実際に配線されているかが検証されない。
//
// ただし instance.render() は DOMPurify を呼ぶ。Jest の既定 testEnvironment は
// node で window が無く、dompurify は sanitize を持たない形で読み込まれるため、
// ここでは parse + renderer.render で HTML を得て、サニタイズは既存テストと同じ
// jsdom 上に構築した DOMPurify を sanitizeRenderedHtml へ渡して確かめる。
const { JSDOM } = require('jsdom');
const createDOMPurify = require('dompurify');
const {
  markdownRenderer,
  sanitizeRenderedHtml,
  slugifyHeading,
  uniqueHeadingSlug,
} = require('../../../viewer-src/main.js');

const md = markdownRenderer();
const purify = createDOMPurify(new JSDOM('').window);

// 実インスタンスの core チェーン（befold_heading_ids を含む）を通した HTML。
function renderBody(src) {
  return md.renderer.render(md.parse(src, {}), md.options, {});
}

// 描画結果を DOM にして、クリック側と同じやり方で解決できるかを見る。
function documentOf(html) {
  return new JSDOM('<div id="diagram-wrap">' + html + '</div>').window.document;
}

// reference-clicks.js のアンカー解決と同じ手順。実ハンドラは e.isTrusted を要求し、
// jsdom の dispatchEvent では false になるため直接は駆動できない。ここでは
// 「href からキーを作り getElementById で引く」という同じ契約を検証する。
function resolveAnchor(doc, href) {
  let id;
  try { id = decodeURIComponent(href.slice(1)); } catch (_) { id = href.slice(1); }
  return doc.getElementById(id);
}

describe('slugifyHeading', () => {
  test('小文字化し、空白をハイフンにし、記号を落とす', () => {
    expect(slugifyHeading('Hello World')).toBe('hello-world');
    expect(slugifyHeading('What is this?!')).toBe('what-is-this');
    expect(slugifyHeading('  Trim  Me  ')).toBe('trim--me');
  });

  test('日本語はそのまま残り、percent-encode しない', () => {
    expect(slugifyHeading('有効期間の表現')).toBe('有効期間の表現');
    expect(slugifyHeading('有効期間 の 表現')).toBe('有効期間-の-表現');
  });

  test('ハイフンとアンダースコアは残す', () => {
    expect(slugifyHeading('foo_bar-baz')).toBe('foo_bar-baz');
  });
});

describe('uniqueHeadingSlug', () => {
  test('2 回目以降に連番サフィックスを付ける', () => {
    const used = new Map();
    expect(uniqueHeadingSlug('foo', used)).toBe('foo');
    expect(uniqueHeadingSlug('foo', used)).toBe('foo-1');
    expect(uniqueHeadingSlug('foo', used)).toBe('foo-2');
  });

  test('連番候補が既存の素の slug と衝突したら空き番号まで送る', () => {
    const used = new Map();
    expect(uniqueHeadingSlug('foo-1', used)).toBe('foo-1');
    expect(uniqueHeadingSlug('foo', used)).toBe('foo');
    expect(uniqueHeadingSlug('foo', used)).toBe('foo-2');
  });

  test('記号だけの見出しでも空 id にしない', () => {
    expect(uniqueHeadingSlug(slugifyHeading('???'), new Map())).toBe('section');
  });
});

describe('見出しへの id 付与', () => {
  test('h1〜h6 すべてに id が付く', () => {
    const src = ['# A', '## B', '### C', '#### D', '##### E', '###### F'].join('\n\n');
    const doc = documentOf(renderBody(src));
    ['a', 'b', 'c', 'd', 'e', 'f'].forEach((slug, i) => {
      const el = doc.getElementById(slug);
      expect(el).not.toBeNull();
      expect(el.tagName).toBe('H' + (i + 1));
    });
  });

  test('装飾付きの見出しは記号を含まない slug になる', () => {
    const doc = documentOf(renderBody('## **太字**の見出し\n'));
    expect(doc.getElementById('太字の見出し')).not.toBeNull();
  });

  test('同じ見出しが並んでも id が一意になる', () => {
    const doc = documentOf(renderBody('# Dup\n\n# Dup\n\n# Dup\n'));
    expect(doc.getElementById('dup')).not.toBeNull();
    expect(doc.getElementById('dup-1')).not.toBeNull();
    expect(doc.getElementById('dup-2')).not.toBeNull();
  });

  test('描画をまたいで連番が持ち越されない', () => {
    renderBody('# Dup\n\n# Dup\n');
    const doc = documentOf(renderBody('# Dup\n'));
    expect(doc.getElementById('dup')).not.toBeNull();
    expect(doc.getElementById('dup-1')).toBeNull();
  });

  test('DOMPurify を通しても id が残る', () => {
    const doc = documentOf(sanitizeRenderedHtml(purify, renderBody('# 有効期間の表現\n')));
    expect(doc.getElementById('有効期間の表現')).not.toBeNull();
  });
});

describe('文書内アンカーリンクの解決', () => {
  test('日本語見出しへのリンクが見出しへ解決する', () => {
    const src = '# 有効期間の表現\n\n[有効期限の表現](#有効期間の表現)\n';
    const doc = documentOf(sanitizeRenderedHtml(purify, renderBody(src)));
    const href = doc.querySelector('a').getAttribute('href');
    const el = resolveAnchor(doc, href);
    expect(el).not.toBeNull();
    expect(el.tagName).toBe('H1');
  });

  test('href が percent-encode されていても id と一致する', () => {
    const src = '# 有効期間の表現\n\n[x](#有効期間の表現)\n';
    const doc = documentOf(sanitizeRenderedHtml(purify, renderBody(src)));
    const href = doc.querySelector('a').getAttribute('href');
    // markdown-it の normalizeLink が encode するかは版に依存する。どちらでも
    // クリック側の decodeURIComponent を通せば id と一致することを固定する。
    expect(decodeURIComponent(href.slice(1))).toBe('有効期間の表現');
    expect(resolveAnchor(doc, href)).not.toBeNull();
  });

  test('存在しない見出しへのリンクは解決しない', () => {
    const doc = documentOf(sanitizeRenderedHtml(purify, renderBody('# A\n\n[x](#no-such)\n')));
    expect(resolveAnchor(doc, '#no-such')).toBeNull();
  });
});
