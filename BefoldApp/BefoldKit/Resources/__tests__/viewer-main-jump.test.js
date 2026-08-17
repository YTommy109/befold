// 文書内ジャンプの共通基盤（TASK-485.1）。目印の列挙はプロバイダに委ね、
// 位置・n/N 表示・ハイライト・再構築だけをコントローラが持つ、という
// 分担が保たれていることを検証する。
const { loadViewerMain } = require('./support/viewerMainHarness');

// 見出しを持つ Markdown 描画結果を用意し、ジャンプバーを開いた状態にする。
function openJumpOn(html) {
  const loaded = loadViewerMain({});
  loaded.document.getElementById('diagram-wrap').innerHTML = html;
  loaded.main._mmdOpenJump('heading');
  return loaded;
}

const HEADINGS = '<h1>題</h1><h2>あ</h2><p>x</p><h3>い</h3><h2>う</h2>';

// 両モードに存在する要素を目印にするテスト用プロバイダ。プロバイダの差し替えだけで
// 別種のジャンプが作れることの検証も兼ねる。
function registerAnyElementProvider(main) {
  main._mmdJump.register({
    id: 'test-any',
    collect: (root) =>
      Array.prototype.slice
        .call(root.querySelectorAll('*'), 0, 3)
        .map((element) => ({ anchor: element, highlight: [element] })),
  });
}

// ジャンプバーは入力欄を持たずキーボードフォーカスが乗らないため、
// バー要素の keydown では Enter を受け取れない（実機で確認）。document で拾う。
function pressEnter(loaded, shiftKey) {
  loaded.document.dispatchEvent(
    new loaded.window.KeyboardEvent('keydown', { key: 'Enter', shiftKey, bubbles: true }),
  );
}

const count = (document) => document.getElementById('mmd-jump-count').textContent;
const current = (document) => document.querySelector('.mmd-jump-current');

describe('文書内ジャンプ', () => {
  test('開くと目印の件数と先頭のハイライトが出る', () => {
    const { document } = openJumpOn(HEADINGS);

    // h1 は目印にしない（文書題名だけの文書で 1/1 しか出せず移動に使えない）。
    expect(count(document)).toBe('1/3');
    expect(current(document)).toBe(document.querySelectorAll('h2, h3')[0]);
  });

  test('次へ・前へで循環する', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/3');
    expect(current(document).textContent).toBe('い');

    main._mmdJumpNextIfOpen();
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('1/3');

    main._mmdJumpPrevIfOpen();
    expect(count(document)).toBe('3/3');
  });

  test('現在位置のハイライトは常に 1 つ', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdJumpNextIfOpen();

    expect(document.querySelectorAll('.mmd-jump-current').length).toBe(1);
  });

  test('目印が 0 個でも壊れず 0/0 を出す', () => {
    const { document } = openJumpOn('<p>見出しのない文書</p>');

    expect(count(document)).toBe('0/0');
    expect(current(document)).toBe(null);
  });

  test('目印が 0 個のとき次へ・前へは何もしない', () => {
    const { document, main } = openJumpOn('<p>見出しのない文書</p>');

    main._mmdJumpNextIfOpen();
    main._mmdJumpPrevIfOpen();

    expect(count(document)).toBe('0/0');
  });

  test('Enter で次の目印へ、Shift+Enter で前の目印へ動く', () => {
    const loaded = openJumpOn(HEADINGS);
    const { document } = loaded;

    pressEnter(loaded, false);
    expect(count(document)).toBe('2/3');

    pressEnter(loaded, true);
    expect(count(document)).toBe('1/3');
  });

  test('ジャンプバーが閉じている間は Enter で動かない', () => {
    const loaded = openJumpOn(HEADINGS);
    loaded.main._mmdCloseJump();

    pressEnter(loaded, false);

    expect(current(loaded.document)).toBe(null);
  });

  test('IME 変換確定の Enter では動かない', () => {
    const loaded = openJumpOn(HEADINGS);

    loaded.document.dispatchEvent(
      new loaded.window.KeyboardEvent('keydown', { key: 'Enter', keyCode: 229, bubbles: true }),
    );

    expect(count(loaded.document)).toBe('1/3');
  });

  test('Escape でジャンプバーが閉じる', () => {
    const loaded = openJumpOn(HEADINGS);

    loaded.document.dispatchEvent(
      new loaded.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
    );

    expect(loaded.document.getElementById('mmd-jump-bar').style.display).toBe('none');
    expect(current(loaded.document)).toBe(null);
  });

  test('閉じるとハイライトが消える', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdCloseJump();

    expect(current(document)).toBe(null);
    expect(document.getElementById('mmd-jump-bar').style.display).toBe('none');
  });

  test('バーが閉じている間は次へ・前へが効かない', () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdCloseJump();

    main._mmdJumpNextIfOpen();

    expect(current(document)).toBe(null);
  });

  test('段階読み込み中は件数に表示範囲のラベルが付く', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdSetTruncated(true, 100, false);

    expect(count(document)).toBe('1/3 (Displayed range)');
  });

  test('描画をやり直すと目印の列が作り直され、位置は保たれる', async () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/3');

    await main.render('## a\n\n### b\n\n## c\n', 'markdown');

    // 新しい文書の目印で作り直され、前の文書の要素は残らない。
    expect(count(document)).toBe('2/3');
    expect(current(document).textContent).toBe('b');
    expect(document.querySelectorAll('.mmd-jump-current').length).toBe(1);
  });

  test('描画の開始時に目印の列が捨てられる', () => {
    const { document, main } = openJumpOn(HEADINGS);
    expect(count(document)).toBe('1/3');

    // render() は mermaid の描画を await するため、着地までに間がある。
    // その間、前の文書の件数が残っていてはいけない。
    void main.render('## a\n', 'markdown');

    expect(count(document)).toBe('0/0');
  });

  test('目印が減ると現在位置は末尾へ寄せられる', async () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdJumpPrevIfOpen();
    expect(count(document)).toBe('3/3');

    await main.render('## only\n', 'markdown');

    expect(count(document)).toBe('1/1');
  });

  // _mmdModeSwitch.consume() は破壊的読み出しで、読み手が 2 つになると後の
  // 1 つが必ず false を受け取る。検索とジャンプは同時に開かない設計なので
  // 「両方が同じ 1 回の消費を見る」ことは同時には確かめられない。
  // ジャンプ側が持ち越しを観測できることをもって、消費が共有されていることを担保する。
  //
  // 見出しはレンダリング表示にしか無く、ソース表示を挟むと列が空になって位置が
  // 失われる（＝持ち越しの有無で結果が変わらず、テストが空振りする）。そこで
  // 両モードに存在する要素を拾うプロバイダを登録して測る。
  // これはプロバイダの差し替えだけで別種のジャンプが作れること自体の検証も兼ねる。
  async function openAnyElementJumpOnCsv() {
    const loaded = loadViewerMain({});
    registerAnyElementProvider(loaded.main);
    await loaded.main.render('a,b\nc,d\n', 'csv', ',');
    loaded.main._mmdOpenJump('test-any');
    return loaded;
  }

  test('モード切替を伴う描画ではジャンプ位置が先頭に戻る', async () => {
    const { document, main } = await openAnyElementJumpOnCsv();
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/3');

    main.setViewMode('source');
    await main.render('a,b\nc,d\n', 'csv', ',');

    expect(count(document)).toBe('1/3');
  });

  test('モードを切り替えない再描画ではジャンプ位置が維持される', async () => {
    const { document, main } = await openAnyElementJumpOnCsv();
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/3');

    await main.render('a,b\nc,d\n', 'csv', ',');

    expect(count(document)).toBe('2/3');
  });

  test('目印の列挙はプロバイダだけが持つ', () => {
    const { main } = loadViewerMain({});
    const document_ = main;

    // collectHeadings は DOM を受け取り目印列を返す純粋な列挙。
    expect(typeof document_.collectHeadings).toBe('function');
    expect(document_.headingJumpProvider.id).toBe('heading');
  });
});

describe('見出しの列挙（collectHeadings）', () => {
  function rootWith(html) {
    const { document } = loadViewerMain({});
    const root = document.getElementById('diagram-wrap');
    root.innerHTML = html;
    return { root, main: loadViewerMain };
  }

  test('h2 と h3 を文書順に拾い、h1 と h4 は拾わない', () => {
    const { root } = rootWith('<h1>0</h1><h3>1</h3><h2>2</h2><h4>x</h4><h3>3</h3>');
    const { collectHeadings } = require('../../../viewer-src/main.js');

    const texts = collectHeadings(root).map((target) => target.anchor.textContent);

    expect(texts).toEqual(['1', '2', '3']);
  });

  test('目印はスクロール先と強調対象を持つ', () => {
    const { root } = rootWith('<h2>a</h2>');
    const { collectHeadings } = require('../../../viewer-src/main.js');

    const [target] = collectHeadings(root);

    expect(target.anchor).toBe(root.querySelector('h2'));
    expect(target.highlight).toEqual([root.querySelector('h2')]);
  });

  test('見出しが無ければ空の列になる', () => {
    const { root } = rootWith('<p>なし</p>');
    const { collectHeadings } = require('../../../viewer-src/main.js');

    expect(collectHeadings(root)).toEqual([]);
  });
});
