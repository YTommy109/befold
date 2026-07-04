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
  markdownFontSize,
} = require('../viewer');

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
