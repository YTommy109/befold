import { describe, expect, test } from '@jest/globals';
import createDOMPurify from 'dompurify';
import hljs from 'highlight.js';
import { JSDOM } from 'jsdom';
import markdownit from 'markdown-it';

import {
  ZOOM_MIN,
  ZOOM_MAX,
  ZOOM_STEP,
  ZOOM_DEFAULT,
  BASE_SCALE,
  DIAGRAM_ZOOM_MAX,
  clampZoom,
  stepZoom,
  wheelZoom,
  zoomLabel,
  parseStoredZoom,
  mermaidTheme,
  sanitizeLang,
  sanitizeRenderedHtml,
  highlightCode,
  diagramScrollHeight,
  imageFitSize,
  PAGE_SCROLL_RATIO,
  DEFAULT_LINE_SCROLL_STEP,
  pageScrollStep,
  halfPageScrollStep,
  lineScrollStep,
  resolveScrollKey,
  isHostFeatureEnabled,
  markdownFontSize,
  escapeHtml,
  renderCodeHtml,
  wrapWithLineNumbers,
} from '../viewer-src/main.js';

describe('clampZoom', () => {
  test('returns value within range unchanged', () => {
    expect(clampZoom(1.0)).toBe(1.0);
    expect(clampZoom(0.5)).toBe(0.5);
    expect(clampZoom(2.0)).toBe(2.0);
    expect(clampZoom(1.25)).toBe(1.25);
  });

  test('clamps below minimum to ZOOM_MIN', () => {
    expect(clampZoom(0.3)).toBe(ZOOM_MIN);
    expect(clampZoom(0)).toBe(ZOOM_MIN);
    expect(clampZoom(-1)).toBe(ZOOM_MIN);
  });

  test('clamps above maximum to ZOOM_MAX', () => {
    expect(clampZoom(2.5)).toBe(ZOOM_MAX);
    expect(clampZoom(10)).toBe(ZOOM_MAX);
  });
});

describe('stepZoom', () => {
  test('increments by one step', () => {
    expect(stepZoom(1.0, ZOOM_STEP)).toBe(1.25);
    expect(stepZoom(1.25, ZOOM_STEP)).toBe(1.5);
  });

  test('decrements by one step', () => {
    expect(stepZoom(1.0, -ZOOM_STEP)).toBe(0.75);
    expect(stepZoom(0.75, -ZOOM_STEP)).toBe(0.5);
  });

  test('clamps at maximum', () => {
    expect(stepZoom(2.0, ZOOM_STEP)).toBe(ZOOM_MAX);
    expect(stepZoom(1.75, ZOOM_STEP)).toBe(2.0);
  });

  test('clamps at minimum', () => {
    expect(stepZoom(0.5, -ZOOM_STEP)).toBe(ZOOM_MIN);
    expect(stepZoom(0.75, -ZOOM_STEP)).toBe(0.5);
  });

  test('handles fractional accumulation without floating point drift', () => {
    let z = 1.0;
    for (let i = 0; i < 4; i++) z = stepZoom(z, ZOOM_STEP);
    expect(z).toBe(2.0);

    z = 1.0;
    for (let i = 0; i < 2; i++) z = stepZoom(z, -ZOOM_STEP);
    expect(z).toBe(0.5);
  });
});

describe('wheelZoom', () => {
  test('scroll up (negative deltaY) zooms in', () => {
    const result = wheelZoom(1.0, -25);
    expect(result).toBe(1.25);
  });

  test('scroll down (positive deltaY) zooms out', () => {
    const result = wheelZoom(1.0, 25);
    expect(result).toBe(0.75);
  });

  test('small deltaY produces fine-grained zoom', () => {
    const result = wheelZoom(1.0, -1);
    expect(result).toBe(1.01);
  });

  test('clamps at boundaries', () => {
    expect(wheelZoom(2.0, -100)).toBe(ZOOM_MAX);
    expect(wheelZoom(0.5, 100)).toBe(ZOOM_MIN);
  });
});

describe('zoomLabel', () => {
  test('formats 1x as 100%', () => {
    expect(zoomLabel(1)).toBe('100%');
  });

  test('formats fractional zoom', () => {
    expect(zoomLabel(0.5)).toBe('50%');
    expect(zoomLabel(0.75)).toBe('75%');
    expect(zoomLabel(1.25)).toBe('125%');
    expect(zoomLabel(2.0)).toBe('200%');
  });

  test('rounds to nearest integer', () => {
    expect(zoomLabel(1.006)).toBe('101%');
    expect(zoomLabel(0.999)).toBe('100%');
  });
});

describe('parseStoredZoom', () => {
  test('parses valid float string', () => {
    expect(parseStoredZoom('1.25')).toBe(1.25);
    expect(parseStoredZoom('0.5')).toBe(0.5);
    expect(parseStoredZoom('2')).toBe(2);
  });

  test('returns ZOOM_DEFAULT for null', () => {
    expect(parseStoredZoom(null)).toBe(ZOOM_DEFAULT);
  });

  test('returns ZOOM_DEFAULT for undefined', () => {
    // @ts-expect-error -- 契約外の引数省略（未保存）に対する既定値を確かめる
    expect(parseStoredZoom()).toBe(ZOOM_DEFAULT);
  });

  test('returns ZOOM_DEFAULT for non-numeric string', () => {
    expect(parseStoredZoom('abc')).toBe(ZOOM_DEFAULT);
    expect(parseStoredZoom('')).toBe(ZOOM_DEFAULT);
  });

  test('parses without clamping (raw stored value)', () => {
    expect(parseStoredZoom('0.1')).toBe(0.1);
    expect(parseStoredZoom('5.0')).toBe(5.0);
  });

  test('parses injected numeric value', () => {
    expect(parseStoredZoom(1.25)).toBe(1.25);
    expect(parseStoredZoom(1)).toBe(1);
  });
});

describe('mermaidTheme', () => {
  test('returns dark theme when prefers-color-scheme is dark', () => {
    expect(mermaidTheme(true)).toBe('dark');
  });

  test('returns default theme when prefers-color-scheme is light', () => {
    expect(mermaidTheme(false)).toBe('default');
  });
});

describe('constants', () => {
  test('ZOOM_MIN < ZOOM_DEFAULT < ZOOM_MAX', () => {
    expect(ZOOM_MIN).toBeLessThan(ZOOM_DEFAULT);
    expect(ZOOM_DEFAULT).toBeLessThan(ZOOM_MAX);
  });

  test('ZOOM_STEP divides range evenly from default', () => {
    const stepsUp = (ZOOM_MAX - ZOOM_DEFAULT) / ZOOM_STEP;
    const stepsDown = (ZOOM_DEFAULT - ZOOM_MIN) / ZOOM_STEP;
    expect(Number.isInteger(stepsUp)).toBe(true);
    expect(Number.isInteger(stepsDown)).toBe(true);
  });
});

describe('sanitizeLang', () => {
  test('passes through normal language names', () => {
    expect(sanitizeLang('javascript')).toBe('javascript');
    expect(sanitizeLang('c++')).toBe('c++');
    expect(sanitizeLang('objective-c')).toBe('objective-c');
  });

  test('strips characters not allowed in a class attribute', () => {
    expect(sanitizeLang('js" onload="x')).toBe('jsonloadx');
    expect(sanitizeLang('a<b>')).toBe('ab');
  });

  test('stringifies non-string input', () => {
    expect(sanitizeLang(null)).toBe('null');
  });
});

describe('highlightCode', () => {
  test('wraps known-language code in pre/code with hljs classes', () => {
    const result = highlightCode(hljs, 'const x = 1;', 'javascript');
    expect(result.startsWith('<pre><code class="hljs language-javascript">')).toBe(true);
    expect(result.endsWith('</code></pre>')).toBe(true);
    expect(result).toContain('<span class="hljs-');
  });

  test('highlights swift keywords', () => {
    const result = highlightCode(hljs, 'let x = 1', 'swift');
    expect(result).toContain('hljs-keyword');
  });

  test('returns empty string for unsupported language', () => {
    expect(highlightCode(hljs, 'foo', 'no-such-lang-xyz')).toBe('');
  });

  test('returns empty string when language is missing', () => {
    expect(highlightCode(hljs, 'foo', '')).toBe('');
    // @ts-expect-error -- 契約外の言語名の省略に対する縮退を確かめる
    expect(highlightCode(hljs, 'foo')).toBe('');
  });

  test('returns empty string when hljs is unavailable', () => {
    expect(highlightCode(null, 'const x = 1;', 'javascript')).toBe('');
  });

  test('escapes HTML inside code content', () => {
    const result = highlightCode(hljs, 'var s = "<script>alert(1)</script>";', 'javascript');
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });
});

describe('markdown-it integration with highlightCode', () => {
  // viewer.html の markdownit 初期化と同じ配線
  const md = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function (str, lang) {
      return highlightCode(hljs, str, lang);
    },
  });

  test('fenced block with language gets hljs markup as-is', () => {
    const html = md.render('```javascript\nconst x = 1;\n```\n');
    expect(html).toContain('<pre><code class="hljs language-javascript">');
    expect(html).toContain('<span class="hljs-');
  });

  test('fenced block without language falls back to escaped plain block', () => {
    const html = md.render('```\n<b>raw</b>\n```\n');
    expect(html).toContain('&lt;b&gt;raw&lt;/b&gt;');
    expect(html).not.toContain('hljs');
  });

  test('fenced block with unsupported language falls back to escaped plain block', () => {
    const html = md.render('```no-such-lang-xyz\n<b>raw</b>\n```\n');
    expect(html).toContain('&lt;b&gt;raw&lt;/b&gt;');
    expect(html).not.toContain('<span class="hljs-');
  });
});

// 実際に innerHTML へ挿入した DOM を検査し、on* ハンドラ属性が存在しないことを確認する。
// (旧サニタイザは文字列置換のため、on* を含む文字列がタグの外/属性値の中に残っても
// それだけでは脆弱性ではない。DOM 構造として実行可能なハンドラが無いことが本質。)
function hasEventHandlerAttribute(html: string) {
  const container = new JSDOM('').window.document.createElement('div');
  container.innerHTML = html;
  return Array.from(container.querySelectorAll('*')).some((el) =>
    Array.from(el.attributes).some((attr) => /^on/iu.test(attr.name)),
  );
}

describe('sanitizeRenderedHtml', () => {
  const purify = createDOMPurify(new JSDOM('').window);

  test('strips onerror hidden behind a slash after a quoted attribute (regex-sanitizer /\\s+on.../ bypass)', () => {
    // 閉じクォート直後の "/" は HTML5 仕様上 attribute name state に戻るため、
    // 空白なしでも onerror が独立した属性としてパースされる(旧正規表現の \s+ 要求を回避)。
    const html = '<div>\n<img src="x"/onerror=alert(1)>\n</div>';
    expect(hasEventHandlerAttribute(html)).toBe(true);
    expect(hasEventHandlerAttribute(sanitizeRenderedHtml(purify, html))).toBe(false);
  });

  test('strips onload behind a namespaced attribute (xlink:href) (regex-sanitizer bypass)', () => {
    const html = '<a xlink:href="1" onload="alert(1)">x</a>';
    expect(hasEventHandlerAttribute(html)).toBe(true);
    expect(hasEventHandlerAttribute(sanitizeRenderedHtml(purify, html))).toBe(false);
  });

  test('strips script tags entirely', () => {
    const html = '<p>hi</p><script>alert(1)</script>';
    expect(sanitizeRenderedHtml(purify, html)).not.toMatch(/<script/iu);
  });

  test('keeps benign markdown-rendered markup intact', () => {
    const html = '<p><strong>hello</strong> <a href="https://example.com">link</a></p>';
    expect(sanitizeRenderedHtml(purify, html)).toBe(html);
  });

  test('keeps mermaid fence output intact', () => {
    // viewer.html の fence ルール(mermaid)が生成する形と同じ
    const html = '<pre class="mermaid">graph TD; A--&gt;B;</pre>';
    expect(sanitizeRenderedHtml(purify, html)).toBe(html);
  });

  // MarkdownImageEmbedder(Swift 側)は inline HTML の <img src> をローカルパスから
  // data URI へ差し替える(TASK-524)。![]() 記法の data URI は markdown-it の
  // validateLink が data:image/ を明示許可して通すが、生 HTML はそこを通らず
  // DOMPurify の判断だけで決まる。ここが落ちると Swift 側が正しく差し替えても
  // 画像は表示されないため、両方の関門を別々にピン留めする。
  test('keeps data: URI images in raw HTML (inline <img> embedding depends on this)', () => {
    const html = '<img src="data:image/png;base64,iVBORw0KGgo=" alt="a" width="380">';
    expect(sanitizeRenderedHtml(purify, html)).toBe(html);
  });

  test('keeps data: URI SVG images and the surrounding centering markup', () => {
    const html =
      '<p align="center"><img src="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=" width="900"></p>';
    expect(sanitizeRenderedHtml(purify, html)).toBe(html);
  });

  test('end-to-end: markdown-it html:true output with the slash-separator bypass payload is neutralized', () => {
    // viewer.html の markdownit 初期化と同じ配線(html:true が生 HTML を通す)
    const md = markdownit({ html: true, linkify: true, typographer: true });
    const rendered = md.render('<div>\n<img src="x"/onerror=alert(1)>\n</div>');
    const clean = sanitizeRenderedHtml(purify, rendered);
    expect(hasEventHandlerAttribute(clean)).toBe(false);
  });
});

describe('DIAGRAM_ZOOM_MAX', () => {
  test('is 3.0 and above ZOOM_MAX', () => {
    expect(DIAGRAM_ZOOM_MAX).toBe(3.0);
    expect(DIAGRAM_ZOOM_MAX).toBeGreaterThan(ZOOM_MAX);
  });

  test('ZOOM_STEP divides diagram range evenly from default', () => {
    const stepsUp = (DIAGRAM_ZOOM_MAX - ZOOM_DEFAULT) / ZOOM_STEP;
    expect(Number.isInteger(stepsUp)).toBe(true);
  });
});

describe('clampZoom with custom max', () => {
  test('allows values above ZOOM_MAX up to the given max', () => {
    expect(clampZoom(2.5, DIAGRAM_ZOOM_MAX)).toBe(2.5);
    expect(clampZoom(3.0, DIAGRAM_ZOOM_MAX)).toBe(3.0);
  });

  test('clamps above the given max', () => {
    expect(clampZoom(3.5, DIAGRAM_ZOOM_MAX)).toBe(DIAGRAM_ZOOM_MAX);
  });

  test('still clamps at ZOOM_MIN', () => {
    expect(clampZoom(0.1, DIAGRAM_ZOOM_MAX)).toBe(ZOOM_MIN);
  });

  test('defaults to ZOOM_MAX when max is omitted (existing behavior)', () => {
    expect(clampZoom(2.5)).toBe(ZOOM_MAX);
  });
});

describe('stepZoom with custom max', () => {
  test('steps beyond 200% up to 300%', () => {
    expect(stepZoom(2.0, ZOOM_STEP, DIAGRAM_ZOOM_MAX)).toBe(2.25);
    expect(stepZoom(2.75, ZOOM_STEP, DIAGRAM_ZOOM_MAX)).toBe(3.0);
  });

  test('clamps at the given max', () => {
    expect(stepZoom(3.0, ZOOM_STEP, DIAGRAM_ZOOM_MAX)).toBe(DIAGRAM_ZOOM_MAX);
  });

  test('defaults to ZOOM_MAX when max is omitted (existing behavior)', () => {
    expect(stepZoom(2.0, ZOOM_STEP)).toBe(ZOOM_MAX);
  });
});

describe('wheelZoom with custom max', () => {
  test('zooms in beyond 200% with custom max', () => {
    expect(wheelZoom(2.0, -25, DIAGRAM_ZOOM_MAX)).toBe(2.25);
  });

  test('clamps at the given max', () => {
    expect(wheelZoom(3.0, -100, DIAGRAM_ZOOM_MAX)).toBe(DIAGRAM_ZOOM_MAX);
  });

  test('defaults to ZOOM_MAX when max is omitted (existing behavior)', () => {
    expect(wheelZoom(2.0, -100)).toBe(ZOOM_MAX);
  });
});

describe('diagramScrollHeight', () => {
  // 枠(.diagram-zoom-scroll)の高さ: ズーム後の実寸とビューポート上限の小さい方。
  // ズーム後の実寸 = naturalHeight * diagramZoom * BASE_SCALE
  // ビューポート上限 = (viewportHeight - 64) / globalZoom

  test('returns BASE_SCALE-adjusted height at 100% when it fits the viewport', () => {
    expect(diagramScrollHeight(300, 1, 800, 1)).toBe(300 * BASE_SCALE);
  });

  test('grows with diagram zoom while under the viewport cap', () => {
    expect(diagramScrollHeight(300, 2, 800, 1)).toBe(300 * 2 * BASE_SCALE);
  });

  test('caps at viewport height when zoomed content exceeds it', () => {
    const cap = (800 - 64) / 1;
    expect(diagramScrollHeight(600, 3, 800, 1)).toBeCloseTo(cap, 5);
  });

  test('global zoom shrinks the cap (layout px vs real px)', () => {
    const cap = (800 - 64) / 2;
    expect(diagramScrollHeight(400, 2, 800, 2)).toBeCloseTo(cap, 5);
  });

  test('taller viewport raises the cap', () => {
    const cap = (1200 - 64) / 1;
    expect(diagramScrollHeight(600, 3, 1200, 1)).toBeCloseTo(cap, 5);
  });
});

describe('imageFitSize', () => {
  test('shrinks a wide image to fit the available width, preserving aspect ratio', () => {
    expect(imageFitSize(4000, 1000, 768, 568)).toEqual({ width: 768, height: 192 });
  });

  test('shrinks a tall image to fit the available height, preserving aspect ratio', () => {
    const fit = imageFitSize(800, 3000, 768, 568);
    expect(fit.height).toBe(568);
    expect(fit.width).toBeCloseTo((800 / 3000) * 568, 5);
  });

  test('does not upscale an image smaller than the available area', () => {
    expect(imageFitSize(200, 100, 768, 568)).toEqual({ width: 200, height: 100 });
  });

  test('returns the natural size unchanged when available size is not known (zero/negative)', () => {
    expect(imageFitSize(400, 300, 0, 0)).toEqual({ width: 400, height: 300 });
    expect(imageFitSize(400, 300, -1, 500)).toEqual({ width: 400, height: 300 });
  });
});

describe('pageScrollStep', () => {
  test('is PAGE_SCROLL_RATIO(90%) of the client height', () => {
    expect(pageScrollStep(800)).toBeCloseTo(800 * PAGE_SCROLL_RATIO, 5);
    expect(pageScrollStep(1000)).toBeCloseTo(900, 5);
  });

  test('scales with client height (window size)', () => {
    expect(pageScrollStep(400)).toBeLessThan(pageScrollStep(800));
  });
});

describe('halfPageScrollStep', () => {
  test('is exactly half of pageScrollStep', () => {
    expect(halfPageScrollStep(800)).toBeCloseTo(pageScrollStep(800) / 2, 5);
  });

  test('scales with client height (window size)', () => {
    expect(halfPageScrollStep(1000)).toBeCloseTo(450, 5);
  });
});

describe('lineScrollStep', () => {
  test('parses a CSS computed line-height string', () => {
    expect(lineScrollStep('22.4px', DEFAULT_LINE_SCROLL_STEP)).toBeCloseTo(22.4, 5);
  });

  test('falls back when line-height is not a number (e.g. "normal")', () => {
    expect(lineScrollStep('normal', DEFAULT_LINE_SCROLL_STEP)).toBe(DEFAULT_LINE_SCROLL_STEP);
  });

  test('falls back when line-height is missing', () => {
    // @ts-expect-error -- 契約外の undefined（line-height が取れない）に対する縮退を確かめる
    expect(lineScrollStep(undefined, DEFAULT_LINE_SCROLL_STEP)).toBe(DEFAULT_LINE_SCROLL_STEP);
  });
});

describe('isHostFeatureEnabled', () => {
  test('未注入(undefined/null)の場合は常に有効とみなす', () => {
    expect(isHostFeatureEnabled(undefined, 'loadMore')).toBe(true);
    // @ts-expect-error -- 契約外の null（未注入）を有効とみなすことを確かめる
    expect(isHostFeatureEnabled(null, 'spaceScroll')).toBe(true);
  });

  test('キー未指定(空オブジェクト)の場合はそのキーを有効とみなす', () => {
    expect(isHostFeatureEnabled({}, 'loadMore')).toBe(true);
  });

  test('明示的に false が指定されたキーのみ無効とみなす', () => {
    expect(isHostFeatureEnabled({ loadMore: false }, 'loadMore')).toBe(false);
    expect(isHostFeatureEnabled({ loadMore: false }, 'spaceScroll')).toBe(true);
  });

  test('true が指定されたキーは有効とみなす', () => {
    expect(isHostFeatureEnabled({ spaceScroll: true }, 'spaceScroll')).toBe(true);
  });
});

describe('resolveScrollKey', () => {
  test('Space scrolls down a full page', () => {
    expect(resolveScrollKey(' ', false)).toEqual({ down: true, amount: 'page' });
  });

  test('Shift+Space scrolls up (back) a full page, same amount as plain Space', () => {
    expect(resolveScrollKey(' ', true)).toEqual({ down: false, amount: 'page' });
  });

  test('Backspace is no longer handled (back-scroll removed)', () => {
    expect(resolveScrollKey('Backspace', false)).toBeNull();
    expect(resolveScrollKey('Backspace', true)).toBeNull();
  });

  test('ArrowDown/ArrowUp scroll one line without Shift', () => {
    expect(resolveScrollKey('ArrowDown', false)).toEqual({ down: true, amount: 'line' });
    expect(resolveScrollKey('ArrowUp', false)).toEqual({ down: false, amount: 'line' });
  });

  test('Shift+ArrowDown/ArrowUp scroll half a page', () => {
    expect(resolveScrollKey('ArrowDown', true)).toEqual({ down: true, amount: 'half' });
    expect(resolveScrollKey('ArrowUp', true)).toEqual({ down: false, amount: 'half' });
  });

  test('vim keys j/k behave the same as ArrowDown/ArrowUp', () => {
    expect(resolveScrollKey('j', false)).toEqual({ down: true, amount: 'line' });
    expect(resolveScrollKey('k', false)).toEqual({ down: false, amount: 'line' });
    expect(resolveScrollKey('j', true)).toEqual({ down: true, amount: 'half' });
    expect(resolveScrollKey('k', true)).toEqual({ down: false, amount: 'half' });
  });

  test('unrelated keys are not handled', () => {
    expect(resolveScrollKey('a', false)).toBeNull();
    expect(resolveScrollKey('Enter', false)).toBeNull();
  });
});

describe('markdownFontSize', () => {
  var MACOS_DEFAULT_BODY = 13;

  test('at default system size (13pt) returns web-standard 16px', () => {
    expect(markdownFontSize(13)).toBe(16);
  });

  test('scales proportionally to system text size', () => {
    expect(markdownFontSize(16)).toBeCloseTo(16 * (16 / MACOS_DEFAULT_BODY));
    expect(markdownFontSize(11)).toBeCloseTo(16 * (11 / MACOS_DEFAULT_BODY));
  });

  test('accepts numeric strings', () => {
    expect(markdownFontSize('13')).toBe(16);
  });

  test('falls back to 16 (web-standard baseline) for invalid input', () => {
    // @ts-expect-error -- 契約外の引数省略に対する既定値を確かめる
    expect(markdownFontSize()).toBe(16);
    expect(markdownFontSize('abc')).toBe(16);
    expect(markdownFontSize(0)).toBe(16);
    expect(markdownFontSize(-3)).toBe(16);
  });
});

describe('escapeHtml', () => {
  test('escapes HTML special characters', () => {
    expect(escapeHtml('<b a="c">&</b>')).toBe('&lt;b a=&quot;c&quot;&gt;&amp;&lt;/b&gt;');
  });

  test('passes plain text through', () => {
    expect(escapeHtml('let x = 1')).toBe('let x = 1');
  });

  test('stringifies non-string input', () => {
    expect(escapeHtml(null)).toBe('null');
  });
});

describe('renderCodeHtml', () => {
  test('known language produces full-page hljs markup', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift', false);
    expect(result.startsWith('<pre><code class="hljs language-swift">')).toBe(true);
    expect(result).toContain('hljs-keyword');
    expect(result.endsWith('</code></pre>')).toBe(true);
  });

  test('行番号なしでも行単位テーブル構造で包む(ガイド描画のため統一)', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift', false);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-content"');
    // 行番号セルは付かない
    expect(result).not.toContain('<td class="line-number">');
  });

  test('unsupported language falls back to escaped line-based block', () => {
    const result = renderCodeHtml(hljs, '<b>raw</b>', 'no-such-lang-xyz', false);
    expect(result.startsWith('<pre><code>')).toBe(true);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('&lt;b&gt;raw&lt;/b&gt;');
    expect(result).not.toContain('<td class="line-number">');
  });

  test('missing hljs falls back to escaped line-based block', () => {
    const result = renderCodeHtml(null, 'const x = 1;', 'javascript', false);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('const x = 1;');
  });

  test('escapes HTML in fallback path (XSS)', () => {
    const result = renderCodeHtml(null, '<script>alert(1)</script>', 'javascript', false);
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });
});

describe('renderCodeHtml with line numbers', () => {
  test('showLineNumbers=true wraps output in a table with line numbers', () => {
    const result = renderCodeHtml(hljs, 'line1\nline2\nline3', 'plaintext', true);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).toContain('<td class="line-number">2</td>');
    expect(result).toContain('<td class="line-number">3</td>');
    expect(result).toContain('<td class="line-content">');
  });

  test('showLineNumbers=false は行番号セルなしの行単位テーブルを返す', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift', false);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-content"');
    expect(result).not.toContain('<td class="line-number">');
    expect(result).toContain('<pre><code');
  });

  test('showLineNumbers 省略時は行番号セルを付けない', () => {
    // @ts-expect-error -- showLineNumbers の省略が行番号なしになることを確かめる
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift');
    expect(result).not.toContain('<td class="line-number">');
  });

  test('single line produces one row', () => {
    const result = renderCodeHtml(null, 'hello', 'plaintext', true);
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).not.toContain('<td class="line-number">2</td>');
  });

  test('empty content produces single empty row', () => {
    const result = renderCodeHtml(null, '', 'plaintext', true);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-number">1</td>');
  });

  test('HTML is escaped in line content', () => {
    const result = renderCodeHtml(null, '<script>alert(1)</script>', 'plaintext', true);
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });

  test('hljs highlighted code is split into lines and wrapped', () => {
    const result = renderCodeHtml(hljs, 'let x = 1\nlet y = 2', 'swift', true);
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).toContain('<td class="line-number">2</td>');
    expect(result).toContain('hljs');
  });

  test('multi-line hljs span (block comment) stays balanced per row', () => {
    const result = renderCodeHtml(hljs, '/* a\nb */', 'swift', true);
    // 各 <td class="line-content"> 内で <span> の開閉が釣り合っていること
    const cells = result.match(/<td class="line-content">.*?<\/td>/gu)!;
    expect(cells).toHaveLength(2);
    for (const cell of cells) {
      const opens = (cell.match(/<span\b/gu) || []).length;
      const closes = (cell.match(/<\/span>/gu) || []).length;
      expect(opens).toBe(closes);
    }
    // 2 行目はコメント色の span で開き直されている
    expect(cells[1]).toMatch(/^<td class="line-content"><span[^>]*hljs-comment/u);
  });
});

describe('wrapWithLineNumbers', () => {
  test('span crossing a newline is closed at row end and reopened on the next row', () => {
    const html = wrapWithLineNumbers('<span class="x">a\nb</span>', false);
    expect(html).toContain('<td class="line-content"><span class="x">a</span></td>');
    expect(html).toContain('<td class="line-content"><span class="x">b</span></td>');
  });

  test('nested spans are reopened in order', () => {
    const html = wrapWithLineNumbers('<span class="o"><span class="i">a\nb</span></span>', false);
    expect(html).toContain(
      '<td class="line-content"><span class="o"><span class="i">a</span></span></td>',
    );
    expect(html).toContain(
      '<td class="line-content"><span class="o"><span class="i">b</span></span></td>',
    );
  });

  test('balanced single-line spans are left untouched', () => {
    const html = wrapWithLineNumbers('<span class="x">a</span>\nplain', false);
    expect(html).toContain('<td class="line-content"><span class="x">a</span></td>');
    expect(html).toContain('<td class="line-content">plain</td>');
  });
});
