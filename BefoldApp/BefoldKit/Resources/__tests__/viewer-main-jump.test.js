// 文書内ジャンプの共通基盤（TASK-485.1）。目印の列挙はプロバイダに委ね、
// 位置・n/N 表示・ハイライト・再構築だけをコントローラが持つ、という
// 分担が保たれていることを検証する。
const { loadViewerMain, captureBridgeMessages } = require('./support/viewerMainHarness');

// 見出しを持つ Markdown 描画結果を用意し、ジャンプバーを開いた状態にする。
function openJumpOn(html) {
  const loaded = loadViewerMain({});
  loaded.document.getElementById('diagram-wrap').innerHTML = html;
  loaded.main._mmdOpenJump('heading');
  return loaded;
}

// h1 1 個 + h2 2 個 + h3 1 個。既定（h1/h2/h3 すべて ON）では 4 件になる。
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

const levelButton = (document, level) => document.getElementById('mmd-jump-level-h' + level);

// ジャンプバーは入力欄を持たずキーボードフォーカスが乗らないため、
// バー要素の keydown では Enter を受け取れない（実機で確認）。document で拾う。
function pressEnter(loaded, shiftKey) {
  loaded.document.dispatchEvent(
    new loaded.window.KeyboardEvent('keydown', { key: 'Enter', shiftKey, bubbles: true }),
  );
}

// 修飾キー付きの Enter。dispatchEvent の戻り値で「既定動作を奪っていないか」を見る
// （preventDefault されていれば false になる）。
function pressEnterWith(loaded, modifiers) {
  return loaded.document.dispatchEvent(
    new loaded.window.KeyboardEvent(
      'keydown',
      Object.assign({ key: 'Enter', bubbles: true, cancelable: true }, modifiers),
    ),
  );
}

// 差分表示の行番号ガター（旧側・新側）のセル。変更ブロックの目印はここへ付く。
const numberCells = (oldNumber, newNumber) =>
  '<td class="line-number diff-old">' +
  oldNumber +
  '</td><td class="line-number diff-new">' +
  newNumber +
  '</td>';

// 列挙は必ず「その harness が読み込んだモジュール」から呼ぶ。require で別途
// 読み直すと _mmdDocument が別インスタンスになり、描いた形の記録が空のまま
// レンダリング表示として扱われる（TASK-485.17 のテストを書いたとき実際に踏んだ）。
const headingTexts = (loaded) =>
  loaded.main
    .collectHeadings(loaded.document.getElementById('diagram-wrap'))
    .map((target) => target.anchor.textContent.trim());

const isBarVisible = (document) => document.getElementById('mmd-jump-panel').style.display === 'flex';

const count = (document) => document.getElementById('mmd-jump-count').textContent;
const current = (document) => document.querySelector('.mmd-jump-current');

describe('文書内ジャンプ', () => {
  test('開くと目印の件数と先頭のハイライトが出る', () => {
    const { document } = openJumpOn(HEADINGS);

    // 既定は h1 / h2 / h3 すべて ON。h1 を含むのは h1 が複数ある文書があるため。
    expect(count(document)).toBe('1/4');
    expect(current(document)).toBe(document.querySelectorAll('h1, h2, h3')[0]);
  });

  test('開いている間は目印の候補すべてに印が付く', () => {
    const { document, main } = openJumpOn(HEADINGS);

    expect(document.querySelectorAll('.mmd-jump-target').length).toBe(4);

    main._mmdJump.close();

    expect(document.querySelectorAll('.mmd-jump-target').length).toBe(0);
  });

  test('次へ・前へで循環する', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/4');
    expect(current(document).textContent).toBe('あ');

    main._mmdJumpNextIfOpen();
    main._mmdJumpNextIfOpen();
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('1/4');

    main._mmdJumpPrevIfOpen();
    expect(count(document)).toBe('4/4');
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
    expect(count(document)).toBe('2/4');

    pressEnter(loaded, true);
    expect(count(document)).toBe('1/4');
  });

  // 実機で見つけた回帰(TASK-485.19): _mmdInitJump() が外枠のリネーム
  // (#mmd-jump-bar → #mmd-jump-panel、TASK-485.19.2)に追随し忘れたコード
  // (`document.getElementById('mmd-jump-bar')` が null を返し、wireBarControls
  // が一度も呼ばれない)により、前へ/次へ/閉じるボタンのクリックが完全に
  // 無反応になっていた。Enter/Shift+Enter は document 側の別経路
  // (keyboard.ts)で動くため気づけず、既存テストも _mmdJumpNextIfOpen() 等の
  // 直接呼び出しか Enter キーだけを確認しており、実際のボタン要素への
  // click() を一度も検証していなかった。ここでボタンの click() を直接
  // シミュレートして固定する。
  test('前へ/次へ/閉じるボタンをクリックすると反応する', () => {
    const loaded = openJumpOn(HEADINGS);
    const { document } = loaded;

    document.getElementById('mmd-jump-next').click();
    expect(count(document)).toBe('2/4');

    document.getElementById('mmd-jump-prev').click();
    expect(count(document)).toBe('1/4');

    document.getElementById('mmd-jump-close').click();
    expect(loaded.main._mmdJump.isOpen()).toBe(false);
  });

  test('ジャンプバーが閉じている間は Enter で動かない', () => {
    const loaded = openJumpOn(HEADINGS);
    loaded.main._mmdJump.close();

    pressEnter(loaded, false);

    expect(current(loaded.document)).toBe(null);
  });

  // TASK-485.6: ジャンプバーは document で Enter を拾うため、放っておくと
  // 修飾キー付きのチョードやリンク上の Enter まで消費してしまう。
  test.each([
    ['Cmd+Enter', { metaKey: true }],
    ['Ctrl+Enter', { ctrlKey: true }],
    ['Alt+Enter', { altKey: true }],
  ])('%s ではジャンプせず既定動作のまま通る', (_name, modifiers) => {
    const loaded = openJumpOn(HEADINGS);

    const notPrevented = pressEnterWith(loaded, modifiers);

    expect(count(loaded.document)).toBe('1/4');
    expect(notPrevented).toBe(true);
  });

  test('フォーカス中のリンク上の Enter はジャンプに奪われない', () => {
    const loaded = openJumpOn(HEADINGS + '<p><a href="https://example.com">リンク</a></p>');
    loaded.document.querySelector('a[href]').focus();

    const notPrevented = pressEnterWith(loaded, {});

    expect(count(loaded.document)).toBe('1/4');
    expect(notPrevented).toBe(true);
  });

  // contenteditable は対象に含めていない。jsdom は isContentEditable を実装しておらず
  // （contenteditable="true" を付けても false のまま）、ここで書いても分岐を固定できない。
  // 実装側は残してある（スクロール側の素通し判定と同じ理由で編集中は奪わない）。
  test.each([
    ['ボタン', '<button id="focus-me">押す</button>'],
    ['入力欄', '<input id="focus-me">'],
  ])('フォーカス中の%s上の Enter はジャンプに奪われない', (_name, markup) => {
    const loaded = openJumpOn(HEADINGS + markup);
    loaded.document.getElementById('focus-me').focus();

    const notPrevented = pressEnterWith(loaded, {});

    expect(count(loaded.document)).toBe('1/4');
    expect(notPrevented).toBe(true);
  });

  test('href の無い <a> にフォーカスがあるときは Enter でジャンプする', () => {
    const loaded = openJumpOn(HEADINGS + '<p><a id="no-href" tabindex="0">印</a></p>');
    loaded.document.getElementById('no-href').focus();

    pressEnter(loaded, false);

    expect(count(loaded.document)).toBe('2/4');
  });

  test('IME 変換確定の Enter では動かない', () => {
    const loaded = openJumpOn(HEADINGS);

    loaded.document.dispatchEvent(
      new loaded.window.KeyboardEvent('keydown', { key: 'Enter', keyCode: 229, bubbles: true }),
    );

    expect(count(loaded.document)).toBe('1/4');
  });

  test('Escape でジャンプバーが閉じる', () => {
    const loaded = openJumpOn(HEADINGS);

    loaded.document.dispatchEvent(
      new loaded.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }),
    );

    expect(loaded.document.getElementById('mmd-jump-panel').style.display).toBe('none');
    expect(current(loaded.document)).toBe(null);
  });

  test('閉じるとハイライトが消える', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdJump.close();

    expect(current(document)).toBe(null);
    expect(document.getElementById('mmd-jump-panel').style.display).toBe('none');
  });

  test('バーが閉じている間は次へ・前へが効かない', () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdJump.close();

    main._mmdJumpNextIfOpen();

    expect(current(document)).toBe(null);
  });

  test('段階読み込み中は件数に表示範囲のラベルが付く', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdSetTruncated(true, 100, false);

    expect(count(document)).toBe('1/4 (Displayed range)');
  });

  test('描画をやり直すと目印の列が作り直され、位置は保たれる', async () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/4');

    await main.render('## a\n\n### b\n\n## c\n', 'markdown');

    // 新しい文書の目印で作り直され、前の文書の要素は残らない。
    expect(count(document)).toBe('2/3');
    expect(current(document).textContent).toBe('b');
    expect(document.querySelectorAll('.mmd-jump-current').length).toBe(1);
  });

  test('描画の開始時に目印の列が捨てられる', () => {
    const { document, main } = openJumpOn(HEADINGS);
    expect(count(document)).toBe('1/4');

    // render() は mermaid の描画を await するため、着地までに間がある。
    // その間、前の文書の件数が残っていてはいけない。
    void main.render('## a\n', 'markdown');

    expect(count(document)).toBe('0/0');
  });

  test('目印が減ると現在位置は末尾へ寄せられる', async () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdJumpPrevIfOpen();
    expect(count(document)).toBe('4/4');

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

describe('見出しレベルのトグル', () => {
  test('既定では 3 つとも ON', () => {
    const { main } = loadViewerMain({});

    expect(main.selectedHeadingLevels()).toEqual([1, 2, 3]);
  });

  test('OFF にしたレベルの見出しは目印から外れる', () => {
    const { document, main } = openJumpOn(HEADINGS);
    expect(count(document)).toBe('1/4');

    main.toggleHeadingLevel(1);

    // h1 が 1 個減る。候補の印も付け直される。
    expect(count(document)).toBe('1/3');
    expect(document.querySelectorAll('.mmd-jump-target').length).toBe(3);
    expect(document.querySelector('h1').classList.contains('mmd-jump-target')).toBe(false);
  });

  test('3 つとも OFF にしても壊れず 0/0 になる', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main.toggleHeadingLevel(1);
    main.toggleHeadingLevel(2);
    main.toggleHeadingLevel(3);

    expect(main.selectedHeadingLevels()).toEqual([]);
    expect(count(document)).toBe('0/0');
    expect(document.querySelectorAll('.mmd-jump-target').length).toBe(0);
  });

  // 「表示範囲内」は"まだ読んでいない範囲は数えられていない"という意味なので、
  // レベルを 1 つも選んでいないことが原因の 0 件では出さない。
  test('レベル未選択による 0 件では表示範囲のラベルを出さない', () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdSetTruncated(true, 100, false);
    expect(count(document)).toBe('1/4 (Displayed range)');

    main.toggleHeadingLevel(1);
    main.toggleHeadingLevel(2);
    main.toggleHeadingLevel(3);

    expect(count(document)).toBe('0/0');
  });

  // 実機で見つけた不具合の回帰テスト。バーを閉じたまま描画すると invalidate で
  // 描画中フラグが立つが、着地の refresh はバーが開いているときしか呼ばれない。
  // フラグが残ったままだと、以後トグルを押しても列が作り直されない。
  test('バーを閉じたまま描画したあとでも、トグルで列が作り直される', async () => {
    const loaded = loadViewerMain({});
    await loaded.main.render('# a\n\n## b\n\n### c\n', 'markdown');
    loaded.main._mmdOpenJump('heading');
    expect(count(loaded.document)).toBe('1/3');

    loaded.main.toggleHeadingLevel(1);

    expect(count(loaded.document)).toBe('1/2');
    expect(loaded.document.querySelector('h1').classList.contains('mmd-jump-target')).toBe(false);
  });

  // 描画中（invalidate から着地の refresh までの間）にバーを開き、レベルを
  // トグルしても列は作り直さない。作り直すと差し替え途中の DOM から作った
  // currentIndex を着地の refresh が位置維持の入力に使ってしまう。
  // 着地の refresh が新しい条件で作り直すので、抑止しても取りこぼさない。
  test('描画中にバーを開いてレベルをトグルしても列は作り直されない', async () => {
    const loaded = loadViewerMain({});
    const pending = loaded.main.render('# a\n\n## b\n\n### c\n', 'markdown');
    loaded.main._mmdOpenJump('heading');
    expect(count(loaded.document)).toBe('1/3');

    loaded.main.toggleHeadingLevel(1);

    // 抑止されていれば列は開いたときのまま（h1 を含む 3 件）。
    expect(count(loaded.document)).toBe('1/3');

    await pending;

    // 着地の refresh が新しい条件で作り直す。
    expect(count(loaded.document)).toBe('1/2');
    expect(loaded.document.querySelector('h1').classList.contains('mmd-jump-target')).toBe(false);
  });

  // 描画中フラグを下ろすのは refresh の 1 箇所だけなので、バーを閉じたままの
  // 描画でも着地で必ず下りる。ただし閉じている間に列を作ると候補の下線が
  // 付いてしまうため、refresh はフラグを下ろしたら何もせずに戻る。
  test('バーを閉じたまま描画しても候補の印は付かない', async () => {
    const loaded = loadViewerMain({});
    loaded.main._mmdOpenJump('heading');
    loaded.main._mmdJump.close();

    await loaded.main.render('# a\n\n## b\n', 'markdown');

    expect(loaded.document.querySelectorAll('.mmd-jump-target').length).toBe(0);
  });

  test('トグルを戻すと目印が復活する', () => {
    const { document, main } = openJumpOn(HEADINGS);
    main.toggleHeadingLevel(2);
    expect(count(document)).toBe('1/2');

    main.toggleHeadingLevel(2);

    expect(count(document)).toBe('1/4');
  });

  test('レベルを変えると現在位置は先頭へ戻る', () => {
    const { document, main } = openJumpOn(HEADINGS);
    main._mmdJumpNextIfOpen();
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('3/4');

    main.toggleHeadingLevel(3);

    expect(count(document)).toBe('1/3');
  });

  test('トグルの操作を jumpLevelsChanged で Swift へ通知する', () => {
    const loaded = openJumpOn(HEADINGS);
    const received = captureBridgeMessages(loaded.window, ['jumpLevelsChanged']);

    loaded.main.toggleHeadingLevel(1);

    // Swift の HeadingJumpLevels.storedValue と同じ "h1" 形式で送る。
    // 数値のまま送ると受け手が解釈できず「3 つとも OFF」として保存される（実機で発覚）。
    expect(received).toEqual([{ name: 'jumpLevelsChanged', payload: { levels: ['h2', 'h3'] } }]);
  });

  // ハーネスは loadViewerMain の中で _mmdInit() を呼ぶ（＝配線済み）。
  // テスト側で初期化関数をもう一度呼ぶとリスナーが二重に付き、1 クリックで
  // 2 回トグルされて元に戻るので、ここでは呼ばない。
  test('ボタンのクリックでもトグルが働く', () => {
    const loaded = openJumpOn(HEADINGS);

    levelButton(loaded.document, 1).click();

    expect(loaded.main.selectedHeadingLevels()).toEqual([2, 3]);
    expect(levelButton(loaded.document, 1).classList.contains('active')).toBe(false);
  });

  test('保存済みのレベルが復元され、ボタンの見た目も揃う', () => {
    const loaded = loadViewerMain({ initialJumpLevels: ['h2'] });

    expect(loaded.main.selectedHeadingLevels()).toEqual([2]);
    expect(levelButton(loaded.document, 2).classList.contains('active')).toBe(true);
    expect(levelButton(loaded.document, 1).classList.contains('active')).toBe(false);
  });

  test('保存値が「3 つとも OFF」なら、それを尊重して既定へ戻さない', () => {
    const loaded = loadViewerMain({ initialJumpLevels: [] });

    expect(loaded.main.selectedHeadingLevels()).toEqual([]);
  });

  test('注入が無ければ既定の 3 つとも ON', () => {
    const loaded = loadViewerMain({});

    expect(loaded.main.selectedHeadingLevels()).toEqual([1, 2, 3]);
  });

  // Swift 側はエンコードに失敗したとき null を注入する（ViewerBridge.defaultingFallback）。
  // 空配列だと「3 つとも OFF」の意味になり、目印が 0 件へ縮退してしまう。
  test('null が注入されたら既定の 3 つとも ON（全 OFF へ縮退しない）', () => {
    const loaded = loadViewerMain({ initialJumpLevels: null });

    expect(loaded.main.selectedHeadingLevels()).toEqual([1, 2, 3]);
  });
});

describe('見出しの列挙（collectHeadings）', () => {
  function rootWith(html) {
    const { document } = loadViewerMain({});
    const root = document.getElementById('diagram-wrap');
    root.innerHTML = html;
    return { root, main: loadViewerMain };
  }

  test('既定では h1 / h2 / h3 を文書順に拾い、h4 以降は拾わない', () => {
    const { root } = rootWith('<h1>0</h1><h3>1</h3><h2>2</h2><h4>x</h4><h3>3</h3>');
    const { collectHeadings } = require('../../../viewer-src/main.js');

    const texts = collectHeadings(root).map((target) => target.anchor.textContent);

    expect(texts).toEqual(['0', '1', '2', '3']);
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

// 変更ブロックのジャンプ（TASK-485.3）。列挙は描画時に振られた data-diff-block だけを
// 読むので、DOM の形（インラインは tr にクラス、分割は側セルにクラス）に依存しない。
describe('変更ブロックのジャンプ', () => {
  // 差分表示 2 レイアウトの最小 DOM。属性の付き方は viewer-diff.test.js が
  // 実描画で担保しているので、ここは列挙・ハイライト・件数だけを見る。
  const INLINE_DIFF_DOM = [
    '<table class="code-table diff-table">',
    '<tr class="diff-line diff-context">' +
      numberCells(1, 1) +
      '<td class="diff-marker"> </td><td class="line-content">a</td></tr>',
    '<tr class="diff-line diff-del" data-diff-block="0">' +
      numberCells(2, '') +
      '<td class="diff-marker">-</td><td class="line-content">b</td></tr>',
    '<tr class="diff-line diff-add" data-diff-block="0">' +
      numberCells('', 2) +
      '<td class="diff-marker">+</td><td class="line-content">B</td></tr>',
    '<tr class="diff-line diff-context">' +
      numberCells(3, 3) +
      '<td class="diff-marker"> </td><td class="line-content">c</td></tr>',
    '<tr class="diff-line diff-add" data-diff-block="1">' +
      numberCells('', 4) +
      '<td class="diff-marker">+</td><td class="line-content">d</td></tr>',
    '</table>',
  ].join('');

  const SPLIT_DIFF_DOM = [
    '<table class="code-table diff-table diff-split">',
    '<tr class="diff-line"><td class="diff-side diff-side-left diff-context">a</td>' +
      '<td class="diff-side diff-side-right diff-context">a</td></tr>',
    '<tr class="diff-line" data-diff-block="0">' +
      '<td class="diff-side diff-side-left diff-del"><table class="diff-side-table"><tr>' +
      '<td class="line-number diff-old">2</td><td class="diff-marker">-</td>' +
      '<td class="line-content">b</td></tr></table></td>' +
      '<td class="diff-side diff-side-right diff-add"><table class="diff-side-table"><tr>' +
      '<td class="line-number diff-new">2</td><td class="diff-marker">+</td>' +
      '<td class="line-content">B</td></tr></table></td></tr>',
    '<tr class="diff-line"><td class="diff-side diff-side-left diff-context">c</td>' +
      '<td class="diff-side diff-side-right diff-context">c</td></tr>',
    '<tr class="diff-line" data-diff-block="1">' +
      '<td class="diff-side diff-side-left diff-empty"><table class="diff-side-table"><tr>' +
      '<td class="line-number diff-old"></td><td class="diff-marker diff-empty"></td>' +
      '<td class="line-content diff-empty"></td></tr></table></td>' +
      '<td class="diff-side diff-side-right diff-add"><table class="diff-side-table"><tr>' +
      '<td class="line-number diff-new">4</td><td class="diff-marker">+</td>' +
      '<td class="line-content">d</td></tr></table></td></tr>',
    '</table>',
  ].join('');

  function openChangeBlockJumpOn(html) {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap').innerHTML = html;
    loaded.main._mmdOpenJump('changeBlock');
    return loaded;
  }

  test.each([
    ['インライン', INLINE_DIFF_DOM],
    ['左右分割', SPLIT_DIFF_DOM],
  ])('%s: 連続する変更行が 1 件にまとまる', (_name, dom) => {
    const { document } = openChangeBlockJumpOn(dom);

    expect(count(document)).toBe('1/2');
  });

  test('前後移動でブロック単位に進む', () => {
    const { document, main } = openChangeBlockJumpOn(INLINE_DIFF_DOM);

    main._mmdJumpNextIfOpen();

    expect(count(document)).toBe('2/2');
  });

  // TASK-485.19.4: resolveJumpNavigationKey は openBar（'jump'かどうか）だけを見て
  // activeKind（heading/changeBlock）を区別しないため、実際の Enter キー入力
  // （document の keydown 経由）でも見出しと同じ経路で動くはず。既存の
  // Enter キー確認テストは見出しモードだけだったので、変更箇所モードでも
  // 同じ経路を通ることをここで固定する。
  test('Enter で次の変更箇所へ、Shift+Enter で前の変更箇所へ動く（見出しと同じキー経路）', () => {
    const loaded = openChangeBlockJumpOn(INLINE_DIFF_DOM);
    const { document } = loaded;

    pressEnter(loaded, false);
    expect(count(document)).toBe('2/2');

    pressEnter(loaded, true);
    expect(count(document)).toBe('1/2');
  });

  // アクティブなブロックは各行の左端セルへ印を付ける（CSS が左辺だけの帯にする）。
  // 行数の多いブロックでも 1 本の帯に見え、地色を潰さない。
  test('アクティブなブロックの各行の左端セルに印が付く', () => {
    const { document } = openChangeBlockJumpOn(INLINE_DIFF_DOM);

    const highlighted = Array.from(document.querySelectorAll('.mmd-jump-current'));

    // 先頭ブロックは 2 行なので 2 セル。どれも行の最初のセル。
    expect(highlighted.length).toBe(2);
    expect(highlighted.every((cell) => cell === cell.parentElement.firstElementChild)).toBe(true);
    expect(highlighted.map((cell) => cell.closest('[data-diff-block]').dataset.diffBlock)).toEqual([
      '0',
      '0',
    ]);
  });

  test('左右分割では左のペインに印が付く', () => {
    const { document } = openChangeBlockJumpOn(SPLIT_DIFF_DOM);

    const highlighted = Array.from(document.querySelectorAll('.mmd-jump-current'));

    expect(highlighted.length).toBe(1);
    expect(highlighted[0].classList.contains('diff-side-left')).toBe(true);
  });

  test('移動すると印が次のブロックへ移る', () => {
    const { document, main } = openChangeBlockJumpOn(INLINE_DIFF_DOM);

    main._mmdJumpNextIfOpen();

    const highlighted = Array.from(document.querySelectorAll('.mmd-jump-current'));
    expect(highlighted.length).toBe(1);
    expect(highlighted[0].closest('[data-diff-block]').dataset.diffBlock).toBe('1');
  });

  // 現在位置の印の外し方が「列の全要素を走査する」形へ戻ると落ちる（TASK-485.12）。
  // 全面書き換えの差分は 1 ブロックが数千行になりうるので、移動のたびに全変更行を
  // 走査すると Enter 連打が O(全変更行) になる。
  test('移動時に外す印は直前のブロックの分だけ', () => {
    const rows = [];
    // 20 行のブロック 2 つ。全走査なら 40 回、直前のブロックだけなら 20 回外す。
    for (let block = 0; block < 2; block += 1) {
      for (let line = 0; line < 20; line += 1) {
        rows.push(
          '<tr class="diff-line diff-add" data-diff-block="' +
            block +
            '">' +
            numberCells('', line + 1) +
            '<td class="diff-marker">+</td><td class="line-content">x</td></tr>',
        );
      }
    }
    const loaded = openChangeBlockJumpOn(
      '<table class="code-table diff-table">' + rows.join('') + '</table>',
    );
    const originalRemove = loaded.window.DOMTokenList.prototype.remove;
    let removals = 0;
    loaded.window.DOMTokenList.prototype.remove = function (...names) {
      if (names.includes('mmd-jump-current')) removals += 1;
      return originalRemove.apply(this, names);
    };

    loaded.main._mmdJumpNextIfOpen();

    loaded.window.DOMTokenList.prototype.remove = originalRemove;
    expect(removals).toBe(20);
  });

  // 印が付いていても、移動先はスクロール対象でも確かめる。
  test('移動するとブロックの先頭行までスクロールする', () => {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap').innerHTML = INLINE_DIFF_DOM;
    const scrolled = [];
    loaded.window.Element.prototype.scrollIntoView = function () {
      scrolled.push(this);
    };

    loaded.main._mmdOpenJump('changeBlock');
    loaded.main._mmdJumpNextIfOpen();

    expect(scrolled.map((element) => element.dataset.diffBlock)).toEqual(['0', '1']);
  });

  // 差分表示は setDiff で渡った全文から表を組み、appendChunk は追記をスキップするため、
  // 本文が段階読み込み中でも変更ブロックは全数そろっている。
  test('段階読み込み中でも表示範囲のラベルを出さない', () => {
    const { document, main } = openChangeBlockJumpOn(INLINE_DIFF_DOM);

    main._mmdSetTruncated(true, 100, false);

    expect(count(document)).toBe('1/2');
  });

  // AC#3。レイアウト切替は Swift が setDiffLayout の直後に render を送る形なので、
  // 着地時の refresh が位置を維持する。番号が両レイアウトで同じだからこれが意味を持つ。
  test('レイアウトを切り替えても現在位置が保たれる', async () => {
    const DIFF = [
      'diff --git a/a.txt b/a.txt',
      '--- a/a.txt',
      '+++ b/a.txt',
      '@@ -1,4 +1,4 @@',
      ' one',
      '-two',
      '+TWO',
      ' three',
      '-four',
      '+FOUR',
      '',
    ].join('\n');
    const { document, main } = loadViewerMain({});
    main.setViewMode('source');
    main.setDiff(DIFF);
    await main.render('dummy', 'plaintext');
    main._mmdOpenJump('changeBlock');
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/2');

    main.setDiffLayout('side-by-side');
    await main.render('dummy', 'plaintext');

    expect(count(document)).toBe('2/2');
  });

  test('見出しレベルのトグルは見出しジャンプのときだけ出す', () => {
    const { document, main } = openChangeBlockJumpOn(INLINE_DIFF_DOM);
    expect(document.getElementById('mmd-jump-levels').style.display).toBe('none');

    main._mmdOpenJump('heading');

    expect(document.getElementById('mmd-jump-levels').style.display).toBe('flex');
  });
});

// Markdown ソース表示の見出しジャンプ（TASK-485.17）。
//
// 中心はレンダリング表示との一致で、これが「フェンス内の # を拾わない」
// 「レベルトグルが両モードで共有される」を同時に担保する。列挙が
// _mmdDocument.shape()（render が実際に描いた形）だけを見ることも、
// 差分表示・CSV ソース・Markdown 以外のソースが 0 件になることで確かめる。
describe('Markdown ソース表示の見出しジャンプ', () => {
  // 実描画を通す。DOM を手で組むと「shape をどう記録したか」を確かめられない。
  async function renderMarkdown(mode, content, options) {
    const loaded = loadViewerMain(options ?? {});
    loaded.main.setViewMode(mode);
    await loaded.main.render(content, 'md');
    return loaded;
  }

  // ATX 見出しだけで書いた文書。setext（=== / --- による下線）は対象外なので
  // 使わない（ソース側は行頭 # だけを見るため、混ぜると両モードが一致しない）。
  const DOC = [
    '# 題',
    '',
    'ほんぶん',
    '',
    '## あ',
    '',
    '```sh',
    '# これはシェルのコメントで見出しではない',
    '## これも',
    '```',
    '',
    '### い',
    '',
    '#### よん（h4 は対象外）',
    '',
    '#hashtag は見出しではない',
    '',
    '## う',
    '',
  ].join('\n');

  test('レンダリング表示とソース表示で見出しの件数と順序が一致する', async () => {
    const rendered = await renderMarkdown('rendered', DOC);
    const source = await renderMarkdown('source', DOC);

    const sourceTexts = headingTexts(source).map((text) => text.replace(/^#+ /u, ''));

    expect(headingTexts(rendered)).toEqual(['題', 'あ', 'い', 'う']);
    expect(sourceTexts).toEqual(['題', 'あ', 'い', 'う']);
  });

  test('ソース表示で見出し行へ前後移動でき、目印は行の本文セルに付く', async () => {
    const { document, main } = await renderMarkdown('source', DOC);

    main._mmdOpenJump('heading');

    expect(count(document)).toBe('1/4');
    expect(current(document).classList.contains('line-content')).toBe(true);
    main._mmdJumpNextIfOpen();
    expect(count(document)).toBe('2/4');
  });

  test('レベルトグルはソース表示でも効く（レンダリング表示と同じ状態を使う）', async () => {
    const { document, main } = await renderMarkdown('source', DOC, {
      initialJumpLevels: ['h2'],
    });

    main._mmdOpenJump('heading');

    // h2 だけ ON なので「あ」「う」の 2 件。
    expect(count(document)).toBe('1/2');

    levelButton(document, 3).click();
    expect(count(document)).toBe('1/3');
  });

  test('段階読み込み中は「表示範囲内」ラベルを出す（差分と違い追記が実際に起きる）', async () => {
    const { document, main } = await renderMarkdown('source', DOC);
    main._mmdOpenJump('heading');

    main._mmdSetTruncated(true, 100, false);

    expect(count(document)).toBe('1/4 (Displayed range)');
  });

  test('追記された行の見出しも数に入る', async () => {
    const { document, main } = await renderMarkdown('source', '# 題\n');
    main._mmdOpenJump('heading');
    expect(count(document)).toBe('1/1');

    main.appendChunk('## あと\n', 'md');

    expect(count(document)).toBe('1/2');
  });

  test('Markdown 以外のソース表示では見出しを拾わない', async () => {
    const loaded = loadViewerMain({});
    loaded.main.setViewMode('source');
    await loaded.main.render('# これは Swift のコメント\nfunc f() {}\n', 'code', 'swift');

    expect(headingTexts(loaded)).toEqual([]);
  });

  test('差分表示では見出しを拾わない（table.code-table を名乗るが shape が diff）', async () => {
    const loaded = loadViewerMain({});
    loaded.main.setViewMode('source');
    loaded.main.setDiff(
      [
        'diff --git a/x.md b/x.md',
        '--- a/x.md',
        '+++ b/x.md',
        '@@ -1,2 +1,2 @@',
        '-# 題',
        '+# 新しい題',
        ' ',
        '',
      ].join('\n'),
    );
    await loaded.main.render(DOC, 'md');

    expect(headingTexts(loaded)).toEqual([]);
  });
});

// 使える種類が変わったらバーを閉じる（TASK-485.18）。
// 「使えるか」は Swift の ViewerCapabilities.canJump(to:) だけが決め、ここは
// 結果を受け取って閉じるかどうかだけを判断する。
describe('ジャンプ可否の同期', () => {
  test('開いている種類が使えなくなったらバーを閉じる', () => {
    const { document, main } = openJumpOn(HEADINGS);
    expect(isBarVisible(document)).toBe(true);

    main._mmdApplyJumpAvailability(['changeBlock']);

    expect(isBarVisible(document)).toBe(false);
  });

  test('開いている種類が引き続き使えるならバーは開いたまま', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdApplyJumpAvailability(['heading', 'changeBlock']);

    expect(isBarVisible(document)).toBe(true);
    expect(count(document)).toBe('1/4');
  });

  test('どれも使えなくなったらバーを閉じる', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdApplyJumpAvailability([]);

    expect(isBarVisible(document)).toBe(false);
  });

  test('閉じているときに届いても何も起きない（検索バーを巻き込まない）', () => {
    const { document, main } = loadViewerMain({});
    document.getElementById('diagram-wrap').innerHTML = HEADINGS;
    main._mmdOpenFind();

    main._mmdApplyJumpAvailability([]);

    expect(main._mmdFind.isOpen()).toBe(true);
  });

  test('閉じたあとはハイライトも候補の印も残らない', () => {
    const { document, main } = openJumpOn(HEADINGS);

    main._mmdApplyJumpAvailability([]);

    expect(document.querySelector('.mmd-jump-current')).toBeNull();
    expect(document.querySelectorAll('.mmd-jump-target')).toHaveLength(0);
  });
});
