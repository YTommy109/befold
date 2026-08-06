const {
  parseUnifiedDiff, renderInlineDiffHtml, pairDiffLines, renderSideBySideDiffHtml, renderDiffHtml,
  highlightedDiffLines,
} = require('../viewer.js');

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

// 連続していない 2 つのハンク。区切り行の有無・位置を見るのに使う。
const TWO_HUNK_DIFF = [
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

// 末尾が空行のファイル（`alpha\nbeta\n\n`）。ハンクの最終行が「テキストが空の
// 文脈行」になり、ハンクをまとめてハイライトすると末尾に空要素が出る。
const TRAILING_BLANK_DIFF = [
  'diff --git a/a.txt b/a.txt',
  '--- a/a.txt',
  '+++ b/a.txt',
  '@@ -1,3 +1,3 @@',
  ' alpha',
  '-beta',
  '+BETA',
  ' ',
  '',
].join('\n');

describe('highlightedDiffLines', () => {
  // 行 HTML は添字で引かれるため、要素数がハンクの行数より少ないと
  // 左右分割の描画が undefined を掴んで落ちる。長さは常に一致させる。
  test('末尾が空行でもハンクの行数と同じ長さの配列を返す', () => {
    const hunk = parseUnifiedDiff(TRAILING_BLANK_DIFF)[0].hunks[0];

    expect(hunk.lines).toHaveLength(4);
    expect(highlightedDiffLines(null, hunk, 'plaintext')).toHaveLength(4);
  });

  // 旧版と新版を 1 ブロックに連結すると、文字列リテラルを書き換えただけの差分でも
  // クォートの数が合わなくなり、変更行より後ろのハイライトが総崩れになる。
  // 複数行文字列の開始行を書き換えると、旧版と新版を連結した並びではクォートの
  // 対応が崩れ（開始行が 2 本並ぶ）、以降の行がすべて文字列として着色される。
  test('複数行文字列の開始行を書き換えても後続行のハイライトが壊れない', () => {
    const hljs = require('highlight.js');
    const diff = [
      'diff --git a/a.py b/a.py',
      '--- a/a.py',
      '+++ b/a.py',
      '@@ -1,3 +1,3 @@',
      '-s = """hello',
      '+s = """hi',
      ' world"""',
      ' import os',
      '',
    ].join('\n');
    const hunk = parseUnifiedDiff(diff)[0].hunks[0];

    const htmls = highlightedDiffLines(hljs, hunk, 'python');

    // 変更行より後ろの文脈行は、旧版だけ／新版だけを描いたときと同じ色付けになる。
    const plain = highlightedDiffLines(hljs, {
      lines: [
        { type: 'context', text: 's = """hi' },
        { type: 'context', text: 'world"""' },
        { type: 'context', text: 'import os' },
      ],
    }, 'python');
    expect(htmls[3]).toBe(plain[2]);
    expect(htmls[3]).toContain('hljs-keyword');
  });
});

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

  // SQL や Lua のコメントはハイフン 2 個で始まるため、削除されると
  // 行頭のマーカーと合わせてファイルヘッダと同じ形になる。文脈（ハンクの
  // 内か外か）を見ずに接頭辞だけで判定すると、その行が消えて以降の
  // 旧側行番号が 1 つずれる。
  test('ハンク内のヘッダと同じ形の行を本文として扱う', () => {
    const diff = [
      'diff --git a/q.sql b/q.sql',
      '--- a/q.sql',
      '+++ b/q.sql',
      '@@ -1,3 +1,3 @@',
      ' SELECT 1;',
      '--- old comment',
      '+++ new comment',
      ' SELECT 2;',
      '',
    ].join('\n');

    const file = parseUnifiedDiff(diff)[0];

    expect(file.oldPath).toBe('q.sql');
    expect(file.newPath).toBe('q.sql');
    expect(file.hunks[0].lines.map((l) => l.type)).toEqual([
      'context', 'del', 'add', 'context',
    ]);
    expect(file.hunks[0].lines.map((l) => l.text)).toEqual([
      'SELECT 1;', '-- old comment', '++ new comment', 'SELECT 2;',
    ]);
    expect(file.hunks[0].lines.map((l) => l.oldNumber)).toEqual([1, 2, null, 3]);
  });

  // パーサの取りこぼしは両レイアウトの描画に伝わるため、両方で本文が出ることを見る。
  test.each([
    ['インライン', renderInlineDiffHtml],
    ['左右分割', renderSideBySideDiffHtml],
  ])('%s でハンク内のヘッダと同じ形の行を描画する', (_name, render) => {
    const diff = [
      'diff --git a/q.sql b/q.sql',
      '--- a/q.sql',
      '+++ b/q.sql',
      '@@ -1,2 +1,2 @@',
      ' SELECT 1;',
      '--- old comment',
      '',
    ].join('\n');

    const html = render(null, diff, 'sql', true);

    expect(html).toContain('old comment');
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

  // 位置情報(`@@ -1,3 +1,4 @@`)は出さない。どこの行かはガターが持っており重複するため。
  test('ハンクの位置情報を描画しない', () => {
    const html = renderInlineDiffHtml(null, TWO_HUNK_DIFF, 'plaintext', true);

    expect(html).not.toContain('@@');
  });

  // 連続していない範囲の境目は残す(消すと離れた行が地続きに見える)。
  test('ハンクの区切り行は 2 つ目以降の前にだけ入り colspan がガター数に合う', () => {
    const withNumbers = renderInlineDiffHtml(null, TWO_HUNK_DIFF, 'plaintext', true);
    const withoutNumbers = renderInlineDiffHtml(null, TWO_HUNK_DIFF, 'plaintext', false);
    const separators = (html) => html.split('diff-hunk-separator').length - 1;

    expect(separators(withNumbers)).toBe(1);
    expect(withNumbers).toContain('colspan="4"');
    expect(withoutNumbers).toContain('colspan="2"');
    // 先頭に区切りを置くと、境目が無いところに帯だけが出る。
    expect(withNumbers.indexOf('diff-hunk-separator')).toBeGreaterThan(withNumbers.indexOf('diff-line'));
  });

  test('ハンクが 1 つだけなら区切り行を出さない', () => {
    expect(renderInlineDiffHtml(null, SIMPLE_DIFF, 'swift', true)).not.toContain('diff-hunk-separator');
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

  // hljs があるときは 1 行ずつではなくまとめてハイライトする。
  // 1 行ずつだとブロックコメントや複数行文字列で字句状態が切れる。
  // ただしハンク全体を 1 ブロックにすると旧版と新版が連結されて字句状態が壊れるため、
  // 旧版(文脈+削除)と新版(文脈+追加)の 2 ブロックに分ける。
  test('hljs へは旧版・新版それぞれをまとめて渡す', () => {
    const calls = [];
    const hljs = {
      getLanguage: () => true,
      highlight: (str) => {
        calls.push(str);
        return { value: str.replace(/</g, '&lt;') };
      },
    };

    renderInlineDiffHtml(hljs, SIMPLE_DIFF, 'swift', false);

    expect(calls).toHaveLength(2);
    expect(calls[0]).toBe('let a = 1\nlet b = 2\nlet c = 4');
    expect(calls[1]).toBe('let a = 1\nlet b = 3\nlet c = 4');
  });
});

describe('pairDiffLines', () => {
  const lines = (types) => types.map((t, i) => ({ type: t, text: String(i) }));

  test('文脈行は左右同じ行に並ぶ', () => {
    expect(pairDiffLines(lines(['context', 'context']))).toEqual([
      { left: 0, right: 0 }, { left: 1, right: 1 },
    ]);
  });

  test('連続する削除と追加を対にする', () => {
    expect(pairDiffLines(lines(['del', 'del', 'add', 'add']))).toEqual([
      { left: 0, right: 2 }, { left: 1, right: 3 },
    ]);
  });

  // 片側が多い場合、余った行は反対側を空にして並べる(行を詰めない)。
  test('数が揃わない場合は空マスで埋める', () => {
    expect(pairDiffLines(lines(['del', 'add', 'add']))).toEqual([
      { left: 0, right: 1 }, { left: null, right: 2 },
    ]);
    expect(pairDiffLines(lines(['del', 'del', 'add']))).toEqual([
      { left: 0, right: 2 }, { left: 1, right: null },
    ]);
  });

  test('追加だけ・削除だけのブロックも扱える', () => {
    expect(pairDiffLines(lines(['add']))).toEqual([{ left: null, right: 0 }]);
    expect(pairDiffLines(lines(['del']))).toEqual([{ left: 0, right: null }]);
  });
});

describe('renderSideBySideDiffHtml', () => {
  test('左右 2 列の構造になる', () => {
    const html = renderSideBySideDiffHtml(null, SIMPLE_DIFF, 'swift', false);

    expect(html).toContain('diff-split');
    expect(html).toContain('diff-side-left');
    expect(html).toContain('diff-side-right');
  });

  // 変更行は同じ <tr> に左右で並ぶ(対応が目で追える)。
  test('削除と追加が同じ行に並ぶ', () => {
    const html = renderSideBySideDiffHtml(null, SIMPLE_DIFF, 'swift', false);
    const rows = html.split('<tr class="diff-line">').slice(1);

    const changed = rows.find((r) => r.includes('let b = 2'));
    expect(changed).toContain('let b = 3');
  });

  test('対応する行が無い側は空マスになる', () => {
    const diff = [
      'diff --git a/a.txt b/a.txt',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -1,1 +1,2 @@',
      ' one',
      '+two',
      '',
    ].join('\n');

    const html = renderSideBySideDiffHtml(null, diff, 'plaintext', false);

    expect(html).toContain('diff-marker diff-empty');
    expect(html).toContain('line-content diff-empty');
  });

  test('ハンクの区切り行の colspan が左右 2 列分になり、位置情報は出ない', () => {
    const withNumbers = renderSideBySideDiffHtml(null, TWO_HUNK_DIFF, 'plaintext', true);

    expect(withNumbers).toContain('colspan="6"');
    expect(renderSideBySideDiffHtml(null, TWO_HUNK_DIFF, 'plaintext', false)).toContain('colspan="4"');
    expect(withNumbers).not.toContain('@@');
  });

  test('ハンクが無ければ空文字列を返す', () => {
    expect(renderSideBySideDiffHtml(null, '', 'swift', false)).toBe('');
  });

  // 例外は呼び出し側の catch に飲まれて空文字になるため、落ちると
  // 「⇧⌘D だけ何も起きない」という形でしか現れない。
  test('末尾が空行のファイルでも描画できる', () => {
    const html = renderSideBySideDiffHtml(null, TRAILING_BLANK_DIFF, 'plaintext', true);

    expect(html).toContain('diff-split');
    expect(html.split('diff-side-left').length - 1).toBe(3);
  });
});

describe('renderDiffHtml', () => {
  test('レイアウト名で 2 つの描画を選ぶ', () => {
    expect(renderDiffHtml(null, SIMPLE_DIFF, 'swift', false, 'side-by-side')).toContain('diff-split');
    expect(renderDiffHtml(null, SIMPLE_DIFF, 'swift', false, 'inline')).not.toContain('diff-split');
  });

  test('未知のレイアウトはインラインとして扱う', () => {
    expect(renderDiffHtml(null, SIMPLE_DIFF, 'swift', false, 'bogus')).not.toContain('diff-split');
  });
});
