const { parseUnifiedDiff, renderInlineDiffHtml } = require('../viewer.js');

const SIMPLE_DIFF = [
  'diff --git a/a.swift b/a.swift',
  'index de98044..7be73ce 100644',
  '--- a/a.swift',
  '+++ b/a.swift',
  '@@ -1,3 +1,3 @@',
  ' let a = 1',
  '-let b = 2',
  '+let b = 3',
  ' let c = 4',
  '',
].join('\n');

describe('parseUnifiedDiff', () => {
  test('ファイル・ハンク・行種別へ分解する', () => {
    const files = parseUnifiedDiff(SIMPLE_DIFF);

    expect(files).toHaveLength(1);
    expect(files[0].oldPath).toBe('a.swift');
    expect(files[0].newPath).toBe('a.swift');
    expect(files[0].hunks).toHaveLength(1);
    expect(files[0].hunks[0].lines.map((l) => l.type)).toEqual([
      'context', 'del', 'add', 'context',
    ]);
    expect(files[0].hunks[0].lines.map((l) => l.text)).toEqual([
      'let a = 1', 'let b = 2', 'let b = 3', 'let c = 4',
    ]);
  });

  // 旧側・新側で番号の進み方が違う。片側にしか無い行はもう一方が null になる。
  test('旧側と新側の行番号をそれぞれ振る', () => {
    const lines = parseUnifiedDiff(SIMPLE_DIFF)[0].hunks[0].lines;

    expect(lines.map((l) => l.oldNumber)).toEqual([1, 2, null, 3]);
    expect(lines.map((l) => l.newNumber)).toEqual([1, null, 2, 3]);
  });

  test('複数ハンクの開始行を保持する', () => {
    const diff = [
      'diff --git a/a.txt b/a.txt',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -1,2 +1,2 @@',
      '-one',
      '+ONE',
      ' two',
      '@@ -10,2 +10,3 @@',
      ' ten',
      '+eleven',
      '',
    ].join('\n');

    const hunks = parseUnifiedDiff(diff)[0].hunks;

    expect(hunks).toHaveLength(2);
    expect(hunks[1].oldStart).toBe(10);
    expect(hunks[1].newStart).toBe(10);
    expect(hunks[1].lines.map((l) => l.newNumber)).toEqual([10, 11]);
  });

  // `\ No newline at end of file` は直前の行への注記で、行として数えると
  // 以降の行番号が 1 つずつずれる。
  test('改行なし注記を行として数えない', () => {
    const diff = [
      'diff --git a/a.txt b/a.txt',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -1,2 +1,2 @@',
      '-one',
      '\\ No newline at end of file',
      '+one!',
      ' two',
      '',
    ].join('\n');

    const lines = parseUnifiedDiff(diff)[0].hunks[0].lines;

    expect(lines.map((l) => l.type)).toEqual(['del', 'add', 'context']);
    expect(lines[2].oldNumber).toBe(2);
  });

  test('バイナリ差分を isBinary で示し、ハンクを持たない', () => {
    const diff = [
      'diff --git a/b.dat b/b.dat',
      'index c94be36..04d3356 100644',
      'Binary files a/b.dat and b/b.dat differ',
      '',
    ].join('\n');

    const files = parseUnifiedDiff(diff);

    expect(files[0].isBinary).toBe(true);
    expect(files[0].hunks).toHaveLength(0);
  });

  test('空文字列・null では空配列を返す', () => {
    expect(parseUnifiedDiff('')).toEqual([]);
    expect(parseUnifiedDiff(null)).toEqual([]);
  });
});

describe('renderInlineDiffHtml', () => {
  test('既存のソース表示と同じ code-table 構造に載せる', () => {
    const html = renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', false);

    expect(html).toContain('<table class="code-table diff-table">');
    expect(html).toContain('class="line-content"');
  });

  // インデントガイドは line-content の CSS 変数で描く。差分の行でも
  // 通常のソース表示と同じ lineContentCell を通ること。
  test('インデントのある行にガイド用の CSS 変数が付く', () => {
    const diff = [
      'diff --git a/a.swift b/a.swift',
      '--- a/a.swift',
      '+++ b/a.swift',
      '@@ -1,1 +1,1 @@',
      '-    let indented = 1',
      '+        let indented = 2',
      '',
    ].join('\n');

    const html = renderInlineDiffHtml(null, diff, 'swift', false);

    expect(html).toContain('--indent-cols:4');
    expect(html).toContain('--indent-cols:8');
  });

  test('行種別ごとのクラスを付ける', () => {
    const html = renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', false);

    expect(html).toContain('class="diff-line diff-add"');
    expect(html).toContain('class="diff-line diff-del"');
    expect(html).toContain('class="diff-line diff-context"');
  });

  // 背景色だけだと色覚特性やハイコントラスト設定で区別できないため、
  // 記号セルは行番号の有無に関わらず必ず出す。
  test('色に依存しない +/- の記号セルを常に持つ', () => {
    const withNumbers = renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', true);
    const withoutNumbers = renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', false);

    expect(withNumbers).toContain('<td class="diff-marker" aria-hidden="true">+</td>');
    expect(withoutNumbers).toContain('<td class="diff-marker" aria-hidden="true">-</td>');
  });

  test('行番号 ON のときだけ旧側・新側の 2 本のガターを出す', () => {
    const withNumbers = renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', true);
    const withoutNumbers = renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', false);

    expect(withNumbers).toContain('<td class="line-number diff-old">2</td>');
    expect(withNumbers).toContain('<td class="line-number diff-new"></td>');
    expect(withoutNumbers).not.toContain('line-number');
  });

  test('ハンクヘッダーの colspan がガター数に合う', () => {
    expect(renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', true)).toContain('colspan="4"');
    expect(renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', false)).toContain('colspan="2"');
  });

  test('差分本文の HTML をエスケープする', () => {
    const diff = [
      'diff --git a/a.html b/a.html',
      '--- a/a.html',
      '+++ b/a.html',
      '@@ -1 +1 @@',
      '-<b>old</b>',
      '+<script>alert(1)</script>',
      '',
    ].join('\n');

    const html = renderInlineDiffHtml(null, diff, 'xml', false);

    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });

  test('ハンクが無ければ空文字列を返す（呼び出し側が通常表示へ戻せる）', () => {
    expect(renderInlineDiffHtml(null, '', 'swift', false)).toBe('');
  });

  // hljs があるときは 1 行ずつではなくハンク単位でハイライトする。
  // 1 行ずつだとブロックコメントや複数行文字列で字句状態が切れる。
  test('hljs へはハンク単位でまとめて渡す', () => {
    const calls = [];
    const hljs = {
      getLanguage: () => true,
      highlight: (str) => {
        calls.push(str);
        return { value: str.replace(/</g, '&lt;') };
      },
    };

    renderInlineDiffHtml(hljs, SIMPLE_DIFF, 'swift', false);

    expect(calls).toHaveLength(1);
    expect(calls[0]).toBe('let a = 1\nlet b = 2\nlet b = 3\nlet c = 4');
  });
});
