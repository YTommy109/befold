// ソースコード表示の関数・型定義ジャンプ（TASK-485.4）。
//
// **実 highlight.js の出力に対して検証する。** 手書きのダミー HTML に
// `<span class="hljs-comment">` を並べて測ると、「hljs が本当にそう出力するか」を
// 一切測らないテストになる（同じファイルの中に、path-ref 用に手書きした裸の
// hljs-title が既にある）。ここは main.render() を通し、code-html.ts の
// reflowSpanBalancedLines が行ごとに span を開き直した結果を読む。
const { loadViewerMain } = require('./support/viewerMainHarness');

const count = (document) => document.getElementById('mmd-jump-count').textContent;

// ソース表示でコードを描画し、定義ジャンプを開く。
async function openDefinitionJump(lang, lines) {
  const loaded = loadViewerMain({});
  loaded.main.setViewMode('source');
  await loaded.main.render(lines.join('\n'), 'code', lang);
  loaded.main._mmdOpenJump('functionDefinition');
  return loaded;
}

// 目印が付いた行のテキスト（行番号セルを含まない本文だけ）。
function markedLines(document) {
  return Array.from(
    document.querySelectorAll('#diagram-wrap .mmd-jump-target, #diagram-wrap .mmd-jump-current'),
  ).map((cell) => cell.textContent.trim());
}

describe('定義ジャンプ: 対応言語で定義を拾う', () => {
  test('Swift の func / class / struct / enum / extension を拾う', async () => {
    const { document } = await openDefinitionJump('swift', [
      'import Foundation',
      'struct Point {',
      '    let x: Int',
      '    func moved() -> Point { self }',
      '    public static func origin() -> Point { Point(x: 0) }',
      '}',
      'extension Point: Equatable {}',
      'enum Kind { case a }',
    ]);

    expect(markedLines(document)).toEqual([
      'struct Point {',
      'func moved() -> Point { self }',
      'public static func origin() -> Point { Point(x: 0) }',
      'extension Point: Equatable {}',
      'enum Kind { case a }',
    ]);
    expect(count(document)).toBe('1/5');
  });

  test('定義行を前後に移動でき、現在位置が巡回する', async () => {
    const { document, main } = await openDefinitionJump('swift', [
      'func first() {}',
      'let x = 1',
      'func second() {}',
      'func third() {}',
    ]);

    const currentText = () => document.querySelector('.mmd-jump-current').textContent.trim();

    expect(count(document)).toBe('1/3');
    expect(currentText()).toBe('func first() {}');

    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/3');
    expect(currentText()).toBe('func second() {}');

    main._mmdJumpPrevIfOpen();
    expect(count(document)).toBe('1/3');
    expect(currentText()).toBe('func first() {}');

    // 先頭で前へ戻ると末尾へ回る（検索・見出しと同じ振る舞い）。
    main._mmdJumpPrevIfOpen();
    expect(count(document)).toBe('3/3');
    expect(currentText()).toBe('func third() {}');
  });

  test('Python の def / class / async def を拾う', async () => {
    const { document } = await openDefinitionJump('python', [
      'import os',
      'class Store:',
      '    def get(self, key):',
      '        return key',
      '    async def fetch(self):',
      '        return 1',
    ]);

    expect(markedLines(document)).toEqual([
      'class Store:',
      'def get(self, key):',
      'async def fetch(self):',
    ]);
  });

  test('TypeScript の function / アロー関数代入 / interface / type を拾う', async () => {
    const { document } = await openDefinitionJump('typescript', [
      'import { a } from "./a";',
      'export function build(x: number): string {',
      '  return String(x);',
      '}',
      'const toName = (x: number): string => String(x);',
      'export interface Shape {',
      '  size: number;',
      '}',
      'type Id = string;',
    ]);

    expect(markedLines(document)).toEqual([
      'export function build(x: number): string {',
      'const toName = (x: number): string => String(x);',
      'export interface Shape {',
      'type Id = string;',
    ]);
  });
});

describe('定義ジャンプ: コメント・文字列を定義と誤検出しない', () => {
  // 複数行コメントの途中の行は、生の hljs 出力では素のテキストだが、
  // reflowSpanBalancedLines が行頭で hljs-comment を開き直すため、
  // 行の td だけを見ても「コメントの中」と分かる。ここが方式の要。
  test('Swift のブロックコメント内の func を拾わない', async () => {
    const { document } = await openDefinitionJump('swift', [
      '/*',
      ' * func documented(a: Int) {}',
      ' * class AlsoInComment {}',
      ' */',
      'func real() {}',
    ]);

    expect(markedLines(document)).toEqual(['func real() {}']);
  });

  test('Swift の複数行文字列内の func を拾わない', async () => {
    const { document } = await openDefinitionJump('swift', [
      'let sample = """',
      'func insideString() {}',
      '"""',
      'func real() {}',
    ]);

    expect(markedLines(document)).toEqual(['func real() {}']);
  });

  test('行コメントで始まる行を拾わない', async () => {
    const { document } = await openDefinitionJump('swift', [
      '// func commented() {}',
      'func real() {}',
    ]);

    expect(markedLines(document)).toEqual(['func real() {}']);
  });

  test('Python の docstring 内の def を拾わない', async () => {
    const { document } = await openDefinitionJump('python', [
      'def real(self):',
      '    """',
      '    def notADefinition(self):',
      '    """',
      '    return 1',
    ]);

    expect(markedLines(document)).toEqual(['def real(self):']);
  });

  test('TypeScript のテンプレートリテラル内の function を拾わない', async () => {
    const { document } = await openDefinitionJump('typescript', [
      'const code = `',
      'function insideTemplate() {}',
      '`;',
      'function real() {}',
    ]);

    expect(markedLines(document)).toEqual(['function real() {}']);
  });

  test('JS の呼び出し行を定義と間違えない（hljs は呼び出しにも title を付ける）', async () => {
    const { document } = await openDefinitionJump('javascript', [
      'function real(a) {',
      '  return a;',
      '}',
      'real(1);',
      'obj.method(2);',
      'compute();',
    ]);

    expect(markedLines(document)).toEqual(['function real(a) {']);
  });
});

describe('定義ジャンプ: 非対応言語と段階読み込み', () => {
  test('非対応言語では目印を 1 つも拾わない', async () => {
    const { document } = await openDefinitionJump('ruby', ['def greet', '  puts "hi"', 'end']);

    expect(markedLines(document)).toEqual([]);
    expect(count(document)).toBe('0/0');
  });

  test('段階読み込み中は「表示範囲内」ラベルを出す（未読み込み範囲の定義は DOM に無い）', async () => {
    const { document, main } = await openDefinitionJump('swift', ['func real() {}']);

    main._mmdSetTruncated(true, 100, false);

    expect(count(document)).toBe('1/1 (Displayed range)');
  });

  test('追記された行の定義も数に入る', async () => {
    // 末尾に空要素を置いて改行で終わらせる。改行で終わっていないと追記分が
    // 既存の最終行へ連結され、行が増えない（render.ts の endedWithNewline 判定）。
    const { document, main } = await openDefinitionJump('swift', ['func first() {}', '']);
    expect(count(document)).toBe('1/1');

    main.appendChunk('func second() {}\n', 'code', 'swift');

    expect(count(document)).toBe('1/2');
  });
});
