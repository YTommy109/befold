import * as fs from 'node:fs';
import * as path from 'node:path';

import { describe, expect, test } from '@jest/globals';
import hljs from 'highlight.js';
import bundledHljs from 'highlight.js/lib/common';

import {
  highlightCode,
  svgDataURI,
  imageDataURI,
  wrapWithLineNumbers,
  parseCsv,
  buildTableHtml,
  renderCsvSourceHtml,
  csvSourceInnerHtml,
  isSafeLinkURL,
  isLocalPathHref,
  buildFindRegExp,
  nextMatchIndex,
  prevMatchIndex,
  keptMatchIndex,
  buildLineNumberRows,
  indentColumns,
  leadingIndentInfo,
  lineContentCell,
  CODE_TAB_SIZE,
  reflowSpanBalancedLines,
  csvRowsHtml,
  codeChunkInnerHtml,
  lastLines,
} from '../viewer-src/main.js';

describe('FileType.swift の言語名契約', () => {
  // FileType.codeExtensionLanguages(FileType.swift)の値と同期させること。
  // full ビルド(192 言語)ではなく、実際にバンドルへ入る common ビルド(36 言語)に
  // 対して検証する。full だと同梱していない言語まで通ってしまい偽陽性になる
  // (取り込み口は viewer-src/vendor.js の 1 箇所)。
  const LANGUAGES = [
    'swift',
    'python',
    'go',
    'rust',
    'javascript',
    'typescript',
    'java',
    'kotlin',
    'c',
    'cpp',
    'csharp',
    'objectivec',
    'ruby',
    'php',
    'perl',
    'lua',
    'r',
    'sql',
    'bash',
    'graphql',
    'css',
    'scss',
    'less',
    'ini',
    'diff',
    'makefile',
    'json',
    'yaml',
    'xml',
    'vbnet',
  ];

  test.each(LANGUAGES)('%s is available in the bundled highlight.js common build', (lang) => {
    expect(bundledHljs.getLanguage(lang)).toBeTruthy();
  });
});

describe('parseCsv', () => {
  test('parses simple comma-separated rows', () => {
    expect(parseCsv('a,b,c\n1,2,3', ',')).toEqual([
      ['a', 'b', 'c'],
      ['1', '2', '3'],
    ]);
  });

  test('parses tab-separated rows', () => {
    expect(parseCsv('a\tb\tc\n1\t2\t3', '\t')).toEqual([
      ['a', 'b', 'c'],
      ['1', '2', '3'],
    ]);
  });

  test('handles quoted fields with commas', () => {
    expect(parseCsv('"a,b",c\n1,2', ',')).toEqual([
      ['a,b', 'c'],
      ['1', '2'],
    ]);
  });

  test('handles escaped quotes inside quoted fields', () => {
    expect(parseCsv('"say ""hello""",b\n1,2', ',')).toEqual([
      ['say "hello"', 'b'],
      ['1', '2'],
    ]);
  });

  test('handles newlines inside quoted fields', () => {
    expect(parseCsv('"line1\nline2",b\n1,2', ',')).toEqual([
      ['line1\nline2', 'b'],
      ['1', '2'],
    ]);
  });

  test('handles empty fields', () => {
    expect(parseCsv(',b,\n1,,3', ',')).toEqual([
      ['', 'b', ''],
      ['1', '', '3'],
    ]);
  });

  test('handles single row without trailing newline', () => {
    expect(parseCsv('a,b,c', ',')).toEqual([['a', 'b', 'c']]);
  });

  test('handles trailing newline', () => {
    expect(parseCsv('a,b\n1,2\n', ',')).toEqual([
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('handles CRLF line endings', () => {
    expect(parseCsv('a,b\r\n1,2', ',')).toEqual([
      ['a', 'b'],
      ['1', '2'],
    ]);
  });

  test('returns empty array for empty string', () => {
    expect(parseCsv('', ',')).toEqual([]);
  });

  test('handles single field', () => {
    expect(parseCsv('a', ',')).toEqual([['a']]);
  });

  test('unescapes escape sequences in cell values', () => {
    expect(parseCsv('a\\nb,c\\td,e\\rf', ',')).toEqual([['a\nb', 'c\td', 'e\rf']]);
  });

  test('keeps a literal backslash-n when the backslash is escaped', () => {
    expect(parseCsv('a\\\\nb', ',')).toEqual([['a\\nb']]);
  });

  test('unescapes an escaped backslash to a single backslash', () => {
    expect(parseCsv('a\\\\b', ',')).toEqual([['a\\b']]);
  });

  test('keeps an unknown escape sequence as-is', () => {
    expect(parseCsv('a\\qb', ',')).toEqual([['a\\qb']]);
  });

  test('keeps a trailing lone backslash', () => {
    expect(parseCsv('a\\', ',')).toEqual([['a\\']]);
  });
});

describe('csv escape sequences reach both table render paths', () => {
  test('buildTableHtml (initial render) emits a real newline in the cell', () => {
    const html = buildTableHtml(parseCsv('h\na\\nb', ','), ['text']);
    expect(html).toContain('<td>a\nb</td>');
  });

  test('csvRowsHtml (chunked append) emits the same cell markup', () => {
    const html = csvRowsHtml(parseCsv('a\\nb', ','), 1, ['text']);
    expect(html).toBe('<tr><td>a\nb</td></tr>');
  });
});

describe('buildTableHtml', () => {
  test('builds table with thead and tbody', () => {
    const html = buildTableHtml(
      [
        ['Name', 'Age'],
        ['Alice', '30'],
        ['Bob', '25'],
      ],
      ['text', 'text'],
    );
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
    const html = buildTableHtml([['A', 'B']], ['text', 'text']);
    expect(html).toContain('<thead>');
    expect(html).toContain('<tbody></tbody>');
  });

  test('empty rows returns empty string', () => {
    expect(buildTableHtml([], [])).toBe('');
  });

  test('escapes HTML in cell values', () => {
    const html = buildTableHtml([['<script>'], ['&"']], ['text']);
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('&amp;&quot;');
  });

  test('pads short rows with empty cells', () => {
    const html = buildTableHtml([['A', 'B', 'C'], ['1']], ['text', 'text', 'text']);
    // 1行目は th×3、2行目は td が 3 つ(うち 2 つは空)
    expect(html).toContain('<td>1</td>');
    expect(html.match(/<td><\/td>/gu)!.length).toBe(2);
  });
});

describe('renderCsvSourceHtml', () => {
  test('wraps output in pre/code', () => {
    const html = renderCsvSourceHtml('a,b\n1,2', ',', false);
    expect(html.startsWith('<pre><code class="csv-source">')).toBe(true);
    expect(html.endsWith('</code></pre>')).toBe(true);
  });

  test('applies rotating colors to columns', () => {
    const html = renderCsvSourceHtml('a,b,c', ',', false);
    // 各列が異なる色の span で囲まれている
    expect(html).toContain('<span class="csv-col-0">');
    expect(html).toContain('<span class="csv-col-1">');
    expect(html).toContain('<span class="csv-col-2">');
  });

  test('delimiter is not wrapped in a color span', () => {
    const html = renderCsvSourceHtml('a,b', ',', false);
    // delimiter はそのまま表示される
    expect(html).toContain('</span>,<span');
  });

  test('escapes HTML in field values', () => {
    const html = renderCsvSourceHtml('<b>,&', ',', false);
    expect(html).toContain('&lt;b&gt;');
    expect(html).toContain('&amp;');
  });

  test('handles tab delimiter', () => {
    const html = renderCsvSourceHtml('a\tb', '\t', false);
    expect(html).toContain('</span>\t<span');
  });

  test('returns empty pre/code for empty string', () => {
    const html = renderCsvSourceHtml('', ',', false);
    expect(html).toBe('<pre><code class="csv-source"></code></pre>');
  });

  test('handles quoted fields preserving quotes in source view', () => {
    const html = renderCsvSourceHtml('"a,b",c', ',', false);
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
    // @ts-expect-error -- showLineNumbers の省略が行番号なしになることを確かめる
    const html = renderCsvSourceHtml('a,b', ',');
    expect(html).not.toContain('code-table');
  });

  test('quoted cell with embedded newline keeps csv-col spans balanced per row', () => {
    const html = renderCsvSourceHtml('a,"x\ny",b', ',', true);
    const cells = html.match(/<td class="line-content">.*?<\/td>/gu)!;
    expect(cells).toHaveLength(2);
    for (const cell of cells) {
      const opens = (cell.match(/<span\b/gu) || []).length;
      const closes = (cell.match(/<\/span>/gu) || []).length;
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
    expect(renderCsvSourceHtml(content, ',', false)).toBe(
      '<pre><code class="csv-source">' + inner + '</code></pre>',
    );
  });

  test('produces per-row rainbow spans usable for chunked append', () => {
    const inner = csvSourceInnerHtml('1,2,3', ',');
    expect(inner).toBe(
      '<span class="csv-col-0">1</span>,<span class="csv-col-1">2</span>,<span class="csv-col-2">3</span>',
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

  test('leaves escape sequences literal so line numbers keep matching the file', () => {
    const inner = csvSourceInnerHtml('a\\nb,c', ',');
    expect(inner).toBe('<span class="csv-col-0">a\\nb</span>,<span class="csv-col-1">c</span>');
    expect(inner).not.toContain('\n');
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

describe('isLocalPathHref', () => {
  test('treats relative and absolute paths as local', () => {
    expect(isLocalPathHref('other.md')).toBe(true);
    expect(isLocalPathHref('./docs/spec.md')).toBe(true);
    expect(isLocalPathHref('../sibling/a.mmd')).toBe(true);
    expect(isLocalPathHref('/abs/path/a.md')).toBe(true);
    expect(isLocalPathHref('~/notes/a.md')).toBe(true);
    expect(isLocalPathHref('dir/file.md#section')).toBe(true);
  });

  test('treats a dotted scheme-like prefix as a path with a line suffix', () => {
    // file.md:12 は scheme="file.md" と読めてしまうため、ドットを含む
    // スキームはローカルパス扱いにする
    expect(isLocalPathHref('file.md:12')).toBe(true);
    expect(isLocalPathHref('./docs/spec.md:120:5')).toBe(true);
  });

  test('excludes URL schemes without a dot', () => {
    expect(isLocalPathHref('https://example.com/a.md')).toBe(false);
    expect(isLocalPathHref('http://example.com')).toBe(false);
    expect(isLocalPathHref('mailto:a@example.com')).toBe(false);
    expect(isLocalPathHref('tel:0312345678')).toBe(false);
    expect(isLocalPathHref('javascript:alert(1)')).toBe(false);
    expect(isLocalPathHref('data:text/plain,x')).toBe(false);
    // ドット入りスキームは除外できない
    expect(isLocalPathHref('befold-x.y:open')).toBe(true);
    expect(isLocalPathHref('x+y-z:payload')).toBe(false);
  });

  test('excludes in-document anchors', () => {
    expect(isLocalPathHref('#anchor')).toBe(false);
    expect(isLocalPathHref('#')).toBe(false);
  });

  test('excludes empty and nullish hrefs', () => {
    expect(isLocalPathHref('')).toBe(false);
    expect(isLocalPathHref(null)).toBe(false);
    // @ts-expect-error -- 契約外の引数省略（href 無し）に対する縮退を確かめる
    expect(isLocalPathHref()).toBe(false);
  });

  test('keeps colon-containing strings that are not scheme-shaped', () => {
    // スキームは英字始まりのみ。数字始まりやコロン始まりはパス候補として残す
    expect(isLocalPathHref('12:34')).toBe(true);
    expect(isLocalPathHref(':leading')).toBe(true);
    expect(isLocalPathHref('a b:c')).toBe(true);
  });
});

describe('buildFindRegExp', () => {
  test('plain mode matches literal substrings', () => {
    const re = buildFindRegExp('cat', { caseSensitive: false, wholeWord: false, useRegex: false })!;
    expect(re.test('the cat sat')).toBe(true);
  });

  test('plain mode escapes regex special characters', () => {
    const re = buildFindRegExp('a.b*c', {
      caseSensitive: false,
      wholeWord: false,
      useRegex: false,
    })!;
    expect(re.test('a.b*c')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('aXbYYc')).toBe(false);
  });

  test('caseSensitive true only matches exact case', () => {
    const re = buildFindRegExp('Cat', { caseSensitive: true, wholeWord: false, useRegex: false })!;
    expect(re.test('Cat')).toBe(true);
    expect(re.test('cat')).toBe(false);
  });

  test('caseSensitive false (default) matches regardless of case', () => {
    const re = buildFindRegExp('Cat', { caseSensitive: false, wholeWord: false, useRegex: false })!;
    expect(re.test('cat')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('CAT')).toBe(true);
  });

  test('wholeWord true matches only at word boundaries', () => {
    const re = buildFindRegExp('cat', { caseSensitive: false, wholeWord: true, useRegex: false })!;
    expect(re.test('the cat sat')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('category')).toBe(false);
  });

  test('useRegex true uses the query as-is as regex source', () => {
    const re = buildFindRegExp('a+', { caseSensitive: false, wholeWord: false, useRegex: true })!;
    expect(re.test('aaa')).toBe(true);
    re.lastIndex = 0;
    expect(re.test('b')).toBe(false);
  });

  test('useRegex true with invalid regex syntax returns null', () => {
    expect(buildFindRegExp('(', { caseSensitive: false, wholeWord: false, useRegex: true })).toBe(
      null,
    );
  });

  test('empty query returns null', () => {
    expect(buildFindRegExp('', { caseSensitive: false, wholeWord: false, useRegex: false })).toBe(
      null,
    );
  });

  test('returned RegExp always has the global flag set', () => {
    const re = buildFindRegExp('cat', { caseSensitive: true, wholeWord: false, useRegex: false })!;
    expect(re.global).toBe(true);
  });
});

describe('buildLineNumberRows', () => {
  test('numbers rows from startLine', () => {
    const rows = buildLineNumberRows('a\nb', 42, true);
    expect(rows).toContain('<td class="line-number">42</td><td class="line-content">a</td>');
    expect(rows).toContain('<td class="line-number">43</td><td class="line-content">b</td>');
  });

  test('multi-line span spanning 3 lines is closed and reopened per row starting at 42', () => {
    const rows = buildLineNumberRows('<span class="hljs-comment">/*\nbody\n*/</span>', 42, true);
    expect(rows).toContain(
      '<tr><td class="line-number">42</td><td class="line-content"><span class="hljs-comment">/*</span></td></tr>',
    );
    expect(rows).toContain(
      '<tr><td class="line-number">43</td><td class="line-content"><span class="hljs-comment">body</span></td></tr>',
    );
    expect(rows).toContain(
      '<tr><td class="line-number">44</td><td class="line-content"><span class="hljs-comment">*/</span></td></tr>',
    );
    // 各行のセルは自己完結: 行ごとに open と close の数が一致する
    const cells = rows.match(/<td class="line-content">.*?<\/td>/gu)!;
    for (const cell of cells) {
      const opens = (cell.match(/<span\b/gu) || []).length;
      const closes = (cell.match(/<\/span>/gu) || []).length;
      expect(opens).toBe(closes);
    }
  });

  test('drops a single trailing empty line (highlight.js trailing newline)', () => {
    const rows = buildLineNumberRows('a\nb\n', 1, false);
    expect((rows.match(/<tr>/gu) || []).length).toBe(2);
  });

  test('omitting showLineNumbers means no line numbers (same rule as renderCodeHtml)', () => {
    // @ts-expect-error -- showLineNumbers の省略が行番号なしになることを確かめる
    expect(buildLineNumberRows('a\nb', 1)).not.toContain('line-number');
    // @ts-expect-error -- showLineNumbers の省略が行番号なしになることを確かめる
    expect(wrapWithLineNumbers('a\nb')).not.toContain('line-number');
    expect(buildLineNumberRows('a\nb', 1, true)).toContain('line-number');
  });

  test('wrapWithLineNumbers equals code-table wrapper around buildLineNumberRows from line 1', () => {
    const input = '<span class="x">a\nb</span>\nplain';
    expect(wrapWithLineNumbers(input, false)).toBe(
      '<table class="code-table">' + buildLineNumberRows(input, 1, false) + '</table>',
    );
  });

  test('showLineNumbers=false は行番号セルを付けず line-content のみ', () => {
    const rows = buildLineNumberRows('a\nb', 1, false);
    expect(rows).toBe(
      '<tr><td class="line-content">a</td></tr><tr><td class="line-content">b</td></tr>',
    );
  });

  // 空行は <td class="line-content"></td> になる。要素が空だと line box が
  // 生成されず <tr> の高さが 0 になり、行番号なし表示で空行が消える
  // (実測: 行番号なしで [15, 0, 15, 0, 0, 15]px、行番号ありで全行 15px)。
  // 生成物側にプレースホルダを入れるとコピー結果に不可視文字が混ざるので、
  // 担保は CSS 側に置く。ここが空行を落とし始めたら気づけるようにしておく。
  test('空行も 1 行として <tr> を作る(高さの担保は style.css 側)', () => {
    const rows = buildLineNumberRows('a\n\nb', 1, false);
    expect(rows).toBe(
      '<tr><td class="line-content">a</td></tr>' +
        '<tr><td class="line-content"></td></tr>' +
        '<tr><td class="line-content">b</td></tr>',
    );
  });

  test('style.css が空の line-content にも line box を作る', () => {
    // クラスを付けるだけでは高さは出ない。見た目側の担保はここでしか測れない。
    // :empty ではなく ::after にするのは、reflowSpanBalancedLines が開き <span> を
    // 前置した空行が :empty に一致しないため。
    const css = fs.readFileSync(
      path.join(__dirname, '..', 'BefoldKit', 'Resources', 'style.css'),
      'utf8',
    );
    const rule = css.slice(css.indexOf('.line-content::after'));
    expect(css).toContain('.line-content::after');
    expect(rule).toContain('display: inline-block;');
    expect(css).not.toContain('.line-content:empty');
  });
});

describe('indentColumns', () => {
  const TAB = CODE_TAB_SIZE;

  test('スペースは 1 桁ずつ数える', () => {
    expect(indentColumns('    code', TAB)).toBe(4);
    expect(indentColumns('  code', TAB)).toBe(2);
  });

  test('タブは次の tab-stop まで進む', () => {
    expect(indentColumns('\tcode', TAB)).toBe(4);
    expect(indentColumns('\t\tcode', TAB)).toBe(8);
  });

  test('タブとスペースの混在を tab-stop 境界で正しく換算する', () => {
    // スペース2 → 桁2、タブ → 次の tab-stop(4)まで = 桁4、合計インデント桁4
    expect(indentColumns('  \tcode', TAB)).toBe(4);
    // タブ(→4) + スペース2 = 桁6
    expect(indentColumns('\t  code', TAB)).toBe(6);
  });

  test('先頭が非空白なら 0', () => {
    expect(indentColumns('code', TAB)).toBe(0);
  });
});

describe('leadingIndentInfo(インデントガイド用)', () => {
  const TAB = CODE_TAB_SIZE;

  test('インデント桁とガイド本数(depth)を返す', () => {
    expect(leadingIndentInfo('        code', TAB)).toEqual({ cols: 8, depth: 2 });
    expect(leadingIndentInfo('    code', TAB)).toEqual({ cols: 4, depth: 1 });
    expect(leadingIndentInfo('code', TAB)).toEqual({ cols: 0, depth: 0 });
  });

  test('先頭の開き span タグを飛ばしてから空白を数える', () => {
    // reflow が前置した開き span の後ろにインデントがある場合
    expect(leadingIndentInfo('<span class="hljs-comment">    body', TAB)).toEqual({
      cols: 4,
      depth: 1,
    });
    // インデントの後にトークン span が来る場合(空白はタグの手前)
    expect(leadingIndentInfo('        <span class="hljs-keyword">let</span>', TAB)).toEqual({
      cols: 8,
      depth: 2,
    });
  });

  test('空行・空白のみの行はガイドを引かない(depth 0)', () => {
    expect(leadingIndentInfo('', TAB)).toEqual({ cols: 0, depth: 0 });
    expect(leadingIndentInfo('    ', TAB)).toEqual({ cols: 0, depth: 0 });
  });

  test('半端なインデント(tab-stop 未満)は端数を切り捨てて depth を決める', () => {
    // 桁6 は depth 1(4桁で1レベル、残り2桁は端数)
    expect(leadingIndentInfo('      code', TAB)).toEqual({ cols: 6, depth: 1 });
  });
});

describe('lineContentCell(ガイド用 CSS 変数の付与)', () => {
  test('インデントのある行に --indent-cols / --indent-depth を付ける', () => {
    expect(lineContentCell('        code')).toBe(
      '<td class="line-content" style="--indent-cols:8;--indent-depth:2">        code</td>',
    );
  });

  test('インデント 0 の行には style を付けない', () => {
    expect(lineContentCell('code')).toBe('<td class="line-content">code</td>');
  });

  test('buildLineNumberRows がインデント行に CSS 変数を乗せる', () => {
    const rows = buildLineNumberRows('    x', 1, false);
    expect(rows).toContain(
      '<td class="line-content" style="--indent-cols:4;--indent-depth:1">    x</td>',
    );
  });
});

describe('csvRowsHtml', () => {
  test('builds tr/td rows and pads short rows up to minCols', () => {
    const html = csvRowsHtml([['a', 'b'], ['c']], 3, []);
    expect(html).toBe(
      '<tr><td>a</td><td>b</td><td></td></tr><tr><td>c</td><td></td><td></td></tr>',
    );
  });

  test('a row longer than minCols keeps all its cells', () => {
    const html = csvRowsHtml([['a', 'b', 'c']], 2, []);
    expect(html).toBe('<tr><td>a</td><td>b</td><td>c</td></tr>');
  });

  test('escapes HTML special characters in cells', () => {
    const html = csvRowsHtml([['<b>', 'a&b', '"q"']], 0, []);
    expect(html).toBe('<tr><td>&lt;b&gt;</td><td>a&amp;b</td><td>&quot;q&quot;</td></tr>');
  });

  test('empty rows array produces empty string', () => {
    expect(csvRowsHtml([], 3, [])).toBe('');
  });
});

describe('codeChunkInnerHtml', () => {
  test('strips the pre/code wrapper from highlighted output', () => {
    const inner = codeChunkInnerHtml(hljs, 'const x = 1;', 'javascript', '');
    expect(inner).not.toMatch(/<pre>|<code|<\/code>|<\/pre>/u);
    expect(inner).toContain('hljs-keyword');
    expect(inner).toBe(
      highlightCode(hljs, 'const x = 1;', 'javascript')
        .replace(/^<pre><code[^>]*>/u, '')
        .replace(/<\/code><\/pre>$/u, ''),
    );
  });

  test('falls back to escapeHtml when hljs is unavailable', () => {
    expect(codeChunkInnerHtml(null, '<b> & "x"', 'javascript', '')).toBe(
      '&lt;b&gt; &amp; &quot;x&quot;',
    );
  });

  test('falls back to escapeHtml when the language is unknown', () => {
    expect(codeChunkInnerHtml(hljs, 'a < b', 'no-such-lang', '')).toBe('a &lt; b');
  });

  test('without context, a block comment continuation is misidentified as code', () => {
    // チャンク境界後の 'still comment' は、文脈なしでは通常コードとして扱われる
    // (これが TASK-14 のバグ本体)。
    const continuation = codeChunkInnerHtml(
      hljs,
      'still comment */\nconst y = 2;',
      'javascript',
      '',
    );
    expect(continuation).not.toContain('hljs-comment');
  });

  test('with context spanning an open block comment, the continuation stays a comment', () => {
    const context = '/* comment start\n';
    const continuation = codeChunkInnerHtml(
      hljs,
      'still comment */\nconst y = 2;',
      'javascript',
      context,
    );
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
      .replace(/^<pre><code[^>]*>/u, '')
      .replace(/<\/code><\/pre>$/u, '');
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

describe('svgDataURI', () => {
  test('base64-encodes ASCII SVG text', () => {
    const uri = svgDataURI('<svg/>');
    expect(uri.startsWith('data:image/svg+xml;base64,')).toBe(true);
    expect(atob(uri.slice('data:image/svg+xml;base64,'.length))).toBe('<svg/>');
  });

  test('round-trips non-Latin-1 characters as UTF-8', () => {
    const svg = '<svg><text>日本語</text></svg>';
    const bytes = atob(svgDataURI(svg).slice('data:image/svg+xml;base64,'.length));
    // atob が返すのはバイト列を 1 文字 1 バイトで表したバイナリ文字列。ここで欲しいのは
    // コードポイントではなくそのバイト値なので charCodeAt のままにする。
    // oxlint-disable-next-line unicorn/prefer-code-point
    const utf8 = Uint8Array.from(bytes, (c) => c.charCodeAt(0));
    expect(new TextDecoder().decode(utf8)).toBe(svg);
  });
});

describe('imageDataURI', () => {
  test('uses the given MIME type', () => {
    expect(imageDataURI('AAAA', 'image/webp')).toBe('data:image/webp;base64,AAAA');
  });

  test('falls back to image/png when the MIME type is missing', () => {
    expect(imageDataURI('AAAA', '')).toBe('data:image/png;base64,AAAA');
    // @ts-expect-error -- 契約外の MIME タイプ省略に対する既定値を確かめる
    expect(imageDataURI('AAAA')).toBe('data:image/png;base64,AAAA');
  });
});

describe('nextMatchIndex', () => {
  test('advances to the next match', () => {
    expect(nextMatchIndex(0, 3)).toBe(1);
    expect(nextMatchIndex(1, 3)).toBe(2);
  });

  test('wraps from the last match to the first', () => {
    expect(nextMatchIndex(2, 3)).toBe(0);
  });

  test('selects the first match from an unselected state', () => {
    expect(nextMatchIndex(-1, 3)).toBe(0);
  });

  test('returns -1 when there are no matches', () => {
    expect(nextMatchIndex(0, 0)).toBe(-1);
    expect(nextMatchIndex(-1, 0)).toBe(-1);
  });
});

describe('prevMatchIndex', () => {
  test('goes back to the previous match', () => {
    expect(prevMatchIndex(2, 3)).toBe(1);
    expect(prevMatchIndex(1, 3)).toBe(0);
  });

  test('wraps from the first match to the last', () => {
    expect(prevMatchIndex(0, 3)).toBe(2);
  });

  test('undoes nextMatchIndex for every position in the cycle', () => {
    for (let i = 0; i < 3; i++) {
      expect(prevMatchIndex(nextMatchIndex(i, 3), 3)).toBe(i);
    }
  });

  test('returns -1 when there are no matches', () => {
    expect(prevMatchIndex(0, 0)).toBe(-1);
  });
});

describe('keptMatchIndex', () => {
  test('keeps an index that is still in range', () => {
    expect(keptMatchIndex(1, 3)).toBe(1);
    expect(keptMatchIndex(2, 3)).toBe(2);
  });

  test('clamps to the last match when the count shrank', () => {
    expect(keptMatchIndex(5, 3)).toBe(2);
  });

  test('clamps an unselected index to the first match', () => {
    expect(keptMatchIndex(-1, 3)).toBe(0);
  });

  test('returns -1 when there are no matches', () => {
    expect(keptMatchIndex(2, 0)).toBe(-1);
  });
});
