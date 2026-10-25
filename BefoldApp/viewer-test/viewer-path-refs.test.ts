// 裸のパス文字列の自動リンク化（path-refs.ts）。GitHub Issue #653。
//
// _PATH_RE が \w（ASCII のみ）で構成要素を拾うため、日本語を含むパスが
// 検出段階で候補にすらならなかった不具合を固定する。
import { beforeEach, describe, expect, test } from '@jest/globals';
import { JSDOM } from 'jsdom';

import { _annotatePathRefs } from '../viewer-src/path-refs.js';

const dom = new JSDOM('<div id="diagram-wrap"></div>');

beforeEach(() => {
  global.document = dom.window.document;
  global.Text = dom.window.Text;
  global.Element = dom.window.Element;
  dom.window.document.getElementById('diagram-wrap')!.innerHTML = '';
});

function pathRefTexts() {
  return Array.from(
    dom.window.document.querySelectorAll<HTMLElement>('#diagram-wrap .befold-path-ref'),
  ).map((el) => el.dataset.path);
}

describe('_annotatePathRefs', () => {
  test('ノード境界・空ノード・同じノード内の複数のパスを保つ', () => {
    const wrap = dom.window.document.getElementById('diagram-wrap')!;
    wrap.innerHTML =
      '<code><span>./a.md ./b</span><span>.ts ./c.py </span><span>./d.rs</span> tail</code>';
    const spans = wrap.querySelectorAll('span');
    spans[0]!.after(dom.window.document.createTextNode(''));
    spans[1]!.after(dom.window.document.createTextNode(''));
    const before = wrap.textContent;

    _annotatePathRefs();

    expect(wrap.textContent).toBe(before);
    expect(pathRefTexts()).toEqual(['./a.md', './b.ts', './b.ts', './b.ts', './c.py', './d.rs']);
    expect(Array.from(wrap.querySelectorAll('.befold-path-ref'), (el) => el.textContent)).toEqual([
      './a.md',
      './b',
      '',
      '.ts',
      './c.py',
      './d.rs',
    ]);
  });

  test('大きいソースのパス注釈はテキストノードを一致ごとに読み直さない', () => {
    const wrap = dom.window.document.getElementById('diagram-wrap')!;
    wrap.innerHTML =
      '<code>' + '<span>./file.md ./other.ts</span><span> </span>'.repeat(1000) + '</code>';
    const nodes = Array.from(wrap.querySelectorAll('span'), (span) => span.firstChild as Text);
    let reads = 0;
    nodes.forEach((node) => {
      Object.defineProperty(node, 'textContent', {
        get: () => {
          reads++;
          return node.data;
        },
      });
    });

    _annotatePathRefs();

    expect(pathRefTexts()).toHaveLength(2000);
    expect(reads).toBeLessThanOrEqual(nodes.length * 2);
  });

  test('ASCII のみの相対パスを検出する', () => {
    dom.window.document.getElementById('diagram-wrap')!.innerHTML =
      '<p>参照: docs/dev/native-app-design.md を見る</p>';

    _annotatePathRefs();

    expect(pathRefTexts()).toContain('docs/dev/native-app-design.md');
  });

  test('日本語を含む相対パスを検出する', () => {
    dom.window.document.getElementById('diagram-wrap')!.innerHTML =
      '<p>参照: 20_経理/freeeナレッジ/freee-API操作.md を見る</p>';

    _annotatePathRefs();

    expect(pathRefTexts()).toContain('20_経理/freeeナレッジ/freee-API操作.md');
  });

  test('スペース区切りの無い日本語文にパスが直接続いても、地の文まで巻き込まない', () => {
    dom.window.document.getElementById('diagram-wrap')!.innerHTML =
      '<p>そのため20_経理/freeeナレッジ/freee-API操作.mdを確認する</p>';

    _annotatePathRefs();

    expect(pathRefTexts()).toEqual(['20_経理/freeeナレッジ/freee-API操作.md']);
  });
});
