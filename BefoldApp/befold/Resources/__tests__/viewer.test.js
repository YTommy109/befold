const {
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
  effectiveZoom,
  parseStoredZoom,
  mermaidTheme,
  sanitizeLang,
  highlightCode,
  diagramScrollHeight,
  imageFitSize,
  PAGE_SCROLL_RATIO,
  DEFAULT_LINE_SCROLL_STEP,
  pageScrollStep,
  halfPageScrollStep,
  lineScrollStep,
  resolveScrollKey,
  markdownFontSize,
  escapeHtml,
  renderCodeHtml,
  wrapWithLineNumbers,
  parseCsv,
  buildTableHtml,
  renderCsvSourceHtml,
  csvSourceInnerHtml,
  CSV_COL_COUNT,
  isSafeLinkURL,
  buildFindRegExp,
  buildLineNumberRows,
  reflowSpanBalancedLines,
  csvRowsHtml,
  codeChunkInnerHtml,
  lastLines,
} = require('../../../BefoldKit/Resources/viewer');

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

describe('effectiveZoom', () => {
  test('returns zoom as-is (BASE_SCALE is applied per-diagram, not globally)', () => {
    expect(effectiveZoom(1.0)).toBe(1.0);
    expect(effectiveZoom(2.0)).toBe(2.0);
  });

  test('returns 0 for zoom 0', () => {
    expect(effectiveZoom(0)).toBe(0);
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
    expect(parseStoredZoom(undefined)).toBe(ZOOM_DEFAULT);
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
  const hljs = require('highlight.js');

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
    expect(highlightCode(hljs, 'foo', undefined)).toBe('');
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
  const hljs = require('highlight.js');
  const markdownit = require('markdown-it');
  // viewer.html の markdownit 初期化と同じ配線
  const md = markdownit({
    html: true,
    linkify: true,
    typographer: true,
    highlight: function(str, lang) {
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
    expect(lineScrollStep(undefined, DEFAULT_LINE_SCROLL_STEP)).toBe(DEFAULT_LINE_SCROLL_STEP);
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
    expect(markdownFontSize(undefined)).toBe(16);
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
  const hljs = require('highlight.js');

  test('known language produces full-page hljs markup', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift');
    expect(result.startsWith('<pre><code class="hljs language-swift">')).toBe(true);
    expect(result).toContain('hljs-keyword');
    expect(result.endsWith('</code></pre>')).toBe(true);
  });

  test('unsupported language falls back to escaped plain block', () => {
    const result = renderCodeHtml(hljs, '<b>raw</b>', 'no-such-lang-xyz');
    expect(result).toBe('<pre><code>&lt;b&gt;raw&lt;/b&gt;</code></pre>');
  });

  test('missing hljs falls back to escaped plain block', () => {
    const result = renderCodeHtml(null, 'const x = 1;', 'javascript');
    expect(result).toBe('<pre><code>const x = 1;</code></pre>');
  });

  test('escapes HTML in fallback path (XSS)', () => {
    const result = renderCodeHtml(null, '<script>alert(1)</script>', 'javascript');
    expect(result).not.toContain('<script>');
    expect(result).toContain('&lt;script&gt;');
  });
});

describe('renderCodeHtml with line numbers', () => {
  const hljs = require('highlight.js');

  test('showLineNumbers=true wraps output in a table with line numbers', () => {
    const result = renderCodeHtml(hljs, 'line1\nline2\nline3', 'plaintext', true);
    expect(result).toContain('<table class="code-table">');
    expect(result).toContain('<td class="line-number">1</td>');
    expect(result).toContain('<td class="line-number">2</td>');
    expect(result).toContain('<td class="line-number">3</td>');
    expect(result).toContain('<td class="line-content">');
  });

  test('showLineNumbers=false returns plain pre/code (existing behavior)', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift', false);
    expect(result).not.toContain('code-table');
    expect(result).toContain('<pre><code');
  });

  test('showLineNumbers defaults to false when omitted', () => {
    const result = renderCodeHtml(hljs, 'let x = 1', 'swift');
    expect(result).not.toContain('code-table');
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
    const cells = result.match(/<td class="line-content">.*?<\/td>/g);
    expect(cells).toHaveLength(2);
    for (const cell of cells) {
      const opens = (cell.match(/<span\b/g) || []).length;
      const closes = (cell.match(/<\/span>/g) || []).length;
      expect(opens).toBe(closes);
    }
    // 2 行目はコメント色の span で開き直されている
    expect(cells[1]).toMatch(/^<td class="line-content"><span[^>]*hljs-comment/);
  });
});

describe('wrapWithLineNumbers', () => {
  test('span crossing a newline is closed at row end and reopened on the next row', () => {
    const html = wrapWithLineNumbers('<span class="x">a\nb</span>');
    expect(html).toContain('<td class="line-content"><span class="x">a</span></td>');
    expect(html).toContain('<td class="line-content"><span class="x">b</span></td>');
  });

  test('nested spans are reopened in order', () => {
    const html = wrapWithLineNumbers('<span class="o"><span class="i">a\nb</span></span>');
    expect(html).toContain(
      '<td class="line-content"><span class="o"><span class="i">a</span></span></td>'
    );
    expect(html).toContain(
      '<td class="line-content"><span class="o"><span class="i">b</span></span></td>'
    );
  });

  test('balanced single-line spans are left untouched', () => {
    const html = wrapWithLineNumbers('<span class="x">a</span>\nplain');
    expect(html).toContain('<td class="line-content"><span class="x">a</span></td>');
    expect(html).toContain('<td class="line-content">plain</td>');
  });
});

describe('FileType.swift の言語名契約', () => {
  // FileType.codeExtensionLanguages(FileType.swift)の値と同期させること。
  // npm の highlight.js ではなく同梱の highlight.min.js に対して検証する
  // (同梱ビルドは言語のサブセットのため、npm 版では偽陽性になる)。
  const bundledHljs = require('../../../BefoldKit/Resources/highlight.min.js');
  const LANGUAGES = [
    'swift', 'python', 'go', 'rust', 'javascript', 'typescript',
    'java', 'kotlin', 'c', 'cpp', 'csharp', 'objectivec',
    'ruby', 'php', 'perl', 'lua', 'r', 'sql', 'bash',
    'graphql', 'css', 'scss', 'less', 'ini', 'diff', 'makefile',
    'json', 'yaml', 'xml', 'vbnet',
  ];

  test.each(LANGUAGES)('%s is available in the bundled highlight.min.js', (lang) => {
    expect(bundledHljs.getLanguage(lang)).toBeTruthy();
  });
});

describe('parseCsv', () => {
  test('parses simple comma-separated rows', () => {
    expect(parseCsv('a,b,c\n1,2,3', ',')).toEqual([['a','b','c'],['1','2','3']]);
  });

  test('parses tab-separated rows', () => {
    expect(parseCsv('a\tb\tc\n1\t2\t3', '\t')).toEqual([['a','b','c'],['1','2','3']]);
  });

  test('handles quoted fields with commas', () => {
    expect(parseCsv('"a,b",c\n1,2', ',')).toEqual([['a,b','c'],['1','2']]);
  });

  test('handles escaped quotes inside quoted fields', () => {
    expect(parseCsv('"say ""hello""",b\n1,2', ',')).toEqual([['say "hello"','b'],['1','2']]);
  });

  test('handles newlines inside quoted fields', () => {
    expect(parseCsv('"line1\nline2",b\n1,2', ',')).toEqual([['line1\nline2','b'],['1','2']]);
  });

  test('handles empty fields', () => {
    expect(parseCsv(',b,\n1,,3', ',')).toEqual([['','b',''],['1','','3']]);
  });

  test('handles single row without trailing newline', () => {
    expect(parseCsv('a,b,c', ',')).toEqual([['a','b','c']]);
  });

  test('handles trailing newline', () => {
    expect(parseCsv('a,b\n1,2\n', ',')).toEqual([['a','b'],['1','2']]);
  });

  test('handles CRLF line endings', () => {
    expect(parseCsv('a,b\r\n1,2', ',')).toEqual([['a','b'],['1','2']]);
  });

  test('returns empty array for empty string', () => {
    expect(parseCsv('', ',')).toEqual([]);
  });

  test('handles single field', () => {
    expect(parseCsv('a', ',')).toEqual([['a']]);
  });
});

describe('buildTableHtml', () => {
  test('builds table with thead and tbody', () => {
    const html = buildTableHtml([['Name','Age'],['Alice','30'],['Bob','25']]);
    expect(html).toContain('<table>');
    expect(html).toContain('<thead>');
    expect(html).toContain('<th>Name</th>');
    expect(html).toContain('<th>Age</th>');
    expect(html).toContain('<tbody>');
    expect(html).toContain('<td>Alice</td>');
    expect(html).toContain('<td>30</td>');
    expect(html).toContain('</table>');
  });

  test('header-only table has empty tbody', () => {
    const html = buildTableHtml([['A','B']]);
    expect(html).toContain('<thead>');
    expect(html).toContain('<tbody></tbody>');
  });

  test('empty rows returns empty string', () => {
    expect(buildTableHtml([])).toBe('');
  });

  test('escapes HTML in cell values', () => {
    const html = buildTableHtml([['<script>'],['&"']]);
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('&amp;&quot;');
  });

  test('pads short rows with empty cells', () => {
    const html = buildTableHtml([['A','B','C'],['1']]);
    const tdCount = (html.match(/<td>/g) || []).length + (html.match(/<td>[^<]*<\/td>/g) || []).length;
    // 1行目は th×3、2行目は td が 3 つ(うち 2 つは空)
    expect(html).toContain('<td>1</td>');
    expect(html.match(/<td><\/td>/g).length).toBe(2);
  });
});

describe('renderCsvSourceHtml', () => {
  test('wraps output in pre/code', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',');
    expect(html.startsWith('<pre><code class="csv-source">')).toBe(true);
    expect(html.endsWith('</code></pre>')).toBe(true);
  });

  test('applies rotating colors to columns', () => {
    const html = renderCsvSourceHtml('a,b,c', ',');
    // 各列が異なる色の span で囲まれている
    expect(html).toContain('<span class="csv-col-0">');
    expect(html).toContain('<span class="csv-col-1">');
    expect(html).toContain('<span class="csv-col-2">');
  });

  test('delimiter is not wrapped in a color span', () => {
    const html = renderCsvSourceHtml('a,b', ',');
    // delimiter はそのまま表示される
    expect(html).toContain('</span>,<span');
  });

  test('escapes HTML in field values', () => {
    const html = renderCsvSourceHtml('<b>,&', ',');
    expect(html).toContain('&lt;b&gt;');
    expect(html).toContain('&amp;');
  });

  test('handles tab delimiter', () => {
    const html = renderCsvSourceHtml('a\tb', '\t');
    expect(html).toContain('</span>\t<span');
  });

  test('returns empty pre/code for empty string', () => {
    const html = renderCsvSourceHtml('', ',');
    expect(html).toBe('<pre><code class="csv-source"></code></pre>');
  });

  test('handles quoted fields preserving quotes in source view', () => {
    const html = renderCsvSourceHtml('"a,b",c', ',');
    // ソース表示ではクオート付きフィールドを1つの色で表示する
    expect(html).toContain('<span class="csv-col-0">&quot;a,b&quot;</span>');
    expect(html).toContain('<span class="csv-col-1">c</span>');
  });
});

describe('renderCsvSourceHtml with line numbers', () => {
  test('showLineNumbers=true wraps output in a table with line numbers', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',', true);
    expect(html).toContain('<table class="code-table">');
    expect(html).toContain('<td class="line-number">1</td>');
    expect(html).toContain('<td class="line-number">2</td>');
    expect(html).toContain('csv-col-');
  });

  test('showLineNumbers=false returns existing format', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',', false);
    expect(html).not.toContain('code-table');
  });

  test('showLineNumbers defaults to false when omitted', () => {
    const html = renderCsvSourceHtml('a,b', ',');
    expect(html).not.toContain('code-table');
  });

  test('quoted cell with embedded newline keeps csv-col spans balanced per row', () => {
    const html = renderCsvSourceHtml('a,"x\ny",b', ',', true);
    const cells = html.match(/<td class="line-content">.*?<\/td>/g);
    expect(cells).toHaveLength(2);
    for (const cell of cells) {
      const opens = (cell.match(/<span\b/g) || []).length;
      const closes = (cell.match(/<\/span>/g) || []).length;
      expect(opens).toBe(closes);
    }
  });
});

describe('csvSourceInnerHtml', () => {
  test('returns empty string for empty content', () => {
    expect(csvSourceInnerHtml('', ',')).toBe('');
  });

  test('is the exact body renderCsvSourceHtml wraps in pre/code (no line numbers)', () => {
    const content = 'a,b,c\n1,"x,y",3';
    const inner = csvSourceInnerHtml(content, ',');
    expect(renderCsvSourceHtml(content, ',')).toBe(
      '<pre><code class="csv-source">' + inner + '</code></pre>'
    );
  });

  test('produces per-row rainbow spans usable for chunked append', () => {
    const inner = csvSourceInnerHtml('1,2,3', ',');
    expect(inner).toBe(
      '<span class="csv-col-0">1</span>,<span class="csv-col-1">2</span>,<span class="csv-col-2">3</span>'
    );
  });

  test('preserves a trailing newline so the next appended chunk does not merge into the last line', () => {
    const inner = csvSourceInnerHtml('1,2,3\n', ',');
    expect(inner.endsWith('\n')).toBe(true);
  });

  test('does not add a trailing newline when the content has none', () => {
    const inner = csvSourceInnerHtml('1,2,3', ',');
    expect(inner.endsWith('\n')).toBe(false);
  });
});

describe('isSafeLinkURL', () => {
  test('allows all data:image subtypes (svg/bmp/ico included)', () => {
    expect(isSafeLinkURL('data:image/png;base64,AAAA')).toBe(true);
    expect(isSafeLinkURL('data:image/jpeg;base64,AAAA')).toBe(true);
    expect(isSafeLinkURL('data:image/gif;base64,AAAA')).toBe(true);
    expect(isSafeLinkURL('data:image/webp;base64,AAAA')).toBe(true);
    expect(isSafeLinkURL('data:image/svg+xml;base64,AAAA')).toBe(true);
    expect(isSafeLinkURL('data:image/bmp;base64,AAAA')).toBe(true);
    expect(isSafeLinkURL('data:image/x-icon;base64,AAAA')).toBe(true);
  });

  test('is case-insensitive and tolerant of surrounding whitespace', () => {
    expect(isSafeLinkURL('  DATA:IMAGE/SVG+XML;base64,AAAA  ')).toBe(true);
  });

  test('blocks non-image data URIs', () => {
    expect(isSafeLinkURL('data:text/html;base64,PHNjcmlwdD4=')).toBe(false);
    expect(isSafeLinkURL('data:application/javascript,alert(1)')).toBe(false);
  });

  test('blocks dangerous schemes', () => {
    expect(isSafeLinkURL('javascript:alert(1)')).toBe(false);
    expect(isSafeLinkURL('vbscript:msgbox(1)')).toBe(false);
    expect(isSafeLinkURL('file:///etc/passwd')).toBe(false);
  });

  test('allows ordinary links and relative paths', () => {
    expect(isSafeLinkURL('https://example.com/a.png')).toBe(true);
    expect(isSafeLinkURL('http://example.com')).toBe(true);
    expect(isSafeLinkURL('./img/logo.png')).toBe(true);
    expect(isSafeLinkURL('other.md#section')).toBe(true);
    expect(isSafeLinkURL('#anchor')).toBe(true);
    expect(isSafeLinkURL('mailto:a@example.com')).toBe(true);
  });
});

describe('buildFindRegExp', () => {
  test('plain mode matches literal substrings', () => {
    const re = buildFindRegExp('cat', { caseSensitive: false, wholeWord: false, useRegex: false });
    expect(re.test('the cat sat')).toBe(true);
  });

  test('plain mode escapes regex special characters', () => {
    const re = buildFindRegExp('a.b*c', { caseSensitive: false, wholeWord: false, useRegex: false });
    expect(re.test('a.b*c')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('aXbYYc')).toBe(false);
  });

  test('caseSensitive true only matches exact case', () => {
    const re = buildFindRegExp('Cat', { caseSensitive: true, wholeWord: false, useRegex: false });
    expect(re.test('Cat')).toBe(true);
    expect(re.test('cat')).toBe(false);
  });

  test('caseSensitive false (default) matches regardless of case', () => {
    const re = buildFindRegExp('Cat', { caseSensitive: false, wholeWord: false, useRegex: false });
    expect(re.test('cat')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('CAT')).toBe(true);
  });

  test('wholeWord true matches only at word boundaries', () => {
    const re = buildFindRegExp('cat', { caseSensitive: false, wholeWord: true, useRegex: false });
    expect(re.test('the cat sat')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('category')).toBe(false);
  });

  test('useRegex true uses the query as-is as regex source', () => {
    const re = buildFindRegExp('a+', { caseSensitive: false, wholeWord: false, useRegex: true });
    expect(re.test('aaa')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('b')).toBe(false);
  });

  test('useRegex true with invalid regex syntax returns null', () => {
    expect(buildFindRegExp('(', { caseSensitive: false, wholeWord: false, useRegex: true })).toBe(null);
  });

  test('empty query returns null', () => {
    expect(buildFindRegExp('', { caseSensitive: false, wholeWord: false, useRegex: false })).toBe(null);
  });

  test('returned RegExp always has the global flag set', () => {
    const re = buildFindRegExp('cat', { caseSensitive: true, wholeWord: false, useRegex: false });
    expect(re.global).toBe(true);
  });
});

describe('buildLineNumberRows', () => {
  test('numbers rows from startLine', () => {
    const rows = buildLineNumberRows('a\nb', 42);
    expect(rows).toContain('<td class="line-number">42</td><td class="line-content">a</td>');
    expect(rows).toContain('<td class="line-number">43</td><td class="line-content">b</td>');
  });

  test('multi-line span spanning 3 lines is closed and reopened per row starting at 42', () => {
    const rows = buildLineNumberRows('<span class="hljs-comment">/*\nbody\n*/</span>', 42);
    expect(rows).toContain(
      '<tr><td class="line-number">42</td><td class="line-content"><span class="hljs-comment">/*</span></td></tr>'
    );
    expect(rows).toContain(
      '<tr><td class="line-number">43</td><td class="line-content"><span class="hljs-comment">body</span></td></tr>'
    );
    expect(rows).toContain(
      '<tr><td class="line-number">44</td><td class="line-content"><span class="hljs-comment">*/</span></td></tr>'
    );
    // 各行のセルは自己完結: 行ごとに open と close の数が一致する
    const cells = rows.match(/<td class="line-content">.*?<\/td>/g);
    for (const cell of cells) {
      const opens = (cell.match(/<span\b/g) || []).length;
      const closes = (cell.match(/<\/span>/g) || []).length;
      expect(opens).toBe(closes);
    }
  });

  test('drops a single trailing empty line (highlight.js trailing newline)', () => {
    const rows = buildLineNumberRows('a\nb\n', 1);
    expect((rows.match(/<tr>/g) || []).length).toBe(2);
  });

  test('wrapWithLineNumbers equals code-table wrapper around buildLineNumberRows from line 1', () => {
    const input = '<span class="x">a\nb</span>\nplain';
    expect(wrapWithLineNumbers(input)).toBe(
      '<table class="code-table">' + buildLineNumberRows(input, 1) + '</table>'
    );
  });
});

describe('csvRowsHtml', () => {
  test('builds tr/td rows and pads short rows up to minCols', () => {
    const html = csvRowsHtml([['a', 'b'], ['c']], 3);
    expect(html).toBe(
      '<tr><td>a</td><td>b</td><td></td></tr>'
      + '<tr><td>c</td><td></td><td></td></tr>'
    );
  });

  test('a row longer than minCols keeps all its cells', () => {
    const html = csvRowsHtml([['a', 'b', 'c']], 2);
    expect(html).toBe('<tr><td>a</td><td>b</td><td>c</td></tr>');
  });

  test('escapes HTML special characters in cells', () => {
    const html = csvRowsHtml([['<b>', 'a&b', '"q"']], 0);
    expect(html).toBe('<tr><td>&lt;b&gt;</td><td>a&amp;b</td><td>&quot;q&quot;</td></tr>');
  });

  test('empty rows array produces empty string', () => {
    expect(csvRowsHtml([], 3)).toBe('');
  });
});

describe('codeChunkInnerHtml', () => {
  const hljs = require('highlight.js');

  test('strips the pre/code wrapper from highlighted output', () => {
    const inner = codeChunkInnerHtml(hljs, 'const x = 1;', 'javascript');
    expect(inner).not.toMatch(/<pre>|<code|<\/code>|<\/pre>/);
    expect(inner).toContain('hljs-keyword');
    expect(inner).toBe(
      highlightCode(hljs, 'const x = 1;', 'javascript')
        .replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '')
    );
  });

  test('falls back to escapeHtml when hljs is unavailable', () => {
    expect(codeChunkInnerHtml(null, '<b> & "x"', 'javascript')).toBe('&lt;b&gt; &amp; &quot;x&quot;');
  });

  test('falls back to escapeHtml when the language is unknown', () => {
    expect(codeChunkInnerHtml(hljs, 'a < b', 'no-such-lang')).toBe('a &lt; b');
  });

  test('without context, a block comment continuation is misidentified as code', () => {
    // チャンク境界後の 'still comment' は、文脈なしでは通常コードとして扱われる
    // (これが TASK-14 のバグ本体)。
    const continuation = codeChunkInnerHtml(hljs, 'still comment */\nconst y = 2;', 'javascript');
    expect(continuation).not.toContain('hljs-comment');
  });

  test('with context spanning an open block comment, the continuation stays a comment', () => {
    const context = '/* comment start\n';
    const continuation = codeChunkInnerHtml(hljs, 'still comment */\nconst y = 2;', 'javascript', context);
    const lines = continuation.split('\n');
    expect(lines).toHaveLength(2);
    expect(lines[0]).toContain('hljs-comment');
    expect(lines[0]).toContain('still comment');
    expect(lines[1]).toContain('hljs-keyword');
  });

  test('context lines are dropped and do not duplicate into the returned HTML', () => {
    const context = 'const a = 1;\nconst b = 2;\n';
    const continuation = codeChunkInnerHtml(hljs, 'const c = 3;', 'javascript', context);
    expect(continuation).not.toContain('a = 1');
    expect(continuation).not.toContain('b = 2');
    expect(continuation).toContain('hljs-number">3');
  });

  test('with context, preserves a trailing newline so the next chunk does not merge into the last line', () => {
    const context = 'const a = 1;\n';
    const continuation = codeChunkInnerHtml(hljs, 'const b = 2;\n', 'javascript', context);
    expect(continuation.endsWith('\n')).toBe(true);
  });

  test('with context, does not add a trailing newline when the chunk has none', () => {
    const context = 'const a = 1;\n';
    const continuation = codeChunkInnerHtml(hljs, 'const b = 2;', 'javascript', context);
    expect(continuation.endsWith('\n')).toBe(false);
  });

  test('with a multi-line context, output matches highlighting the same text without a chunk split', () => {
    const full = '/* start\nmiddle\nend */\nconst z = 1;';
    const context = '/* start\nmiddle\n';
    const tail = 'end */\nconst z = 1;';
    const withContext = codeChunkInnerHtml(hljs, tail, 'javascript', context);
    const fullHighlighted = highlightCode(hljs, full, 'javascript')
      .replace(/^<pre><code[^>]*>/, '').replace(/<\/code><\/pre>$/, '');
    const fullReflowedTailLines = reflowSpanBalancedLines(fullHighlighted).slice(2).join('\n');
    expect(withContext).toBe(fullReflowedTailLines);
  });
});

describe('lastLines', () => {
  test('returns the whole string when it has fewer newlines than maxLines', () => {
    expect(lastLines('a\nb\n', 10)).toBe('a\nb\n');
  });

  test('returns the last maxLines complete lines, preserving the trailing newline', () => {
    expect(lastLines('a\nb\nc\n', 2)).toBe('b\nc\n');
  });

  test('returns empty string for empty input', () => {
    expect(lastLines('', 5)).toBe('');
  });

  test('maxLines=0 returns empty string', () => {
    expect(lastLines('a\nb\n', 0)).toBe('');
  });
});
