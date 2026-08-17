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

// 差分表示の行番号ガター（旧側・新側）のセル。変更ブロックの目印はここへ付く。
const numberCells = (oldNumber, newNumber) =>
  '<td class="line-number diff-old">' +
  oldNumber +
  '</td><td class="line-number diff-new">' +
  newNumber +
  '</td>';

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

    main._mmdCloseJump();

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

    expect(count(loaded.document)).toBe('1/4');
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

  // 差分表示では目印に印を付けない。変更ブロックは .diff-add / .diff-del の地色で
  // 既に見えており、罫線を重ねても情報が増えないため（行数の多いブロックでは
  // 画面が枠だらけになる）。どこに居るかはスクロール位置とバーの n/N が伝える。
  test.each([
    ['インライン', INLINE_DIFF_DOM],
    ['左右分割', SPLIT_DIFF_DOM],
  ])('%s: ハイライトのクラスを付けない', (_name, dom) => {
    const { document } = openChangeBlockJumpOn(dom);

    expect(document.querySelectorAll('.mmd-jump-current').length).toBe(0);
    expect(document.querySelectorAll('.mmd-jump-target').length).toBe(0);
  });

  // 印が無いぶん、移動先はスクロール対象で確かめる。
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
