// describe 直下のヘルパーは、それを使うテストの真横に置いてあることに意味がある
// (どのテストのための組み立てかが読んで分かる)。モジュール先頭へ移すとテストと
// 離れて読みにくくなる一方、テスト本体は 1 回しか走らないので「毎回作り直す」
// コストの指摘は当たらない。このファイルではルールごと切る。
// oxlint-disable unicorn/consistent-function-scoping
// DOM に触れる層(描画・ズーム・検索・参照解決)のテスト。ファイル名は分割前の
// viewer-main.js に由来する。公開面の barrel 経由で、jsdom + viewer.html の DOM 上でロジックを
// 読み込み・初期化・単体呼び出しできることを確認する。
import { describe, expect, jest, test } from '@jest/globals';

import { loadViewerMain, captureBridgeMessages } from './support/viewerMainHarness.js';

// カラースキーム変更を発火できる matchMedia に差し替える。ハーネス既定のスタブは
// addEventListener が空実装のため、change を流すテストだけここで置き換える
// (_mmdInit() が matchMedia を呼ぶより前に差し替える必要がある)。
describe('エクスポート境界', () => {
  test('読み込むだけでは初期化の副作用が起きない', () => {
    const { document, main } = loadViewerMain({ init: false });

    expect(typeof main.render).toBe('function');
    expect(typeof main._mmdInit).toBe('function');
    // _mmdInitFind() が反映するはずの状態が未適用であること
    expect((document.getElementById('mmd-find-input') as HTMLInputElement).placeholder).toBe(
      'Search',
    );
  });

  test('_mmdInit() を明示的に呼ぶと初期化が走る', () => {
    const { document } = loadViewerMain({
      findStrings: { placeholder: 'Find' },
    });

    expect((document.getElementById('mmd-find-input') as HTMLInputElement).placeholder).toBe(
      'Find',
    );
  });
});

describe('_mmdInitZoom', () => {
  test('Swift が注入した倍率を採用する', () => {
    const { window, main } = loadViewerMain({ initialZoom: 1.5 });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    // 注入値(1.5)が採用されていれば、既定倍率へのリセットは変化として通知される
    main._mmdZoomReset();

    expect(received.length).toBe(1);
    expect((received[0]!.payload as { zoom: number }).zoom).toBe(main.ZOOM_DEFAULT);
  });

  test('注入値と同じ倍率では zoomChanged を通知しない', () => {
    const { window, main } = loadViewerMain({ init: false, initialZoom: 1.5 });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    main._mmdInit();

    expect(received).toEqual([]);
  });

  test('倍率が変わったときだけ zoomChanged を通知する', () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    main._mmdZoomIn();

    expect(received.length).toBe(1);
    expect(received[0]!.name).toBe('zoomChanged');
    expect((received[0]!.payload as { zoom: number }).zoom).toBeGreaterThan(1);
  });

  // 倍率も per-file に保存されるため、スクロール位置と同じく「その倍率が属する文書」を
  // 発火時に申告する。Swift 側の現在 URL を参照していた頃は、切替直後に配達された
  // 通知が切替先のキーを汚した(TASK-391)。
  test('zoomChanged に採用済みの文書パスを載せる', async () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBe('/mock/a.md');
  });

  test('文書が定まらない間(描画前)の zoomChanged は path に null を送る', () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBeNull();
  });

  test('rename 後の zoomChanged は新しいパスを載せる', async () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    main._mmdRenameDocPath('/mock/a.md', '/mock/b.md');
    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBe('/mock/b.md');
  });

  // 以下 4 件は、かつて scrollPositionChanged 側で文書パスの採用規則を見ていたもの。
  // スクロール位置の継続通知は TASK-574.3 で撤去した（位置は切替直前の pull 1 本に
  // 揃えた）が、採用規則そのものは倍率の通知が同じ _mmdDocPath を使うので残っている。
  // 観測点を zoomChanged へ移して規則の担保を保つ。
  test('予告は render まで採用されない(採用前の通知は現在の文書のパスのまま)', async () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    // 切替先の予告だけがあり render がまだ実行されていない間、DOM は旧文書のまま。
    // ここで発火した通知が新パスを名乗ると、旧文書の値が切替先のキーへ保存される。
    main._mmdSetRenderDocPath('/mock/b.md');
    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBe('/mock/a.md');
  });

  test('予告なしの内部再描画では採用済みのパスを保つ', async () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    // カラースキーム変更相当(予告なしの render)でパスが消えてはならない
    await main.render('a\nb\n', 'code', 'txt');
    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBe('/mock/a.md');
  });

  test('_mmdRenameDocPath は現在のパスが一致しないとき何もしない', async () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    // 別文書へ切替中の rename 等。誤った付け替えより旧キーへの短時間の保存が安全。
    main._mmdRenameDocPath('/mock/x.md', '/mock/y.md');
    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBe('/mock/a.md');
  });

  test('_mmdRenameDocPath は未採用の予告パスも差し替える', async () => {
    const { window, main } = loadViewerMain({ initialZoom: 1 });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    // 旧名の render が実行待ちのまま rename された場合、採用後のパスも新名になる
    main._mmdSetRenderDocPath('/mock/a.md');
    main._mmdRenameDocPath('/mock/a.md', '/mock/b.md');
    await main.render('a\nb\n', 'code', 'txt');
    main._mmdZoomIn();

    expect((received.at(-1)!.payload as { path: string | null }).path).toBe('/mock/b.md');
  });
});

describe('_mmdScrollTarget', () => {
  test('ソース表示でなければ .viewer を返す', () => {
    const { document, main } = loadViewerMain({});

    expect(main._mmdScrollTarget()).toBe(document.querySelector('.viewer'));
  });

  test('ソース表示では pre code を返す', () => {
    const { document, main } = loadViewerMain({});
    const wrap = document.getElementById('diagram-wrap')!;
    wrap.classList.add('code-body');
    wrap.innerHTML = '<pre><code>x</code></pre>';

    expect(main._mmdScrollTarget()).toBe(
      document.querySelector('#diagram-wrap.code-body pre code'),
    );
  });
});

describe('_mmdSetTruncated', () => {
  const bannerStrings = {
    showing: '{count} 行を表示中',
    loadMore: 'さらに読み込む',
    loadError: '残りの読み込みに失敗しました',
  };

  test('打ち切り解除でバナーを隠す', () => {
    const { document, main } = loadViewerMain({ bannerStrings });

    main._mmdSetTruncated(false, undefined, false);

    expect(document.getElementById('mmd-truncated-banner')!.style.display).toBe('none');
  });

  test('行数付きでバナーと続き読み込みボタンを表示する', () => {
    const { document, main } = loadViewerMain({ bannerStrings });

    main._mmdSetTruncated(true, 1000, false);

    expect(document.getElementById('mmd-truncated-banner')!.style.display).toBe('flex');
    expect(document.getElementById('mmd-truncated-text')!.textContent).toBe('1000 行を表示中');
    const btn = document.getElementById('mmd-load-more-btn')!;
    expect(btn.style.display).toBe('inline-block');
    expect(btn.textContent).toBe('さらに読み込む');
  });

  test('loadMore 無効ホストではボタンを出さない', () => {
    const { document, main } = loadViewerMain({
      bannerStrings,
      hostFeatures: { loadMore: false },
    });

    main._mmdSetTruncated(true, 1000, false);

    expect(document.getElementById('mmd-load-more-btn')!.style.display).toBe('none');
  });

  test('読み込み失敗ではエラー文言に切り替えボタンを隠す', () => {
    const { document, main } = loadViewerMain({ bannerStrings });

    main._mmdSetTruncated(true, 1000, true);

    expect(document.getElementById('mmd-truncated-text')!.textContent).toBe(
      '残りの読み込みに失敗しました',
    );
    expect(document.getElementById('mmd-load-more-btn')!.style.display).toBe('none');
  });
});

describe('_mmdLoadMore', () => {
  test('loadMoreLines を通知する', () => {
    const { window, main } = loadViewerMain({});
    const received = captureBridgeMessages(window, ['loadMoreLines']);

    main._mmdLoadMore();

    expect(received.length).toBe(1);
    expect(received[0]!.name).toBe('loadMoreLines');
  });

  test('loadMore 無効ホストでは通知しない', () => {
    const { window, main } = loadViewerMain({ hostFeatures: { loadMore: false } });
    const received = captureBridgeMessages(window, ['loadMoreLines']);

    main._mmdLoadMore();

    expect(received).toEqual([]);
  });
});

describe('_mmdInitFind', () => {
  test('保存済みトグル状態を反映する', () => {
    const { document } = loadViewerMain({
      initialFindOptions: { caseSensitive: true, wholeWord: false, useRegex: true },
    });

    expect(document.getElementById('mmd-find-case')!.classList.contains('active')).toBe(true);
    expect(document.getElementById('mmd-find-word')!.classList.contains('active')).toBe(false);
    expect(document.getElementById('mmd-find-regex')!.classList.contains('active')).toBe(true);
  });

  test('ローカライズ済み文字列を反映する', () => {
    const { document } = loadViewerMain({
      findStrings: {
        placeholder: 'Find',
        previous: 'Previous',
        next: 'Next',
        matchCase: 'Match Case',
        matchWholeWord: 'Match Whole Word',
        useRegularExpression: 'Use Regular Expression',
        close: 'Close',
      },
    });

    expect((document.getElementById('mmd-find-input') as HTMLInputElement).placeholder).toBe(
      'Find',
    );
    expect(document.getElementById('mmd-find-prev')!.title).toBe('Previous');
    expect(document.getElementById('mmd-find-next')!.title).toBe('Next');
    expect(document.getElementById('mmd-find-case')!.title).toBe('Match Case');
    expect(document.getElementById('mmd-find-word')!.title).toBe('Match Whole Word');
    expect(document.getElementById('mmd-find-regex')!.title).toBe('Use Regular Expression');
    expect(document.getElementById('mmd-find-close')!.title).toBe('Close');
  });
});

describe('検索バーの配線', () => {
  test('トグルのクリックで状態が反転し findOptionsChanged を通知する', () => {
    const { window, document, main } = loadViewerMain({
      initialFindOptions: { caseSensitive: false, wholeWord: false, useRegex: false },
    });
    const received = captureBridgeMessages(window, ['findOptionsChanged']);

    document.getElementById('mmd-find-case')!.click();

    expect(document.getElementById('mmd-find-case')!.classList.contains('active')).toBe(true);
    expect(received.length).toBe(1);
    expect(received[0]!.payload).toEqual({
      caseSensitive: true,
      wholeWord: false,
      useRegex: false,
    });
    expect(main._mmdFind.isOpen()).toBe(false);
  });

  test('閉じるボタンで検索バーが閉じる', () => {
    const { document, main } = loadViewerMain({});

    main._mmdOpenFind();
    expect(main._mmdFind.isOpen()).toBe(true);
    expect(document.getElementById('mmd-find-panel')!.style.display).toBe('flex');

    document.getElementById('mmd-find-close')!.click();

    expect(main._mmdFind.isOpen()).toBe(false);
    expect(document.getElementById('mmd-find-panel')!.style.display).toBe('none');
  });
});

describe('render の型ディスパッチ', () => {
  // #diagram-wrap に付いた型別クラスだけを取り出す
  function bodyClasses(document: Document) {
    return Array.from(document.getElementById('diagram-wrap')!.classList)
      .filter((c) => c.endsWith('-body'))
      .toSorted();
  }

  test('mmd は mermaid 用の pre を組み立てる', () => {
    const { document, main } = loadViewerMain({});

    // mermaid.min.js は jsdom では読み込めず _mmdEnsureMermaidLoaded() の await が
    // 解決しないため、DOM 構築が終わっている同期部分だけを検証する。
    void main.render('graph TD;\nA-->B', 'mmd');

    const wrap = document.getElementById('diagram-wrap')!;
    expect(wrap.querySelector('pre.mermaid')!.textContent).toBe('graph TD;\nA-->B');
    expect(bodyClasses(document)).toEqual([]);
  });

  test('mmd はダイアグラム定義を HTML エスケープする', () => {
    const { document, main } = loadViewerMain({});

    void main.render('A["<img src=x onerror=alert(1)>"]', 'mmd');

    const wrap = document.getElementById('diagram-wrap')!;
    expect(wrap.querySelector('img')).toBeNull();
    expect(wrap.querySelector('pre.mermaid')!.textContent).toContain(
      '<img src=x onerror=alert(1)>',
    );
  });

  test('svg はズームラッパー付きの img を組み立てる', async () => {
    const { window, document, main } = loadViewerMain({});

    await main.render('<svg><text>日本語</text></svg>', 'svg');

    const img = document.querySelector<HTMLImageElement>(
      '#diagram-wrap .diagram-zoom-wrap .diagram-zoom-inner img',
    )!;
    expect(img).not.toBeNull();
    expect(img.alt).toBe('SVG');
    expect(img.src).toBe(window.svgDataURI('<svg><text>日本語</text></svg>'));
    expect(
      document.querySelector<HTMLElement>('#diagram-wrap .diagram-zoom-wrap')!.dataset.diagramIndex,
    ).toBe('0');
    // mermaid と同じズーム操作 UI が付く
    expect(document.querySelector('#diagram-wrap .diagram-zoom-controls')).not.toBeNull();
  });

  test('html は sandbox 付き iframe に srcdoc で流し込む', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('<p>hi</p>', 'html');

    const iframe = document.querySelector<HTMLIFrameElement>('#diagram-wrap iframe')!;
    expect(iframe.getAttribute('sandbox')).toBe('allow-same-origin');
    expect(iframe.srcdoc).toBe('<p>hi</p>');
    expect(bodyClasses(document)).toEqual(['html-body']);
  });

  test('csv はテーブルを組み立てる', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('a,b\n1,2\n', 'csv', ',');

    const headers = Array.from(document.querySelectorAll('#diagram-wrap table th')).map(
      (th) => th.textContent,
    );
    const cells = Array.from(document.querySelectorAll('#diagram-wrap table td')).map(
      (td) => td.textContent,
    );
    expect(headers).toContain('a');
    expect(cells).toContain('2');
    expect(bodyClasses(document)).toEqual(['csv-body', 'markdown-body']);
  });

  test('image は MIME 付きの data URI を img に設定する', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('AAAA', 'image', 'image/webp');

    const img = document.querySelector<HTMLImageElement>('#diagram-wrap img')!;
    expect(img.getAttribute('src')).toBe('data:image/webp;base64,AAAA');
    expect(img.alt).toBe('Image');
    expect(bodyClasses(document)).toEqual(['image-body']);
  });

  test('code はコード表示用のクラスと内容を設定する', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('let x = 1', 'code', 'swift');

    expect(document.querySelector('#diagram-wrap pre code')!.textContent).toBe('let x = 1');
    expect(bodyClasses(document)).toEqual(['code-body']);
  });

  // ベンダーはバンドル同梱(viewer-src/vendor.js)になったため「markdown-it 未ロード」
  // という状態は存在しない(TASK-432.5)。以前はこの経路の縮退表示を固定していた。
  test('md は markdown-it でレンダリングする', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('# Title', 'md');

    expect(document.querySelector('#diagram-wrap h1')!.textContent).toBe('Title');
    expect(bodyClasses(document)).toEqual(['markdown-body']);
  });

  test('型を切り替えると前回の型別クラスが残らない', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('AAAA', 'image', 'image/png');
    expect(bodyClasses(document)).toEqual(['image-body']);

    await main.render('a,b\n', 'csv', ',');

    expect(bodyClasses(document)).toEqual(['csv-body', 'markdown-body']);
  });

  test('ソース表示へ切り替えると前回の型別クラスが残らない', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('a,b\n', 'csv', ',');
    expect(bodyClasses(document)).toEqual(['csv-body', 'markdown-body']);

    main.setViewMode('source');
    await main.render('a,b\n', 'csv', ',');

    expect(bodyClasses(document)).toEqual(['code-body']);
  });

  test('描画のたびにエラーパネルを消す', async () => {
    const { document, main } = loadViewerMain({});
    const panel = document.getElementById('mmd-error')!;
    panel.textContent = 'previous error';
    panel.style.display = 'block';

    await main.render('a,b\n', 'csv', ',');

    expect(panel.style.display).toBe('none');
    expect(panel.textContent).toBe('');
  });
});

describe('検索ナビゲーション', () => {
  // 検索対象の DOM を用意し、検索バーを開いて query を入力した状態にする。
  // 入力は実際の input イベント経由で流し、配線ごと検証する。
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
  const currentMark = (document: Document) => document.querySelector('mark.mmd-find-match-current');

  test('検索するとヒット件数と先頭のハイライトが出る', () => {
    const { document } = openFindOn('x a x b x', 'x');

    expect(count(document)).toBe('1/3');
    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(3);
    expect(currentMark(document)).toBe(document.querySelectorAll('mark.mmd-find-match')[0]);
  });

  test('CSV の複数セルを再検索しても Range は検索ごとに1つだけ生成する', async () => {
    const { document, window, main } = loadViewerMain({});
    await main.render('first,second\nalpha alpha,alpine\nbeta,gamma', 'csv', ',');
    const wrap = document.getElementById('diagram-wrap')!;
    const originalHtml = wrap.innerHTML;
    main._mmdOpenFind();
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;
    // jsdom の時間計測では WebKit の live Range 更新コストを検出できないため、
    // ヒット数・セル数に比例して Range を生成しないことを直接検証する。
    const createRange = jest.spyOn(document, 'createRange');

    for (const [query, expected] of [
      ['a', 8],
      ['al', 3],
    ] as const) {
      createRange.mockClear();
      input.value = query;
      input.dispatchEvent(new window.Event('input'));

      expect(createRange).toHaveBeenCalledTimes(1);
      expect(count(document)).toBe('1/' + expected);
      expect(Array.from(wrap.querySelectorAll('mark'), (mark) => mark.textContent)).toEqual(
        Array.from({ length: expected }, () => query),
      );
    }

    main._mmdCloseFind();
    expect(wrap.innerHTML).toBe(originalHtml);
    createRange.mockRestore();
  });

  // TASK-485.19 で jump.ts 側に見つかった回帰（外枠リネームへの追随漏れで
  // ボタンの click() が一度も配線されなくなっていた）と同型の穴を、
  // find.ts 側でも塞いでおく。next()/prev() の直接呼び出しではなく
  // 実際のボタン要素への click() を検証する。
  test('次へ/前へボタンをクリックすると反応する', () => {
    const { document } = openFindOn('x a x b x', 'x');

    document.getElementById('mmd-find-next')!.click();
    expect(count(document)).toBe('2/3');

    document.getElementById('mmd-find-prev')!.click();
    expect(count(document)).toBe('1/3');
  });

  test('next は末尾から先頭へ循環する', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    main._mmdFind.next();
    expect(count(document)).toBe('2/3');
    main._mmdFind.next();
    expect(count(document)).toBe('3/3');
    main._mmdFind.next();
    expect(count(document)).toBe('1/3');
  });

  test('prev は先頭から末尾へ循環する', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    main._mmdFind.prev();
    expect(count(document)).toBe('3/3');
    main._mmdFind.prev();
    expect(count(document)).toBe('2/3');
  });

  test('現在位置のハイライトは常に1つだけ', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    main._mmdFind.next();

    expect(document.querySelectorAll('mark.mmd-find-match-current').length).toBe(1);
    expect(currentMark(document)).toBe(document.querySelectorAll('mark.mmd-find-match')[1]);
  });

  test('⌘G 相当は検索バーが閉じている間は何もしない', () => {
    const { document, main } = openFindOn('x a x b x', 'x');
    main._mmdCloseFind();

    main._mmdBarNextIfOpen();

    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
  });

  // バーの排他（bar.ts）が検索側にも効いていることを固定する。TASK-485.1 で
  // 「同時に開くバーは 1 つ」を単一の所有者で表す形にしたので、その所有者を
  // 経由しない開閉を書くとここが落ちる。
  test('検索バーは bar レジストリ経由で開閉状態を持つ', () => {
    const { main } = openFindOn('x a x b x', 'x');

    expect(main.currentBar()).toBe('find');
    expect(main.isBarOpen('find')).toBe(true);

    main._mmdCloseFind();

    expect(main.currentBar()).toBe(null);
  });

  test('別のバーを開くと検索バーは閉じる', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    main.claimBar('jump');

    expect(main.currentBar()).toBe('jump');
    expect(document.getElementById('mmd-find-panel')!.style.display).toBe('none');
    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
  });

  test('閉じているバーの release は、後から開いた別のバーを消さない', () => {
    const { main } = openFindOn('x a x b x', 'x');
    main.claimBar('jump');

    main.releaseBar('find');

    expect(main.currentBar()).toBe('jump');
  });

  // 件数表示の「空文字を出す」2 分岐(クエリ空 / 正規表現エラー)を固定する。
  // TASK-485.1 で件数ラベルの組み立てをジャンプ機能と共有する純粋関数へ切り出すため、
  // その前にこの 2 分岐が呼び出し側に残ることを担保しておく(共有関数側へ吸い出すと
  // ジャンプ側には無い状態を引数で持ち回ることになり、検索の表示が静かに変わる)。
  test('クエリが空になると件数表示は空文字になる', () => {
    const { document } = openFindOn('x a x b x', 'x');
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;

    input.value = '';
    input.dispatchEvent(new document.defaultView!.Event('input'));

    expect(count(document)).toBe('');
  });

  test('正規表現として不正なクエリでは件数表示は空文字になる', () => {
    const { document } = openFindOn('x a x b x', 'x');
    document.getElementById('mmd-find-regex')!.click();
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;

    input.value = '[';
    input.dispatchEvent(new document.defaultView!.Event('input'));

    expect(input.classList.contains('mmd-find-error')).toBe(true);
    expect(count(document)).toBe('');
  });

  test('閉じるとハイライトが平文に戻る', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    main._mmdCloseFind();

    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
    expect(document.getElementById('diagram-wrap')!.textContent).toBe('x a x b x');
  });

  // シンタックスハイライトの <span> 境界(や _PATH_RE のリンク化)でテキストノードが
  // 分割されていても、その境界をまたぐ文字列を検索できることを検証する(Issue #336)。
  function openFindOnHtml(html: string, query: string) {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap')!.innerHTML = html;
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input') as HTMLInputElement;
    input.value = query;
    input.dispatchEvent(new loaded.window.Event('input'));
    return loaded;
  }

  test('span 境界をまたぐ foo.bar がデフォルトモードでヒットする', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      'foo.bar',
    );

    expect(count(document)).toBe('1/1');
    const mark = document.querySelector('mark.mmd-find-match')!;
    expect(mark.textContent).toBe('foo.bar');
  });

  test('span 境界をまたぐ .bar が先頭ドットだけでもヒットする', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      '.bar',
    );

    expect(count(document)).toBe('1/1');
    expect(document.querySelector('mark.mmd-find-match')!.textContent).toBe('.bar');
  });

  test('span 境界をまたぐ foo. が末尾ドットだけでもヒットする', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      'foo.',
    );

    expect(count(document)).toBe('1/1');
    expect(document.querySelector('mark.mmd-find-match')!.textContent).toBe('foo.');
  });

  test('span 境界をまたぐマッチはトグル(大小文字・単語一致・正規表現)を有効にしても検出できる', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">Foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">Bar</span>',
      '',
    );
    document.getElementById('mmd-find-case')!.click();
    document.getElementById('mmd-find-word')!.click();
    document.getElementById('mmd-find-regex')!.click();
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;
    input.value = 'Foo\\.Bar';
    input.dispatchEvent(new document.defaultView!.Event('input'));

    expect(count(document)).toBe('1/1');
    expect(document.querySelector('mark.mmd-find-match')!.textContent).toBe('Foo.Bar');
  });

  test('span をまたいだハイライト解除後もテキスト内容が保たれる', () => {
    const { document, main } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      'foo.bar',
    );

    main._mmdCloseFind();

    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
    expect(document.querySelector('#diagram-wrap')!.textContent).toBe('foo.bar');
  });

  // extractContents() は境界をまたぐマッチの端で、部分的にしか含まれない祖先 <span> を
  // 空のまま残す。1打鍵ごとに run() が呼ばれるため、これを放置すると空 <span> が
  // 際限なく増殖してレイアウトが壊れる(タイプするたびに崩れる、という形で顕在化した回帰)。
  test('span 境界をまたぐ検索を連続して打鍵しても空の span が増殖しない', () => {
    const { document, window } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      '',
    );
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;
    const queries = [
      'f',
      'fo',
      'foo',
      'foo.',
      'foo.b',
      'foo.ba',
      'foo.bar',
      'foo.ba',
      'foo.b',
      'foo.',
      'foo',
      'fo',
      'f',
      '',
    ];

    queries.forEach((q) => {
      input.value = q;
      input.dispatchEvent(new window.Event('input'));
    });

    const emptySpans = Array.from(document.querySelectorAll('#diagram-wrap span')).filter(
      (span) => span.textContent === '',
    );
    expect(emptySpans.length).toBe(0);
    expect(document.querySelector('#diagram-wrap')!.textContent).toBe('foo.bar');
  });

  // マッチが1つの <span> 内に収まっている(境界をまたがない)場合は、その span 自体を
  // 分割・複製してはいけない。Range の境界オフセットを前後どちらのテキストノードに
  // 解決するかを誤ると、実際にはマッチしていない隣接 span まで巻き込んで割れてしまう
  // (README 検索でヒット箇所が「b e f o l d」のように分断された回帰の再現)。
  test('マッチが1つの span 内に収まる場合はその span を分割しない', () => {
    const { document } = openFindOnHtml(
      'DMG を開き、<span class="hljs-title">befold</span><span class="hljs-punctuation">.</span><span class="hljs-property">app</span> を配置',
      'b',
    );

    const titleSpans = document.querySelectorAll('#diagram-wrap span.hljs-title');
    expect(titleSpans.length).toBe(1);
    expect(titleSpans[0]!.textContent).toBe('befold');
    expect(document.querySelector('mark.mmd-find-match')!.textContent).toBe('b');
  });

  // 行番号付きコードブロックは行ごとに <tr><td class="line-content"> で区切られる。
  // ブロック境界(見出し・リスト項目・テーブル行/セルなど)をまたいでテキストノードを
  // 連結してしまうと、複数行にまたがる Range の抽出でテーブル構造そのものが壊れる
  // (Markdown プレビュー全体のレイアウトが崩れた回帰の再現)。
  test('リストとテーブル行をまたいで検索してもテーブル構造が壊れない', () => {
    const { document, window } = openFindOnHtml(
      '<ul><li>DMG を開き、<span class="hljs-title">befold</span><span class="hljs-punctuation">.</span>' +
        '<span class="hljs-property">app</span> を配置</li></ul>' +
        '<pre><code class="hljs"><table class="code-table">' +
        '<tr><td class="line-number">1</td><td class="line-content">' +
        '<span class="hljs-title">befold</span> path/to/diagram.mmd</td></tr>' +
        '<tr><td class="line-number">2</td><td class="line-content">' +
        '<span class="hljs-title">befold</span> --help</td></tr>' +
        '</table></code></pre>',
      '',
    );
    const input = document.getElementById('mmd-find-input') as HTMLInputElement;

    ['b', 'be', 'bef', 'befo', 'befol', 'befold'].forEach((q) => {
      input.value = q;
      input.dispatchEvent(new window.Event('input'));
    });

    const rows = document.querySelectorAll('#diagram-wrap table.code-table tr');
    expect(rows.length).toBe(2);
    expect(rows[0]!.querySelector('.line-content')!.textContent).toBe('befold path/to/diagram.mmd');
    expect(rows[1]!.querySelector('.line-content')!.textContent).toBe('befold --help');
  });
});
