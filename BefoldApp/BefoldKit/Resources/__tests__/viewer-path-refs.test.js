// 裸のパス文字列の自動リンク化（path-refs.ts）。GitHub Issue #653。
//
// _PATH_RE が \w（ASCII のみ）で構成要素を拾うため、日本語を含むパスが
// 検出段階で候補にすらならなかった不具合を固定する。

const { JSDOM } = require('jsdom');

const { _annotatePathRefs } = require('../../../viewer-src/path-refs.js');

const dom = new JSDOM('<div id="diagram-wrap"></div>');

beforeEach(() => {
  global.document = dom.window.document;
  global.Text = dom.window.Text;
  global.Element = dom.window.Element;
  dom.window.document.getElementById('diagram-wrap').innerHTML = '';
});

function pathRefTexts() {
  return Array.from(dom.window.document.querySelectorAll('#diagram-wrap .befold-path-ref')).map(
    (el) => el.dataset.path,
  );
}

describe('_annotatePathRefs', () => {
  test('ASCII のみの相対パスを検出する', () => {
    dom.window.document.getElementById('diagram-wrap').innerHTML =
      '<p>参照: docs/dev/native-app-design.md を見る</p>';

    _annotatePathRefs();

    expect(pathRefTexts()).toContain('docs/dev/native-app-design.md');
  });

  test('日本語を含む相対パスを検出する', () => {
    dom.window.document.getElementById('diagram-wrap').innerHTML =
      '<p>参照: 20_経理/freeeナレッジ/freee-API操作.md を見る</p>';

    _annotatePathRefs();

    expect(pathRefTexts()).toContain('20_経理/freeeナレッジ/freee-API操作.md');
  });

  test('スペース区切りの無い日本語文にパスが直接続いても、地の文まで巻き込まない', () => {
    dom.window.document.getElementById('diagram-wrap').innerHTML =
      '<p>そのため20_経理/freeeナレッジ/freee-API操作.mdを確認する</p>';

    _annotatePathRefs();

    expect(pathRefTexts()).toEqual(['20_経理/freeeナレッジ/freee-API操作.md']);
  });
});
