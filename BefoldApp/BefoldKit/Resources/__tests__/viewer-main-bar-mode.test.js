// バー右上のモード切替スイッチ（検索/見出し/変更箇所、TASK-485.19.2）。
// 実際の検索・列挙ロジックは find.ts / jump.ts が持つため、ここでは
// 「クリックで正しいモードが開くか」「選択状態の見た目が実際の開閉と揃うか」
// だけを検証する。
const { loadViewerMain } = require('./support/viewerMainHarness');

const outerVisible = (document) => document.getElementById('mmd-bar').style.display === 'flex';

const activeModes = (document) =>
  ['search', 'heading', 'changeBlock']
    .filter((mode) => document.getElementById('mmd-bar-mode-' + mode).classList.contains('active'))
    .sort();

const clickMode = (document, mode) => {
  document.getElementById('mmd-bar-mode-' + mode).click();
};

describe('バーのモード切替スイッチ', () => {
  test('何も開いていない間は外枠が非表示で、どのセグメントも選択状態を持たない', () => {
    const { document } = loadViewerMain({});

    expect(outerVisible(document)).toBe(false);
    expect(activeModes(document)).toEqual([]);
  });

  test('検索を開くと外枠が表示され、検索セグメントだけが選択状態になる', () => {
    const { main, document } = loadViewerMain({});

    main._mmdOpenFind();

    expect(outerVisible(document)).toBe(true);
    expect(activeModes(document)).toEqual(['search']);
  });

  test('見出しセグメントをクリックすると見出しジャンプが開き、検索は閉じる', () => {
    const { main, document } = loadViewerMain({});
    document.getElementById('diagram-wrap').innerHTML = '<h1>題</h1>';
    main._mmdOpenFind();

    clickMode(document, 'heading');

    expect(main._mmdFind.isOpen()).toBe(false);
    expect(main._mmdJump.isOpen()).toBe(true);
    expect(main._mmdJump.activeMode()).toBe('heading');
    expect(activeModes(document)).toEqual(['heading']);
  });

  test('見出しから変更箇所への切り替え（jump 内部の kind 変更）でも選択表示が移る', () => {
    const { main, document } = loadViewerMain({});
    document.getElementById('diagram-wrap').innerHTML = '<h1>題</h1>';
    main._mmdOpenJump('heading');
    expect(activeModes(document)).toEqual(['heading']);

    clickMode(document, 'changeBlock');

    expect(main._mmdJump.isOpen()).toBe(true);
    expect(main._mmdJump.activeMode()).toBe('changeBlock');
    expect(activeModes(document)).toEqual(['changeBlock']);
  });

  test('検索セグメントをクリックすると検索バーが開く', () => {
    const { main, document } = loadViewerMain({});
    main._mmdOpenJump('heading');

    clickMode(document, 'search');

    expect(main._mmdJump.isOpen()).toBe(false);
    expect(main._mmdFind.isOpen()).toBe(true);
    expect(activeModes(document)).toEqual(['search']);
  });

  test('Escape で閉じると外枠も非表示に戻り、選択状態も消える', () => {
    const { main, document, window } = loadViewerMain({});
    main._mmdOpenFind();
    expect(outerVisible(document)).toBe(true);

    document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));

    expect(outerVisible(document)).toBe(false);
    expect(activeModes(document)).toEqual([]);
  });
});
