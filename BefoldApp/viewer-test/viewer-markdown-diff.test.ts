// Markdown のレンダリング表示へ差分を重ねる経路(TASK-483.4)のテスト。
// 設計: docs/superpowers/specs/2026-11-21-rendered-markdown-diff-design.md

import { describe, expect, test } from '@jest/globals';

import { buildMarkdownDiffHtml } from '../viewer-src/main.js';
import { loadViewerMain } from './support/viewerMainHarness.js';

// 全文差分(-U1000000 相当)を組む。lines は ' ' / '+' / '-' 接頭辞付きの行。
function wholeFileDiff(lines: string[]): string {
  const oldCount = lines.filter((l) => !l.startsWith('+')).length;
  const newCount = lines.filter((l) => !l.startsWith('-')).length;
  return [
    'diff --git a/n.md b/n.md',
    '--- a/n.md',
    '+++ b/n.md',
    `@@ -1,${oldCount} +1,${newCount} @@`,
    ...lines,
    '',
  ].join('\n');
}

function parse(html: string): Document {
  return new DOMParser().parseFromString(html, 'text/html');
}

describe('buildMarkdownDiffHtml', () => {
  test('変更のあったブロックだけが包まれ、削除 → 追加の順に並ぶ', () => {
    const diff = wholeFileDiff([' # Title', ' ', '-old para', '+new para', ' ', ' tail']);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    const blocks = Array.from(doc.querySelectorAll('.md-diff-block'), (el) => [
      el.className,
      (el as HTMLElement).dataset['diffBlock'],
      el.textContent!.trim(),
    ]);
    expect(blocks).toEqual([
      ['md-diff-block diff-del', '0', 'old para'],
      ['md-diff-block diff-add', '0', 'new para'],
    ]);
    // 文脈ブロックは包まずにそのまま描く。
    expect(doc.querySelector('h1')!.textContent).toBe('Title');
    expect(doc.body.lastElementChild!.textContent).toBe('tail');
  });

  test('空行だけの変更は描画に現れないので色を付けない', () => {
    const diff = wholeFileDiff([' a', '+', ' ', ' b']);
    expect(parse(buildMarkdownDiffHtml(diff)!).querySelector('.md-diff-block')).toBeNull();
  });

  const kinds = (html: string) =>
    Array.from(parse(html).querySelectorAll('.md-diff-block'), (el) => el.className.split(' ')[1]);

  // 削除だけ・追加だけの変更でも、ブロックの形が変わるなら両側に色が付く
  // (旧ブロックが赤で新ブロックが無色、のような片側だけの表示にしない)。
  test('リストの項目を消しただけでも、旧リストは削除・新リストは追加になる', () => {
    expect(kinds(buildMarkdownDiffHtml(wholeFileDiff([' - a', '-- b', ' - c']))!)).toEqual([
      'diff-del',
      'diff-add',
    ]);
  });

  test('リストへ項目を足しただけでも、旧リストは削除・新リストは追加になる', () => {
    expect(kinds(buildMarkdownDiffHtml(wholeFileDiff([' - a', '+- x', ' - b']))!)).toEqual([
      'diff-del',
      'diff-add',
    ]);
  });

  test('空行を足して段落が割れたら、元の段落は削除・割れた 2 段落は追加になる', () => {
    expect(kinds(buildMarkdownDiffHtml(wholeFileDiff([' a', '+', ' b']))!)).toEqual([
      'diff-del',
      'diff-add',
      'diff-add',
    ]);
  });

  // 開きタグと閉じタグが別ブロックにある生 HTML は、閉じるまでを 1 単位にまとめる。
  // 開きタグだけを差分の <div> で包むと、包みの </div> で中の要素まで閉じられる。
  test('details の summary だけを変えても、本文は details の中に残る', () => {
    const diff = wholeFileDiff([
      ' <details>',
      '-<summary>Old</summary>',
      '+<summary>New</summary>',
      ' ',
      ' body',
      ' ',
      ' </details>',
      ' ',
      ' after',
    ]);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelectorAll('.diff-del > details')).toHaveLength(1);
    expect(doc.querySelectorAll('.diff-add > details')).toHaveLength(1);
    expect(doc.querySelector('.diff-add > details summary')!.textContent).toBe('New');
    expect(doc.querySelector('.diff-add > details p')!.textContent).toBe('body');
    // 閉じた後のブロックは単位の外(文脈)に戻る。
    expect(doc.body.lastElementChild!.textContent).toBe('after');
  });

  test('ブロックをまたぐ details の中身を変えても、details ごと差し替わる', () => {
    const diff = wholeFileDiff([' <details>', ' ', '-old', '+new', ' ', ' </details>']);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelector('.diff-del > details')!.textContent).toContain('old');
    expect(doc.querySelector('.diff-add > details')!.textContent).toContain('new');
  });

  test('div align="center" のような開きタグだけのブロックでも入れ子が崩れない', () => {
    const diff = wholeFileDiff([' <div align="center">', ' ', '-# Old', '+# New', ' ', ' </div>']);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelector('.diff-add > div h1')!.textContent).toBe('New');
    expect(doc.querySelectorAll('.md-diff-block')).toHaveLength(2);
  });

  // ページ内リンクは文書で最初に一致した要素へ飛ぶ。削除側の写しが先に並ぶので外す。
  test('削除ブロック内の生 HTML の id / name も外れる', () => {
    const diff = wholeFileDiff(['-<a name="setup"></a>old', '+<a name="setup"></a>new']);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelector('.diff-del a')!.hasAttribute('name')).toBe(false);
    expect(doc.querySelector('.diff-add a')!.getAttribute('name')).toBe('setup');
  });

  // 見出しのアンカーと見出しジャンプが新版の見出しを指すようにする。
  test('削除ブロック内の見出し id は外れ、新版の見出しと二重にならない', () => {
    const diff = wholeFileDiff(['-# Same', '+# Same!', ' ', ' x']);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelector('.diff-del h1')!.hasAttribute('id')).toBe(false);
    expect(doc.querySelector('.diff-add h1')!.id).toBe('same');
  });

  test('mermaid・コードブロック・表を含んでも壊れない', () => {
    const diff = wholeFileDiff([
      ' ```mermaid',
      '-graph TD;A-->B',
      '+graph TD;A-->C',
      ' ```',
      ' ',
      ' ```js',
      ' let x = 1;',
      ' ```',
      ' ',
      ' |a|b|',
      ' |-|-|',
      '-|1|2|',
      '+|1|3|',
    ]);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelectorAll('.diff-del pre.mermaid')).toHaveLength(1);
    expect(doc.querySelectorAll('.diff-add pre.mermaid')).toHaveLength(1);
    expect(doc.querySelector('.diff-add pre.mermaid')!.textContent!.trim()).toBe('graph TD;A-->C');
    expect(doc.querySelectorAll('.diff-del table')).toHaveLength(1);
    expect(doc.querySelectorAll('.diff-add table')).toHaveLength(1);
    // 変わっていないコードブロックは文脈として 1 回だけ描かれる。
    expect(doc.querySelectorAll('pre code')).toHaveLength(1);
    expect(
      new Set(
        Array.from(
          doc.querySelectorAll('[data-diff-block]'),
          (e) => (e as HTMLElement).dataset['diffBlock'],
        ),
      ),
    ).toEqual(new Set(['0', '1']));
  });

  test('参照リンクの定義は同じ版の中で解決される', () => {
    const diff = wholeFileDiff(['-see [x]', '+see [x] now', ' ', ' [x]: https://example.com/']);
    const doc = parse(buildMarkdownDiffHtml(diff)!);
    expect(doc.querySelector('.diff-add a')!.getAttribute('href')).toBe('https://example.com/');
    expect(doc.querySelector('.diff-del a')!.getAttribute('href')).toBe('https://example.com/');
  });

  test('全文差分でない・壊れた差分では null', () => {
    expect(buildMarkdownDiffHtml('unified diff ではない')).toBeNull();
  });
});

describe('レンダリング表示の Markdown へ差分を重ねる', () => {
  const DIFF = wholeFileDiff([' # T', ' ', '-a', '+b']);

  test('差分が届いていればレンダリング表示のまま色分けされ、差分ジャンプの対象になる', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff(DIFF);
    main.setViewMode('rendered');
    await main.render('# T\n\nb\n', 'md');

    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
    expect(document.querySelector('#diagram-wrap h1')!.textContent).toBe('T');
    expect(document.querySelectorAll('#diagram-wrap [data-diff-block="0"]')).toHaveLength(2);
  });

  // 表示は差分の全文から組んであるため、追記すると本文が二重になる。
  test('差分表示中はチャンクを DOM へ追記しない', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff(DIFF);
    main.setViewMode('rendered');
    await main.render('# T\n\n', 'md');

    main.appendChunk('b\n', 'md');

    expect(document.querySelector('#diagram-wrap')!.textContent).not.toContain('bb');
    expect(document.querySelectorAll('#diagram-wrap p')).toHaveLength(2);
  });

  test('描けない差分では通常のレンダリング表示へ落ち、追記も続く', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff('これは unified diff ではない\n');
    main.setViewMode('rendered');
    await main.render('# T\n\n', 'md');
    main.appendChunk('追記された段落\n', 'md');

    expect(document.querySelector('#diagram-wrap .md-diff-block')).toBeNull();
    expect(document.querySelector('#diagram-wrap')!.textContent).toContain('追記された段落');
  });

  test('差分ジャンプで変更ブロックを順に辿れる', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff(wholeFileDiff([' # T', ' ', '-a', '+b', ' ', ' c', ' ', '+d']));
    main.setViewMode('rendered');
    await main.render('# T', 'md');
    main._mmdOpenJump('changeBlock');
    main._mmdJumpNextIfOpen();

    expect(document.getElementById('mmd-jump-count')!.textContent).toBe('2/2');
  });

  // ソース差分(⌘3)はレンダリング差分と別のモードとして残る(TASK-483 AC #4)。
  test('ソース表示では従来どおりソース差分の表になる', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff(DIFF);
    main.setViewMode('source');
    await main.render('# T\n\nb\n', 'md');

    expect(document.querySelector('#diagram-wrap table.diff-table')).not.toBeNull();
    expect(document.querySelector('#diagram-wrap .md-diff-block')).toBeNull();
  });
});
