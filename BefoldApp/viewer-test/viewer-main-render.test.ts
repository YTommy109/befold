// describe 直下のヘルパーは、それを使うテストの真横に置いてあることに意味がある
// (どのテストのための組み立てかが読んで分かる)。モジュール先頭へ移すとテストと
// 離れて読みにくくなる一方、テスト本体は 1 回しか走らないので「毎回作り直す」
// コストの指摘は当たらない。このファイルではルールごと切る。
// oxlint-disable unicorn/consistent-function-scoping
// DOM に触れる層(描画・ズーム・検索・参照解決)のテスト。ファイル名は分割前の
// viewer-main.js に由来する。公開面の barrel 経由で、jsdom + viewer.html の DOM 上でロジックを
// 読み込み・初期化・単体呼び出しできることを確認する。
import { describe, expect, test } from '@jest/globals';
import type { DOMWindow } from 'jsdom';

import {
  loadViewerMain,
  captureBridgeMessages,
  dispatchTrustedClick,
  dispatchTrustedContextMenu,
} from './support/viewerMainHarness.js';
import type { LoadedViewer } from './support/viewerMainHarness.js';

// カラースキーム変更を発火できる matchMedia に差し替える。ハーネス既定のスタブは
// addEventListener が空実装のため、change を流すテストだけここで置き換える
// (_mmdInit() が matchMedia を呼ぶより前に差し替える必要がある)。
function installColorSchemeStub(window: DOMWindow) {
  const listeners: (() => void)[] = [];
  window.matchMedia = function (query: string) {
    return {
      media: query,
      matches: false,
      addEventListener: function (type: string, fn: () => void) {
        listeners.push(fn);
      },
      removeEventListener: function () {},
    } as unknown as MediaQueryList;
  };
  return {
    fireChange: () => {
      listeners.forEach((fn) => {
        fn();
      });
    },
  };
}

describe('_mmdFindRefresh の現在位置維持', () => {
  function openFindOn(text: string, query: string) {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap')!.textContent = text;
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input') as HTMLInputElement;
    input.value = query;
    input.dispatchEvent(new loaded.window.Event('input'));
    return loaded;
  }

  const count = (document: Document) => document.getElementById('mmd-find-count')!.textContent;

  test('再検索しても現在位置を維持する', () => {
    const { document, main } = openFindOn('x a x b x', 'x');
    main._mmdFind.next();
    expect(count(document)).toBe('2/3');

    main._mmdFindRefresh();

    expect(count(document)).toBe('2/3');
  });

  test('resetToFirst で先頭に戻す', () => {
    const { document, main } = openFindOn('x a x b x', 'x');
    main._mmdFind.next();

    main._mmdFindRefresh(true);

    expect(count(document)).toBe('1/3');
  });

  test('ヒット数が減ったら末尾にクランプする', () => {
    const { document, main } = openFindOn('x a x b x', 'x');
    main._mmdFind.next();
    main._mmdFind.next();
    expect(count(document)).toBe('3/3');

    // 再描画でヒットが 2 件に減った状況を作る
    document.getElementById('diagram-wrap')!.textContent = 'x a x';
    main._mmdFindRefresh();

    expect(count(document)).toBe('2/2');
  });

  test('ヒットが無くなったら 0/0 を表示する', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    document.getElementById('diagram-wrap')!.textContent = 'no hits here';
    main._mmdFindRefresh();

    expect(count(document)).toBe('0/0');
  });
});

describe('段階読み込み中の件数表示', () => {
  test('打ち切り中は「表示範囲内」を添える', () => {
    const { document, window, main } = loadViewerMain({
      findStrings: { withinDisplayedRange: '表示範囲内' },
      bannerStrings: { showing: '{count} 行' },
    });
    document.getElementById('diagram-wrap')!.textContent = 'x a x';
    main._mmdOpenFind();
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;
    input.value = 'x';
    input.dispatchEvent(new window.Event('input'));
    expect(document.getElementById('mmd-find-count')!.textContent).toBe('1/2');

    main._mmdSetTruncated(true, 100, false);

    expect(document.getElementById('mmd-find-count')!.textContent).toBe('1/2 (表示範囲内)');
  });
});

describe('モード切替の持ち越し', () => {
  const count = (document: Document) => document.getElementById('mmd-find-count')!.textContent;

  // csv を描画し、検索バーを開いて 2 件目を選択した状態にする
  async function renderAndSelectSecond() {
    const loaded = loadViewerMain({});
    await loaded.main.render('x,a\nx,b\n', 'csv', ',');
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input') as HTMLInputElement;
    input.value = 'x';
    input.dispatchEvent(new loaded.window.Event('input'));
    loaded.main._mmdFind.next();
    expect(count(loaded.document)).toBe('2/2');
    return loaded;
  }

  test('setViewMode 直後の描画では検索位置が先頭に戻る', async () => {
    const { document, main } = await renderAndSelectSecond();

    main.setViewMode('source');
    await main.render('x,a\nx,b\n', 'csv', ',');

    expect(count(document)).toBe('1/2');
  });

  test('持ち越しは1回の描画で消費され、次の描画には残らない', async () => {
    const { document, main } = await renderAndSelectSecond();

    main.setViewMode('source');
    await main.render('x,a\nx,b\n', 'csv', ',');
    main._mmdFind.next();
    expect(count(document)).toBe('2/2');

    // モードを切り替えずに再描画(ライブリロード相当)しても位置は維持される
    await main.render('x,a\nx,b\n', 'csv', ',');

    expect(count(document)).toBe('2/2');
  });

  test('同じモードを指定しても持ち越しは立たない', async () => {
    const { document, main } = await renderAndSelectSecond();

    main.setViewMode('rendered');
    await main.render('x,a\nx,b\n', 'csv', ',');

    expect(count(document)).toBe('2/2');
  });
});

describe('チャンク末尾の改行の持ち越し', () => {
  const lineNumbers = (document: Document) =>
    Array.from(document.querySelectorAll('#diagram-wrap table.code-table tr')).map(
      (tr) => tr.querySelector('.line-number')!.textContent,
    );

  test('改行で終わったチャンクの続きは新しい行になる', async () => {
    const { main, document } = loadViewerMain({});
    main.setLineNumbers(true);
    await main.render('a\nb\n', 'code', 'txt');

    main.appendChunk('c\n', 'code', 'txt');

    expect(lineNumbers(document)).toEqual(['1', '2', '3']);
  });

  test('改行で終わらなかったチャンクの続きは前の行に結合される', async () => {
    const { main, document } = loadViewerMain({});
    main.setLineNumbers(true);
    // 強制分割で行の途中で切れた状態
    await main.render('a\nb', 'code', 'txt');

    main.appendChunk('cd\n', 'code', 'txt');

    expect(lineNumbers(document)).toEqual(['1', '2']);
    const rows = document.querySelectorAll('#diagram-wrap table.code-table tr');
    expect(rows[1]!.querySelector('.line-content')!.textContent).toBe('bcd');
  });
});

describe('ダイアグラム個別ズーム', () => {
  const labelOf = (wrap: Element) => wrap.querySelector('.diagram-zoom-label')!.textContent;
  const wraps = (document: Document) =>
    Array.from(document.querySelectorAll<HTMLElement>('#diagram-wrap .diagram-zoom-wrap'));

  // mermaid 実行後の DOM(=.mermaid が 2 つある状態)を作り、ズームラッパーで包む。
  // 実際の描画は mermaid.min.js を読まないハーネスでは走らないため、包む対象だけ用意する。
  function wrapTwoDiagrams(loaded: LoadedViewer) {
    const diagramWrap = loaded.document.getElementById('diagram-wrap')!;
    diagramWrap.innerHTML =
      '<pre class="mermaid">graph TD; A-->B;</pre><pre class="mermaid">graph TD; C-->D;</pre>';
    loaded.main._mmdWrapDiagrams(diagramWrap);
    return wraps(loaded.document);
  }

  test('注入されたツールチップを適用する', () => {
    const loaded = loadViewerMain({
      uiStrings: { zoomOut: '縮小', zoomReset: 'クリックでリセット', zoomIn: '拡大' },
    });
    const [first] = wrapTwoDiagrams(loaded);

    expect(first!.querySelector<HTMLElement>('.diagram-zoom-out')!.title).toBe('縮小');
    expect(first!.querySelector<HTMLElement>('.diagram-zoom-label')!.title).toBe(
      'クリックでリセット',
    );
    expect(first!.querySelector<HTMLElement>('.diagram-zoom-in')!.title).toBe('拡大');
  });

  test('個別ズームは対象のダイアグラムだけに効く', () => {
    const loaded = loadViewerMain({});
    const [first, second] = wrapTwoDiagrams(loaded);

    // 先頭以外を操作して、インデックスごとに独立していることを確かめる
    second!.querySelector<HTMLElement>('.diagram-zoom-in')!.click();

    expect(labelOf(second!)).toBe(
      loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT + loaded.main.ZOOM_STEP),
    );
    expect(labelOf(first!)).toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));
    expect(loaded.main._mmdDiagramZoomValue(0)).toBe(loaded.main.ZOOM_DEFAULT);
    // 全体ズームは個別ズームでは動かない
    expect(loaded.main._mmdZoom.value()).toBe(loaded.main.ZOOM_DEFAULT);
  });

  test('個別ズームは再描画をまたいで維持される', () => {
    const loaded = loadViewerMain({});
    const [first] = wrapTwoDiagrams(loaded);
    first!.querySelector<HTMLElement>('.diagram-zoom-in')!.click();
    const zoomed = labelOf(first!);
    expect(zoomed).not.toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));

    // ライブリロード相当: DOM を作り直して同じ順番のダイアグラムを包み直す
    const [reFirst, reSecond] = wrapTwoDiagrams(loaded);

    expect(labelOf(reFirst!)).toBe(zoomed);
    expect(labelOf(reSecond!)).toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));
  });

  test('倍率ラベルのクリックで既定倍率に戻る', () => {
    const loaded = loadViewerMain({});
    const [first] = wrapTwoDiagrams(loaded);
    first!.querySelector<HTMLElement>('.diagram-zoom-in')!.click();

    first!.querySelector<HTMLElement>('.diagram-zoom-label')!.click();

    expect(labelOf(first!)).toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));
    expect(loaded.main._mmdDiagramZoomValue(0)).toBe(loaded.main.ZOOM_DEFAULT);
  });
});

describe('カラースキーム変更時の再描画', () => {
  test('直近に描画した内容・型・区切り文字で描き直す', async () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();
    await loaded.main.render('a;b\n', 'csv', ';');
    // 描画結果を消し、再描画で戻ってくることを観測できる状態にする
    loaded.document.getElementById('diagram-wrap')!.innerHTML = '';

    colorScheme.fireChange();

    const cells = Array.from(loaded.document.querySelectorAll('#diagram-wrap th')).map(
      (th) => th.textContent,
    );
    // 区切り文字(';')を保持していなければ 1 セルに固まる
    expect(cells).toEqual(['a', 'b']);
  });

  test('追記済みのチャンクも含めて描き直す', async () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();
    await loaded.main.render('a\n', 'csv', ',');
    loaded.main.appendChunk('b\n', 'csv', ',');
    loaded.document.getElementById('diagram-wrap')!.innerHTML = '';

    colorScheme.fireChange();

    const rows = Array.from(loaded.document.querySelectorAll('#diagram-wrap tr')).map(
      (tr) => tr.textContent,
    );
    expect(rows).toEqual(['a', 'b']);
  });

  test('まだ何も描画していなければ再描画しない', () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();

    colorScheme.fireChange();

    expect(loaded.document.getElementById('diagram-wrap')!.innerHTML).toBe('');
  });
});

describe('行番号表示の反映', () => {
  // 行単位テーブルは行番号の有無に関わらず常に使うため、行番号セルの有無で判定する。
  const hasLineNumbers = (document: Document) =>
    document.querySelector('#diagram-wrap td.line-number') !== null;

  test('無効にすると次の描画で行番号が付かない', async () => {
    const { main, document } = loadViewerMain({});
    main.setLineNumbers(true);
    await main.render('a\nb\n', 'code', 'txt');
    expect(hasLineNumbers(document)).toBe(true);

    main.setLineNumbers(false);
    await main.render('a\nb\n', 'code', 'txt');

    expect(hasLineNumbers(document)).toBe(false);
  });

  test('ソース表示にも行番号設定が効く', async () => {
    const { main, document } = loadViewerMain({});
    main.setLineNumbers(true);
    main.setViewMode('source');

    await main.render('a,b\n', 'csv', ',');

    expect(hasLineNumbers(document)).toBe(true);
  });
});

describe('インデントガイド(end-to-end)', () => {
  test('インデントされたコード行に --indent-cols / --indent-depth が乗る', async () => {
    const { main, document } = loadViewerMain({});
    // 行番号なしでも(統一した行単位構造なので)ガイド変数が付く。
    main.setLineNumbers(false);
    await main.render('function f() {\n    return 1;\n}', 'code', 'js');

    const cells = document.querySelectorAll('#diagram-wrap .line-content');
    // 2 行目(4 スペースインデント)のセルにガイド変数が乗っている。
    const indented = Array.from(cells).find(
      (c) => c.getAttribute('style') && c.getAttribute('style')!.includes('--indent-cols:4'),
    );
    expect(indented).toBeTruthy();
    expect(indented!.getAttribute('style')).toContain('--indent-depth:1');
    // 行番号セルは付かない。
    expect(document.querySelector('#diagram-wrap td.line-number')).toBeNull();
  });
});

describe('スクロール位置の復元', () => {
  test('Swift が注入した位置を次の描画で復元する', async () => {
    const { main } = loadViewerMain({});
    main._mmdSetRestoreScroll(120);

    await main.render('a\nb\n', 'code', 'txt');

    expect(main._mmdScrollTarget()!.scrollTop).toBe(120);
  });

  test('注入位置は 1 回の描画で消費され、次の描画では現在位置を保つ', async () => {
    const { main } = loadViewerMain({});
    main._mmdSetRestoreScroll(120);
    await main.render('a\nb\n', 'code', 'txt');
    // ソース表示のスクロール実体は描画のたびに作り直されるため都度取り直す
    main._mmdScrollTarget()!.scrollTop = 40;

    // 内部再描画(カラースキーム変更相当)では注入位置は残っていない
    await main.render('a\nb\n', 'code', 'txt');

    expect(main._mmdScrollTarget()!.scrollTop).toBe(40);
  });
});

describe('mermaid のパースエラー表示', () => {
  test('mmd 表示ではエラーパネルを出して図の領域を隠す', () => {
    const { main, document } = loadViewerMain({});
    // mermaid.min.js は jsdom では読み込めず await が解決しないため、型の記録が
    // 終わっている同期部分だけを使う(render の型ディスパッチのテストと同じ理由)。
    void main.render('graph TD; A-->B;', 'mmd');

    main._mmdMermaidParseError(new Error('boom'));

    expect(document.getElementById('mmd-error')!.style.display).toBe('block');
    expect(document.getElementById('mmd-error')!.textContent).toBe('boom');
    expect(document.getElementById('diagram-wrap')!.style.display).toBe('none');
  });

  test('Markdown 内の図では図の領域を隠さない', async () => {
    const { main, document } = loadViewerMain({});
    // markdown-it 未ロードのハーネスでは本文は縮退するが、型は md として記録される
    await main.render('# title', 'md');

    main._mmdMermaidParseError(new Error('boom'));

    expect(document.getElementById('mmd-error')!.style.display).toBe('block');
    expect(document.getElementById('diagram-wrap')!.style.display).toBe('block');
  });
});

describe('パス参照の表示時解決', () => {
  // #diagram-wrap に任意の HTML を流し込み、収集対象を組み立てる。
  // <a> は markdown-it 未ロードのハーネスでは render() から作れないため直接置く。
  function setWrapHtml(loaded: LoadedViewer, html: string) {
    loaded.document.getElementById('diagram-wrap')!.innerHTML = html;
  }

  function classesOf(loaded: LoadedViewer, selector: string) {
    return Array.from(loaded.document.querySelector(selector)!.classList).toSorted();
  }

  function click(loaded: LoadedViewer, selector: string, init?: MouseEventInit) {
    dispatchTrustedClick(loaded.window, loaded.document.querySelector(selector)!, init);
  }

  test('描画後にローカルパス候補を一意化して resolveReferences を送る', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences']);

    await loaded.main.render('src/a.swift\nsrc/a.swift\nsrc/b.swift\n', 'code', 'txt');

    expect(received.length).toBe(1);
    expect((received[0]!.payload as { paths: string[] }).paths.toSorted()).toEqual([
      'src/a.swift',
      'src/b.swift',
    ]);
    // 応答が返るまでは全候補が中立表示になる
    const refs = loaded.document.querySelectorAll<HTMLElement>('#diagram-wrap .befold-path-ref');
    expect(refs.length).toBe(3);
    refs.forEach((ref) => {
      expect(ref.classList.contains('befold-link-pending')).toBe(true);
    });
  });

  test('解決できたものだけをリンク化し、絶対パスを DOM に残す', async () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    await loaded.main.render('src/a.swift\nsrc/missing.swift\n', 'code', 'txt');

    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    const refs = loaded.document.querySelectorAll<HTMLElement>('#diagram-wrap .befold-path-ref');
    expect(Array.from(refs[0]!.classList).toSorted()).toEqual(['befold-link', 'befold-path-ref']);
    expect(refs[0]!.dataset.resolved).toBe('/repo/src/a.swift');
    expect(Array.from(refs[1]!.classList).toSorted()).toEqual([
      'befold-link-dead',
      'befold-path-ref',
    ]);
    expect(refs[1]!.dataset.resolved).toBeUndefined();
  });

  // ハイライトで span に割られたパスは片ごとに注釈される。解決要求は一意化された
  // 1 パスで送られ、どの片をクリックしてもパス全体が開く(TASK-455)。
  test('span に割られたパス参照はどの片からでも開ける', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    await loaded.main.render('see ./notes.md for details\n', 'code', 'swift');

    expect((received[0]!.payload as { paths: string[] }).paths).toEqual(['./notes.md']);
    loaded.main._mmdApplyResolvedReferences({ './notes.md': '/repo/notes.md' });

    const refs = Array.from(loaded.document.querySelectorAll('#diagram-wrap .befold-path-ref'));
    expect(refs.length).toBeGreaterThan(1);
    refs.forEach((ref) => {
      expect(Array.from(ref.classList).toSorted()).toEqual(['befold-link', 'befold-path-ref']);
      dispatchTrustedClick(loaded.window, ref);
    });

    expect(
      received
        .filter((m) => m.name === 'referenceActivated')
        .map((m) => (m.payload as { href: string }).href),
    ).toEqual(refs.map(() => './notes.md'));
  });

  test('解決できなかった <a> は href を失いクリックできなくなる', () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    setWrapHtml(loaded, '<a id="dead" href="./missing.md">missing</a>');

    loaded.main._mmdResolveReferences();
    loaded.main._mmdApplyResolvedReferences({});

    expect(loaded.document.getElementById('dead')!.hasAttribute('href')).toBe(false);
    click(loaded, '#dead');
    expect(received.filter((m) => m.name === 'referenceActivated')).toEqual([]);
  });

  test('解決応答が返る前のクリックでは referenceActivated を送らない', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');

    click(loaded, '#diagram-wrap .befold-path-ref');

    expect(received.filter((m) => m.name === 'referenceActivated')).toEqual([]);
  });

  test('解決済みのパス参照はクリックで referenceActivated を送る', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    click(loaded, '#diagram-wrap .befold-path-ref');

    expect(received.filter((m) => m.name === 'referenceActivated').map((m) => m.payload)).toEqual([
      { href: 'src/a.swift', metaKey: false, shiftKey: false },
    ]);
  });

  test('修飾キーの押下状態をそのまま referenceActivated に載せる', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    click(loaded, '#diagram-wrap .befold-path-ref', { metaKey: true });
    click(loaded, '#diagram-wrap .befold-path-ref', { metaKey: true, shiftKey: true });

    expect(received.filter((m) => m.name === 'referenceActivated').map((m) => m.payload)).toEqual([
      { href: 'src/a.swift', metaKey: true, shiftKey: false },
      { href: 'src/a.swift', metaKey: true, shiftKey: true },
    ]);
  });

  test('ctrlKey が押された click では referenceActivated を送らない(コンテキストメニュー扱い)', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    click(loaded, '#diagram-wrap .befold-path-ref', { ctrlKey: true });

    expect(received.filter((m) => m.name === 'referenceActivated')).toEqual([]);
  });

  test('外部 URL と # アンカーは中立化せず従来どおり動く', () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceActivated',
    ]);
    setWrapHtml(
      loaded,
      '<a id="ext" href="https://example.com/a.md">ext</a>' +
        '<a id="mail" href="mailto:a@example.com">mail</a>' +
        '<a id="anchor" href="#sec">anchor</a><h2 id="sec">sec</h2>',
    );

    loaded.main._mmdResolveReferences();

    expect(received.filter((m) => m.name === 'resolveReferences')).toEqual([]);
    ['#ext', '#mail', '#anchor'].forEach((sel) => {
      expect(classesOf(loaded, sel)).toEqual([]);
    });
    click(loaded, '#ext');
    expect(received.filter((m) => m.name === 'referenceActivated').map((m) => m.payload)).toEqual([
      { href: 'https://example.com/a.md', metaKey: false, shiftKey: false },
    ]);
  });

  test('コロン付きの行番号参照はスキームと誤認せず解決要求に含める', () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences']);
    setWrapHtml(loaded, '<a id="line" href="viewer-main.js:12">line</a>');

    loaded.main._mmdResolveReferences();

    expect((received[0]!.payload as { paths: string[] }).paths).toEqual(['viewer-main.js:12']);
  });

  test('メッセージハンドラ未登録のホストでは中立化したまま固まらない', () => {
    const loaded = loadViewerMain({});
    // webkit.messageHandlers を用意しない = Swift 側にハンドラが無く応答も来ない
    setWrapHtml(loaded, '<a id="local" href="./doc.md">doc</a>');

    loaded.main._mmdResolveReferences();

    expect(classesOf(loaded, '#local')).toEqual([]);
  });

  test('追加チャンクでは未分類のパス参照だけを送り直す', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences']);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    loaded.main.appendChunk('src/b.swift\n', 'code', 'txt');

    expect(received.map((m) => (m.payload as { paths: string[] }).paths)).toEqual([
      ['src/a.swift'],
      ['src/b.swift'],
    ]);
    const refs = loaded.document.querySelectorAll<HTMLElement>('#diagram-wrap .befold-path-ref');
    expect(refs[0]!.classList.contains('befold-link')).toBe(true);
    expect(refs[1]!.classList.contains('befold-link-pending')).toBe(true);
  });

  test('未応答バッチが無い状態で応答が届いても何も起きない', async () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });
    const ref = loaded.document.querySelector<HTMLElement>('#diagram-wrap .befold-path-ref')!;

    // キューが空の状態での 2 度目の応答(Swift 側の重複応答を想定)
    loaded.main._mmdApplyResolvedReferences({});

    expect(Array.from(ref.classList).toSorted()).toEqual(['befold-link', 'befold-path-ref']);
    expect(ref.dataset.resolved).toBe('/repo/src/a.swift');
  });

  test('再描画中に届いた古い応答が新しい要求の対象を巻き込まない', async () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    await loaded.main.render('src/old.swift\n', 'code', 'txt');

    // 応答が返る前にファイルが切り替わり、新しい要求が出る
    await loaded.main.render('src/new.swift\n', 'code', 'txt');
    // 旧ドキュメント向けの応答が遅れて届く
    loaded.main._mmdApplyResolvedReferences({ 'src/old.swift': '/repo/src/old.swift' });

    const ref = loaded.document.querySelector<HTMLElement>('#diagram-wrap .befold-path-ref')!;
    expect(ref.textContent).toBe('src/new.swift');
    expect(ref.classList.contains('befold-link-pending')).toBe(true);

    loaded.main._mmdApplyResolvedReferences({ 'src/new.swift': '/repo/src/new.swift' });

    expect(ref.dataset.resolved).toBe('/repo/src/new.swift');
  });

  test('Object.prototype 由来の名前を書いた参照は解決済み扱いにならない', () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    setWrapHtml(
      loaded,
      '<a id="ctor" href="constructor">ctor</a>' +
        '<a id="hop" href="hasOwnProperty">hop</a>' +
        '<a id="tostr" href="toString">tostr</a>',
    );

    loaded.main._mmdResolveReferences();
    // Swift が 1 件も解決できなかった応答
    loaded.main._mmdApplyResolvedReferences({});

    ['#ctor', '#hop', '#tostr'].forEach((sel) => {
      const el = loaded.document.querySelector<HTMLElement>(sel)!;
      expect(el.classList.contains('befold-link')).toBe(false);
      expect(el.classList.contains('befold-link-dead')).toBe(true);
      expect(el.dataset.resolved).toBeUndefined();
      expect(el.hasAttribute('href')).toBe(false);
    });
  });

  test('__proto__ という名前の参照も解決要求に含める', () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences']);
    setWrapHtml(
      loaded,
      '<a id="proto" href="__proto__">proto</a><a id="ok" href="./doc.md">doc</a>',
    );

    loaded.main._mmdResolveReferences();

    expect((received[0]!.payload as { paths: string[] }).paths.toSorted()).toEqual([
      './doc.md',
      '__proto__',
    ]);
  });

  test('解決先の絶対パスを title に出し、解決失敗時は元の title を残さない', () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    // 生 HTML で表示テキストと無関係なパスへ誘導し、title で偽装した参照
    setWrapHtml(
      loaded,
      '<span id="fake" class="befold-path-ref" data-path="./secret.md" title="README.md">README.md</span>' +
        '<a id="dead" href="./missing.md" title="安全なリンク">missing</a>',
    );

    loaded.main._mmdResolveReferences();
    loaded.main._mmdApplyResolvedReferences({ './secret.md': '/repo/secret.md' });

    expect(loaded.document.getElementById('fake')!.getAttribute('title')).toBe('/repo/secret.md');
    expect(loaded.document.getElementById('dead')!.hasAttribute('title')).toBe(false);
  });

  test('リンク上の contextmenu は既定メニューを抑止して referenceContextMenu を送る', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, [
      'resolveReferences',
      'referenceContextMenu',
    ]);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    const event = dispatchTrustedContextMenu(
      loaded.window,
      loaded.document.querySelector('#diagram-wrap .befold-path-ref')!,
    );

    expect(event.defaultPrevented).toBe(true);
    expect(received.filter((m) => m.name === 'referenceContextMenu').map((m) => m.payload)).toEqual(
      [{ href: 'src/a.swift' }],
    );
  });

  test('リンク以外の contextmenu は既定メニューのまま何も送らない', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['referenceContextMenu']);
    await loaded.main.render('ただの本文\n', 'code', 'txt');

    const event = dispatchTrustedContextMenu(
      loaded.window,
      loaded.document.getElementById('diagram-wrap')!,
    );

    expect(event.defaultPrevented).toBe(false);
    expect(received).toEqual([]);
  });
});

describe('Markdown のチャンク追記(Issue #307)', () => {
  const wrap = (document: Document) => document.getElementById('diagram-wrap')!;

  test('追記したチャンクが末尾にレンダリングされる', async () => {
    const { main, document } = loadViewerMain({});
    await main.render('# first\n\n', 'md');

    main.appendChunk('## second\n\n', 'md');

    expect(wrap(document).querySelector('h1')!.textContent).toBe('first');
    expect(wrap(document).querySelector('h2')!.textContent).toBe('second');
  });

  test('追記しても先頭チャンクの DOM を作り直さない', async () => {
    const { main, document } = loadViewerMain({});
    await main.render('# first\n\n', 'md');
    const firstHeading = wrap(document).querySelector('h1');

    main.appendChunk('## second\n\n', 'md');

    // 全文を再レンダリングしていれば h1 は別ノードに置き換わる。
    expect(wrap(document).querySelector('h1')).toBe(firstHeading);
  });

  test('追記チャンクも DOMPurify でサニタイズされる', async () => {
    const { main, document } = loadViewerMain({});
    await main.render('# first\n\n', 'md');

    main.appendChunk('<img src=x onerror="alert(1)">\n\n', 'md');

    const img = wrap(document).querySelector('img')!;
    expect(img).not.toBeNull();
    expect(img.getAttribute('onerror')).toBeNull();
  });

  test('追記した内容も検索対象の本文に含まれる', async () => {
    const { main, document } = loadViewerMain({});
    await main.render('# first\n\n', 'md');

    main.appendChunk('needle text\n\n', 'md');

    expect(wrap(document).textContent).toContain('needle text');
  });
});
