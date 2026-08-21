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

  // TASK-485.19.3: 非対応モードのセグメントは、Swift 側 canJump(to:) 由来の
  // availableKinds（TASK-485.18 の可用性伝搬を流用）に基づき自動的に隠す。
  describe('モードの可用性に応じたセグメントの表示', () => {
    const segmentVisible = (document, mode) =>
      document.getElementById('mmd-bar-mode-' + mode).style.display !== 'none';

    test('Swift からまだ同期が届く前は見出し/変更箇所を隠し、検索だけ出す', () => {
      const { document } = loadViewerMain({});

      expect(segmentVisible(document, 'search')).toBe(true);
      expect(segmentVisible(document, 'heading')).toBe(false);
      expect(segmentVisible(document, 'changeBlock')).toBe(false);
    });

    test('_mmdApplyJumpAvailability で使える種類だけが表示される', () => {
      const { main, document } = loadViewerMain({});

      main._mmdApplyJumpAvailability(['heading']);

      expect(segmentVisible(document, 'heading')).toBe(true);
      expect(segmentVisible(document, 'changeBlock')).toBe(false);

      main._mmdApplyJumpAvailability(['heading', 'changeBlock']);

      expect(segmentVisible(document, 'heading')).toBe(true);
      expect(segmentVisible(document, 'changeBlock')).toBe(true);
    });

    test('開いているモードが使えなくなるとバーごと閉じ、外枠・選択状態・セグメントが揃って消える', () => {
      const { main, document } = loadViewerMain({});
      document.getElementById('diagram-wrap').innerHTML = '<h1>題</h1>';
      main._mmdApplyJumpAvailability(['heading', 'changeBlock']);
      main._mmdOpenJump('heading');
      expect(outerVisible(document)).toBe(true);

      main._mmdApplyJumpAvailability(['changeBlock']);

      expect(main._mmdJump.isOpen()).toBe(false);
      expect(outerVisible(document)).toBe(false);
      expect(activeModes(document)).toEqual([]);
      expect(segmentVisible(document, 'heading')).toBe(false);
    });
  });

  // TASK-485.19.3: 検索クエリ・トグル・見出しレベル選択は、find.ts / jump.ts が
  // もともと持つ「close() では消さない」振る舞い（本タスクの前から存在する）に
  // よって、モード切替をまたいでも自然に保持される。ここではその組み合わせが
  // スイッチ経由でも壊れていないことを固定する。
  describe('モード切替をまたぐ状態の保持', () => {
    test('検索クエリと大文字小文字トグルは、見出しへ切り替えて戻っても残る', () => {
      const { main, document } = loadViewerMain({});
      document.getElementById('diagram-wrap').innerHTML = '<h1>ABC</h1><p>abc abc</p>';
      main._mmdApplyJumpAvailability(['heading']);
      main._mmdOpenFind();
      const input = document.getElementById('mmd-find-input');
      input.value = 'abc';
      input.dispatchEvent(new document.defaultView.Event('input'));
      document.getElementById('mmd-find-case').click();
      expect(document.getElementById('mmd-find-count').textContent).toBe('1/2');

      clickMode(document, 'heading');
      clickMode(document, 'search');

      expect(document.getElementById('mmd-find-input').value).toBe('abc');
      expect(document.getElementById('mmd-find-case').classList.contains('active')).toBe(true);
      expect(document.getElementById('mmd-find-count').textContent).toBe('1/2');
    });

    test('見出しレベルの選択は、検索へ切り替えて戻っても残る', () => {
      const { main, document } = loadViewerMain({});
      document.getElementById('diagram-wrap').innerHTML = '<h1>a</h1><h2>b</h2>';
      main._mmdApplyJumpAvailability(['heading']);
      main._mmdOpenJump('heading');
      main.toggleHeadingLevel(1);
      expect(document.getElementById('mmd-jump-count').textContent).toBe('1/1');

      clickMode(document, 'search');
      clickMode(document, 'heading');

      expect(document.getElementById('mmd-jump-count').textContent).toBe('1/1');
      expect(document.getElementById('mmd-jump-level-h1').classList.contains('active')).toBe(false);
    });
  });

  // TASK-485.19.3 AC4: 非アクティブなモードは再描画のたびに列挙し直さない
  // （find.ts は既に呼び出し側の isOpen() ガードで、jump.ts は refresh() 内の
  // isJumpBarOpen() ガードでこれを満たしている。ここではその既存のガードが
  // 崩れていないことを固定する）。
  describe('非アクティブモードは再描画で無駄な列挙をしない', () => {
    test('検索を閉じたまま再描画しても、残っていたクエリで再検索されない', async () => {
      const { main, document } = loadViewerMain({});
      await main.render('abc\n', 'markdown');
      main._mmdOpenFind();
      const input = document.getElementById('mmd-find-input');
      input.value = 'abc';
      input.dispatchEvent(new document.defaultView.Event('input'));
      expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(1);
      main._mmdCloseFind();

      await main.render('abc abc\n', 'markdown');

      expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
    });
  });
});
