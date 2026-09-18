import * as fs from 'node:fs';
import * as path from 'node:path';

import { describe, expect, test } from '@jest/globals';
import hljs from 'highlight.js';

import { renderInlineDiffHtml, renderSideBySideDiffHtml } from '../viewer-src/main.js';

// 1 行だけを書き換えた差分。語単位の強調は「どの削除行とどの追加行が対か」が
// 決まって初めて計算できるので、対になる形を最小で作る。
const singleChangeDiff = (oldLine: string, newLine: string): string =>
  [
    'diff --git a/a.txt b/a.txt',
    '--- a/a.txt',
    '+++ b/a.txt',
    '@@ -1 +1 @@',
    '-' + oldLine,
    '+' + newLine,
    '',
  ].join('\n');

// 行ごとの「強調された文字列」。1 行の中で強調が hljs の span をまたぐと
// <span class="diff-word"> は複数に分かれるため、行ごとに連結して 1 つの文字列で見る
// (画面上は連続した 1 本の帯になる)。強調の無い行は結果に入れない。
//
// 測るのはクラス名の個数や範囲の数え方ではなく**どの文字列が強調されたか**にする。
// 実装の決め打ちを写したテストは、実装を変えたときに緑のまま意味を失う。
const markedPerLine = (html: string): string[] => {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  const marked: string[] = [];
  for (const cell of Array.from(doc.querySelectorAll('.line-content'))) {
    const words = Array.from(cell.querySelectorAll('.diff-word'))
      .map((word) => word.textContent ?? '')
      .join('');
    if (words !== '') {
      marked.push(words);
    }
  }
  return marked;
};

// 行の内容セルの textContent を順に並べる。語強調を重ねても元の行文字列から
// 1 文字も増減しないことを見るのに使う。
const lineTexts = (html: string): string[] => {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  return Array.from(doc.querySelectorAll('.line-content')).map((cell) => cell.textContent ?? '');
};

describe('変更行の語単位の差分（.diff-word）', () => {
  // AC#1。1 文字だけ直した行と行ごと書き換えた行が同じ見た目にならないこと。
  test('変わった語だけが強調される', () => {
    const html = renderInlineDiffHtml(
      null,
      singleChangeDiff('let b = 2', 'let b = 3'),
      'swift',
      false,
    );

    expect(markedPerLine(html)).toEqual(['2', '3']);
  });

  // AC#3。空白で区切られない日本語でも語に割れること（Intl.Segmenter の辞書分割）。
  test('日本語の行でも語単位で強調される', () => {
    const html = renderInlineDiffHtml(
      null,
      singleChangeDiff('これは日本語の文です。', 'これは中国語の文です。'),
      'plaintext',
      false,
    );

    expect(markedPerLine(html)).toEqual(['日本語', '中国語']);
  });

  // AC#2 と、設計で決めた「対応付けの経路は pairDiffLines 1 本」の担保。
  // レイアウトごとに別々の対応付けが育つと、この期待が破れる。
  test('インラインと左右分割で同じ強調になる', () => {
    const diff = singleChangeDiff('foo(alpha, beta)', 'foo(alpha, gamma)');
    const inline = renderInlineDiffHtml(null, diff, 'swift', true);
    const split = renderSideBySideDiffHtml(null, diff, 'swift', true);

    expect(markedPerLine(inline)).toEqual(['beta', 'gamma']);
    expect(markedPerLine(split)).toEqual(markedPerLine(inline));
  });

  // AC#5。行全体が強調になるなら情報が増えないので出さない（従来の行単位色分けのまま）。
  test('行が丸ごと書き換わった行は強調しない', () => {
    const html = renderInlineDiffHtml(null, singleChangeDiff('alpha', 'beta'), 'plaintext', false);

    expect(markedPerLine(html)).toEqual([]);
  });

  // 対にならない行（片側だけの追加・削除）は比較相手が居ない。
  test('追加だけ・削除だけの行は強調しない', () => {
    const addOnly = [
      'diff --git a/a.txt b/a.txt',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -1 +1,2 @@',
      ' one',
      '+two',
      '',
    ].join('\n');

    expect(markedPerLine(renderInlineDiffHtml(null, addOnly, 'plaintext', false))).toEqual([]);
  });

  // AC#4。強調はテキストの実行部だけを包み、hljs の span は 1 つも分割しない。
  // jump-providers が「その行はコメント・文字列の中か」を hljs-string / hljs-comment の
  // **存在**で決めている（jump-providers.ts）ので、分割して消えると誤判定になる。
  test('文字列リテラルの中を強調しても hljs の span を分割しない', () => {
    const html = renderInlineDiffHtml(
      hljs,
      singleChangeDiff('let s = "alpha beta"', 'let s = "alpha gamma"'),
      'swift',
      false,
    );
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const strings = Array.from(doc.querySelectorAll('.hljs-string'));

    expect(strings.map((el) => el.textContent)).toEqual(['"alpha beta"', '"alpha gamma"']);
    // 強調は文字列 span の内側に入る（外側へ出ると span が割れる）。
    expect(strings.map((el) => el.querySelector('.diff-word')?.textContent)).toEqual([
      'beta',
      'gamma',
    ]);
  });

  // HTML 実体参照（&lt; / &amp;）は復号すると 1 文字。位置の数え方を誤ると
  // 無関係な場所が強調される形で静かに間違うので、内容が変わらないことまで見る。
  test('HTML 特殊文字を含む行でも位置がずれない', () => {
    const html = renderInlineDiffHtml(
      hljs,
      singleChangeDiff('if a && b < c {', 'if a && b > c {'),
      'swift',
      false,
    );

    expect(markedPerLine(html)).toEqual(['<', '>']);
    expect(lineTexts(html)).toEqual(['if a && b < c {', 'if a && b > c {']);
  });

  // 塗り分けのセレクタが両レイアウトの DOM に届いているか。クラスの付き先は
  // インラインが <tr>、左右分割が側の <td> と違うので、子孫セレクタが片方だけ
  // 空振りしても markedPerLine の期待は通ってしまう（span は在るが色が付かない）。
  // WebView の見た目そのものは自動テストの対象外なので、ここでは「セレクタが
  // 要素に一致すること」と「地色がライト・ダークの両方で定義されていること」を測る。
  test('語強調の塗り分けが両レイアウトの DOM に届く', () => {
    const css = fs.readFileSync(
      path.join(__dirname, '..', 'BefoldKit', 'Resources', 'style.css'),
      'utf8',
    );
    const diff = singleChangeDiff('foo(alpha, beta)', 'foo(alpha, gamma)');

    for (const selector of ['.diff-del .diff-word', '.diff-add .diff-word']) {
      expect(css).toContain(selector);
      for (const html of [
        renderInlineDiffHtml(null, diff, 'swift', false),
        renderSideBySideDiffHtml(null, diff, 'swift', false),
      ]) {
        const doc = new DOMParser().parseFromString(html, 'text/html');
        expect(doc.querySelectorAll(selector).length).toBeGreaterThan(0);
      }
    }

    for (const variable of ['--diff-add-word-bg', '--diff-del-word-bg']) {
      // :root のライト値と、@media (prefers-color-scheme: dark) のダーク値。
      expect(css.split(variable + ':').length - 1).toBe(2);
    }
  });
});
