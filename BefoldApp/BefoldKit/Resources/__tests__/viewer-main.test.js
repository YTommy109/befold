// viewer-main.js(命令的レンダリング層)のテスト。
// エクスポート境界の導入により、jsdom + viewer.html の DOM 上でロジックを
// 読み込み・初期化・単体呼び出しできることを確認する。

const { loadViewerMain, captureBridgeMessages } = require('./support/viewerMainHarness');

// カラースキーム変更を発火できる matchMedia に差し替える。ハーネス既定のスタブは
// addEventListener が空実装のため、change を流すテストだけここで置き換える
// (_mmdInit() が matchMedia を呼ぶより前に差し替える必要がある)。
function installColorSchemeStub(window) {
  const listeners = [];
  window.matchMedia = function(query) {
    return {
      media: query,
      matches: false,
      addEventListener: function(type, fn) { listeners.push(fn); },
      removeEventListener: function() {},
    };
  };
  return { fireChange: () => listeners.forEach((fn) => fn()) };
}

// setTimeout/clearTimeout を記録するスタブに差し替える。スクロール通知のデバウンスは
// jsdom window のタイマを使うため jest のフェイクタイマーが効かず、また実時間を待つと
// テストが遅く不安定になる。予約と取り消しを直接観測する。
function installTimerStub(window) {
  const scheduled = [];
  window.setTimeout = function(fn, delay) {
    scheduled.push({ fn: fn, delay: delay, cancelled: false });
    return scheduled.length;
  };
  window.clearTimeout = function(id) {
    if (id) { scheduled[id - 1].cancelled = true; }
  };
  return scheduled;
}

describe('エクスポート境界', () => {
  test('読み込むだけでは初期化の副作用が起きない', () => {
    const { document, main } = loadViewerMain({ init: false });

    expect(typeof main.render).toBe('function');
    expect(typeof main._mmdInit).toBe('function');
    // _mmdInitFind() が反映するはずの状態が未適用であること
    expect(document.getElementById('mmd-find-input').placeholder).toBe('検索');
  });

  test('_mmdInit() を明示的に呼ぶと初期化が走る', () => {
    const { document } = loadViewerMain({
      findStrings: { placeholder: 'Find' },
    });

    expect(document.getElementById('mmd-find-input').placeholder).toBe('Find');
  });
});

describe('_mmdInitZoom', () => {
  test('Swift が注入した倍率を採用する', () => {
    const { window, main, viewer } = loadViewerMain({ initialZoom: '1.5' });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    // 注入値(1.5)が採用されていれば、既定倍率へのリセットは変化として通知される
    main._mmdZoomReset();

    expect(received.length).toBe(1);
    expect(received[0].payload).toBe(viewer.ZOOM_DEFAULT);
  });

  test('注入値と同じ倍率では zoomChanged を通知しない', () => {
    const { window, main } = loadViewerMain({ init: false, initialZoom: '1.5' });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    main._mmdInit();

    expect(received).toEqual([]);
  });

  test('倍率が変わったときだけ zoomChanged を通知する', () => {
    const { window, main } = loadViewerMain({ initialZoom: '1' });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    main._mmdZoomIn();

    expect(received.length).toBe(1);
    expect(received[0].name).toBe('zoomChanged');
    expect(received[0].payload).toBeGreaterThan(1);
  });
});

describe('_mmdScrollTarget', () => {
  test('ソース表示でなければ .viewer を返す', () => {
    const { document, main } = loadViewerMain({});

    expect(main._mmdScrollTarget()).toBe(document.querySelector('.viewer'));
  });

  test('ソース表示では pre code を返す', () => {
    const { document, main } = loadViewerMain({});
    const wrap = document.getElementById('diagram-wrap');
    wrap.classList.add('code-body');
    wrap.innerHTML = '<pre><code>x</code></pre>';

    expect(main._mmdScrollTarget()).toBe(document.querySelector('#diagram-wrap.code-body pre code'));
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

    main._mmdSetTruncated(false);

    expect(document.getElementById('mmd-truncated-banner').style.display).toBe('none');
  });

  test('行数付きでバナーと続き読み込みボタンを表示する', () => {
    const { document, main } = loadViewerMain({ bannerStrings });

    main._mmdSetTruncated(true, 1000, false);

    expect(document.getElementById('mmd-truncated-banner').style.display).toBe('flex');
    expect(document.getElementById('mmd-truncated-text').textContent).toBe('1000 行を表示中');
    const btn = document.getElementById('mmd-load-more-btn');
    expect(btn.style.display).toBe('inline-block');
    expect(btn.textContent).toBe('さらに読み込む');
  });

  test('loadMore 無効ホストではボタンを出さない', () => {
    const { document, main } = loadViewerMain({
      bannerStrings,
      hostFeatures: { loadMore: false },
    });

    main._mmdSetTruncated(true, 1000, false);

    expect(document.getElementById('mmd-load-more-btn').style.display).toBe('none');
  });

  test('読み込み失敗ではエラー文言に切り替えボタンを隠す', () => {
    const { document, main } = loadViewerMain({ bannerStrings });

    main._mmdSetTruncated(true, 1000, true);

    expect(document.getElementById('mmd-truncated-text').textContent)
      .toBe('残りの読み込みに失敗しました');
    expect(document.getElementById('mmd-load-more-btn').style.display).toBe('none');
  });
});

describe('_mmdLoadMore', () => {
  test('loadMoreLines を通知する', () => {
    const { window, main } = loadViewerMain({});
    const received = captureBridgeMessages(window, ['loadMoreLines']);

    main._mmdLoadMore();

    expect(received.length).toBe(1);
    expect(received[0].name).toBe('loadMoreLines');
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

    expect(document.getElementById('mmd-find-case').classList.contains('active')).toBe(true);
    expect(document.getElementById('mmd-find-word').classList.contains('active')).toBe(false);
    expect(document.getElementById('mmd-find-regex').classList.contains('active')).toBe(true);
  });

  test('ローカライズ済み文字列を反映する', () => {
    const { document } = loadViewerMain({
      findStrings: {
        placeholder: 'Find', previous: 'Previous', next: 'Next',
        matchCase: 'Match Case', matchWholeWord: 'Match Whole Word',
        useRegularExpression: 'Use Regular Expression', close: 'Close',
      },
    });

    expect(document.getElementById('mmd-find-input').placeholder).toBe('Find');
    expect(document.getElementById('mmd-find-prev').title).toBe('Previous');
    expect(document.getElementById('mmd-find-next').title).toBe('Next');
    expect(document.getElementById('mmd-find-case').title).toBe('Match Case');
    expect(document.getElementById('mmd-find-word').title).toBe('Match Whole Word');
    expect(document.getElementById('mmd-find-regex').title).toBe('Use Regular Expression');
    expect(document.getElementById('mmd-find-close').title).toBe('Close');
  });
});

describe('検索バーの配線', () => {
  test('トグルのクリックで状態が反転し findOptionsChanged を通知する', () => {
    const { window, document, main } = loadViewerMain({
      initialFindOptions: { caseSensitive: false, wholeWord: false, useRegex: false },
    });
    const received = captureBridgeMessages(window, ['findOptionsChanged']);

    document.getElementById('mmd-find-case').click();

    expect(document.getElementById('mmd-find-case').classList.contains('active')).toBe(true);
    expect(received.length).toBe(1);
    expect(received[0].payload).toEqual({
      caseSensitive: true, wholeWord: false, useRegex: false,
    });
    expect(main._mmdFind.isOpen()).toBe(false);
  });

  test('閉じるボタンで検索バーが閉じる', () => {
    const { document, main } = loadViewerMain({});

    main._mmdOpenFind();
    expect(main._mmdFind.isOpen()).toBe(true);
    expect(document.getElementById('mmd-find-bar').style.display).toBe('flex');

    document.getElementById('mmd-find-close').click();

    expect(main._mmdFind.isOpen()).toBe(false);
    expect(document.getElementById('mmd-find-bar').style.display).toBe('none');
  });
});

describe('render の型ディスパッチ', () => {
  // #diagram-wrap に付いた型別クラスだけを取り出す
  function bodyClasses(document) {
    return Array.from(document.getElementById('diagram-wrap').classList)
      .filter((c) => c.endsWith('-body'))
      .sort();
  }

  test('mmd は mermaid 用の pre を組み立てる', () => {
    const { document, main } = loadViewerMain({});

    // mermaid.min.js は jsdom では読み込めず _mmdEnsureMermaidLoaded() の await が
    // 解決しないため、DOM 構築が終わっている同期部分だけを検証する。
    main.render('graph TD;\nA-->B', 'mmd');

    const wrap = document.getElementById('diagram-wrap');
    expect(wrap.querySelector('pre.mermaid').textContent).toBe('graph TD;\nA-->B');
    expect(bodyClasses(document)).toEqual([]);
  });

  test('mmd はダイアグラム定義を HTML エスケープする', () => {
    const { document, main } = loadViewerMain({});

    main.render('A["<img src=x onerror=alert(1)>"]', 'mmd');

    const wrap = document.getElementById('diagram-wrap');
    expect(wrap.querySelector('img')).toBeNull();
    expect(wrap.querySelector('pre.mermaid').textContent).toContain('<img src=x onerror=alert(1)>');
  });

  test('svg はズームラッパー付きの img を組み立てる', async () => {
    const { window, document, main } = loadViewerMain({});

    await main.render('<svg><text>日本語</text></svg>', 'svg');

    const img = document.querySelector('#diagram-wrap .diagram-zoom-wrap .diagram-zoom-inner img');
    expect(img).not.toBeNull();
    expect(img.alt).toBe('SVG');
    expect(img.src).toBe(window.svgDataURI('<svg><text>日本語</text></svg>'));
    expect(document.querySelector('#diagram-wrap .diagram-zoom-wrap').dataset.diagramIndex).toBe('0');
    // mermaid と同じズーム操作 UI が付く
    expect(document.querySelector('#diagram-wrap .diagram-zoom-controls')).not.toBeNull();
  });

  test('html は sandbox 付き iframe に srcdoc で流し込む', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('<p>hi</p>', 'html');

    const iframe = document.querySelector('#diagram-wrap iframe');
    expect(iframe.getAttribute('sandbox')).toBe('allow-same-origin');
    expect(iframe.srcdoc).toBe('<p>hi</p>');
    expect(bodyClasses(document)).toEqual(['html-body']);
  });

  test('csv はテーブルを組み立てる', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('a,b\n1,2\n', 'csv', ',');

    const headers = Array.from(document.querySelectorAll('#diagram-wrap table th'))
      .map((th) => th.textContent);
    const cells = Array.from(document.querySelectorAll('#diagram-wrap table td'))
      .map((td) => td.textContent);
    expect(headers).toContain('a');
    expect(cells).toContain('2');
    expect(bodyClasses(document)).toEqual(['csv-body', 'markdown-body']);
  });

  test('image は MIME 付きの data URI を img に設定する', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('AAAA', 'image', 'image/webp');

    const img = document.querySelector('#diagram-wrap img');
    expect(img.getAttribute('src')).toBe('data:image/webp;base64,AAAA');
    expect(img.alt).toBe('Image');
    expect(bodyClasses(document)).toEqual(['image-body']);
  });

  test('pdf は data: ではなく blob: URL の iframe にする', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('JVBERg==', 'pdf');

    const iframe = document.querySelector('#diagram-wrap iframe');
    expect(iframe.getAttribute('src').startsWith('blob:')).toBe(true);
    expect(bodyClasses(document)).toEqual(['pdf-body']);
  });

  test('code はコード表示用のクラスと内容を設定する', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('let x = 1', 'code', 'swift');

    expect(document.querySelector('#diagram-wrap pre code').textContent).toBe('let x = 1');
    expect(bodyClasses(document)).toEqual(['code-body']);
  });

  test('markdown-it 未ロードでは代替文言を出して後続処理を打ち切る', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('# Title', 'md');

    expect(document.getElementById('diagram-wrap').textContent).toBe('markdown-it not loaded');
    expect(bodyClasses(document)).toEqual(['markdown-body']);
  });

  test('型を切り替えると前回の型別クラスが残らない', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('AAAA', 'image', 'image/png');
    expect(bodyClasses(document)).toEqual(['image-body']);

    await main.render('a,b\n', 'csv', ',');

    expect(bodyClasses(document)).toEqual(['csv-body', 'markdown-body']);
  });

  test('描画のたびにエラーパネルを消す', async () => {
    const { document, main } = loadViewerMain({});
    const panel = document.getElementById('mmd-error');
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
  function openFindOn(text, query) {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap').textContent = text;
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input');
    input.value = query;
    input.dispatchEvent(new loaded.window.Event('input'));
    return loaded;
  }

  const count = (document) => document.getElementById('mmd-find-count').textContent;
  const currentMark = (document) => document.querySelector('mark.mmd-find-match-current');

  test('検索するとヒット件数と先頭のハイライトが出る', () => {
    const { document } = openFindOn('x a x b x', 'x');

    expect(count(document)).toBe('1/3');
    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(3);
    expect(currentMark(document)).toBe(document.querySelectorAll('mark.mmd-find-match')[0]);
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

    main._mmdFindNextIfOpen();

    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
  });

  test('閉じるとハイライトが平文に戻る', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    main._mmdCloseFind();

    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
    expect(document.getElementById('diagram-wrap').textContent).toBe('x a x b x');
  });
});

describe('_mmdFindRefresh の現在位置維持', () => {
  function openFindOn(text, query) {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap').textContent = text;
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input');
    input.value = query;
    input.dispatchEvent(new loaded.window.Event('input'));
    return loaded;
  }

  const count = (document) => document.getElementById('mmd-find-count').textContent;

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
    document.getElementById('diagram-wrap').textContent = 'x a x';
    main._mmdFindRefresh();

    expect(count(document)).toBe('2/2');
  });

  test('ヒットが無くなったら 0/0 を表示する', () => {
    const { document, main } = openFindOn('x a x b x', 'x');

    document.getElementById('diagram-wrap').textContent = 'no hits here';
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
    document.getElementById('diagram-wrap').textContent = 'x a x';
    main._mmdOpenFind();
    const input = document.getElementById('mmd-find-input');
    input.value = 'x';
    input.dispatchEvent(new window.Event('input'));
    expect(document.getElementById('mmd-find-count').textContent).toBe('1/2');

    main._mmdSetTruncated(true, 100, false);

    expect(document.getElementById('mmd-find-count').textContent).toBe('1/2 (表示範囲内)');
  });
});

describe('モード切替の持ち越し', () => {
  const count = (document) => document.getElementById('mmd-find-count').textContent;

  // csv を描画し、検索バーを開いて 2 件目を選択した状態にする
  async function renderAndSelectSecond() {
    const loaded = loadViewerMain({});
    await loaded.main.render('x,a\nx,b\n', 'csv', ',');
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input');
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
  const lineNumbers = (document) =>
    Array.from(document.querySelectorAll('#diagram-wrap table.code-table tr'))
      .map((tr) => tr.querySelector('.line-number').textContent);

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
    expect(rows[1].querySelector('.line-content').textContent).toBe('bcd');
  });
});

describe('ダイアグラム個別ズーム', () => {
  const labelOf = (wrap) => wrap.querySelector('.diagram-zoom-label').textContent;
  const wraps = (document) =>
    Array.from(document.querySelectorAll('#diagram-wrap .diagram-zoom-wrap'));

  // mermaid 実行後の DOM(=.mermaid が 2 つある状態)を作り、ズームラッパーで包む。
  // 実際の描画は mermaid.min.js を読まないハーネスでは走らないため、包む対象だけ用意する。
  function wrapTwoDiagrams(loaded) {
    const diagramWrap = loaded.document.getElementById('diagram-wrap');
    diagramWrap.innerHTML = '<pre class="mermaid">graph TD; A-->B;</pre>'
      + '<pre class="mermaid">graph TD; C-->D;</pre>';
    loaded.main._mmdWrapDiagrams(diagramWrap);
    return wraps(loaded.document);
  }

  test('個別ズームは対象のダイアグラムだけに効く', () => {
    const loaded = loadViewerMain({});
    const [first, second] = wrapTwoDiagrams(loaded);

    // 先頭以外を操作して、インデックスごとに独立していることを確かめる
    second.querySelector('.diagram-zoom-in').click();

    expect(labelOf(second)).toBe(loaded.viewer.zoomLabel(loaded.viewer.ZOOM_DEFAULT + loaded.viewer.ZOOM_STEP));
    expect(labelOf(first)).toBe(loaded.viewer.zoomLabel(loaded.viewer.ZOOM_DEFAULT));
    expect(loaded.main._mmdDiagramZoomValue(0)).toBe(loaded.viewer.ZOOM_DEFAULT);
    // 全体ズームは個別ズームでは動かない
    expect(loaded.main._mmdZoom.value()).toBe(loaded.viewer.ZOOM_DEFAULT);
  });

  test('個別ズームは再描画をまたいで維持される', () => {
    const loaded = loadViewerMain({});
    const [first] = wrapTwoDiagrams(loaded);
    first.querySelector('.diagram-zoom-in').click();
    const zoomed = labelOf(first);
    expect(zoomed).not.toBe(loaded.viewer.zoomLabel(loaded.viewer.ZOOM_DEFAULT));

    // ライブリロード相当: DOM を作り直して同じ順番のダイアグラムを包み直す
    const [reFirst, reSecond] = wrapTwoDiagrams(loaded);

    expect(labelOf(reFirst)).toBe(zoomed);
    expect(labelOf(reSecond)).toBe(loaded.viewer.zoomLabel(loaded.viewer.ZOOM_DEFAULT));
  });

  test('倍率ラベルのクリックで既定倍率に戻る', () => {
    const loaded = loadViewerMain({});
    const [first] = wrapTwoDiagrams(loaded);
    first.querySelector('.diagram-zoom-in').click();

    first.querySelector('.diagram-zoom-label').click();

    expect(labelOf(first)).toBe(loaded.viewer.zoomLabel(loaded.viewer.ZOOM_DEFAULT));
    expect(loaded.main._mmdDiagramZoomValue(0)).toBe(loaded.viewer.ZOOM_DEFAULT);
  });
});

describe('カラースキーム変更時の再描画', () => {
  test('直近に描画した内容・型・区切り文字で描き直す', async () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();
    await loaded.main.render('a;b\n', 'csv', ';');
    // 描画結果を消し、再描画で戻ってくることを観測できる状態にする
    loaded.document.getElementById('diagram-wrap').innerHTML = '';

    colorScheme.fireChange();

    const cells = Array.from(loaded.document.querySelectorAll('#diagram-wrap th'))
      .map((th) => th.textContent);
    // 区切り文字(';')を保持していなければ 1 セルに固まる
    expect(cells).toEqual(['a', 'b']);
  });

  test('追記済みのチャンクも含めて描き直す', async () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();
    await loaded.main.render('a\n', 'csv', ',');
    loaded.main.appendChunk('b\n', 'csv', ',');
    loaded.document.getElementById('diagram-wrap').innerHTML = '';

    colorScheme.fireChange();

    const rows = Array.from(loaded.document.querySelectorAll('#diagram-wrap tr'))
      .map((tr) => tr.textContent);
    expect(rows).toEqual(['a', 'b']);
  });

  test('まだ何も描画していなければ再描画しない', () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();

    colorScheme.fireChange();

    expect(loaded.document.getElementById('diagram-wrap').innerHTML).toBe('');
  });
});

describe('行番号表示の反映', () => {
  const hasLineNumbers = (document) =>
    document.querySelector('#diagram-wrap table.code-table') !== null;

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

describe('PDF の blob URL', () => {
  // 生成/解放を記録する URL スタブ。ハーネス既定のスタブは解放を観測できない。
  function installBlobUrlRecorder(window) {
    const issued = [];
    const revoked = [];
    window.URL.createObjectURL = function() {
      const url = 'blob:https://localhost/recorded-' + issued.length;
      issued.push(url);
      return url;
    };
    window.URL.revokeObjectURL = function(url) { revoked.push(url); };
    return { issued, revoked };
  }

  test('他の型へ切り替えると前回の blob URL を解放する', async () => {
    const { window, main } = loadViewerMain({});
    const recorder = installBlobUrlRecorder(window);
    await main.render('JVBERg==', 'pdf');

    await main.render('a\nb\n', 'code', 'txt');

    expect(recorder.revoked).toEqual(recorder.issued);
  });

  test('PDF を続けて描画しても解放漏れがない', async () => {
    const { window, main, document } = loadViewerMain({});
    const recorder = installBlobUrlRecorder(window);

    await main.render('JVBERg==', 'pdf');
    await main.render('JVBERg==', 'pdf');

    expect(recorder.issued.length).toBe(2);
    // 直前の 1 本だけが解放され、表示中の URL は生きている
    expect(recorder.revoked).toEqual([recorder.issued[0]]);
    expect(document.querySelector('#diagram-wrap iframe').getAttribute('src'))
      .toBe(recorder.issued[1]);
  });

  test('解放済みの blob URL を二重に解放しない', async () => {
    const { window, main } = loadViewerMain({});
    const recorder = installBlobUrlRecorder(window);
    await main.render('JVBERg==', 'pdf');
    await main.render('a\nb\n', 'code', 'txt');

    await main.render('a\nb\n', 'code', 'txt');

    expect(recorder.revoked.length).toBe(1);
  });
});

describe('スクロール位置の復元', () => {
  test('Swift が注入した位置を次の描画で復元する', async () => {
    const { main } = loadViewerMain({});
    main._mmdSetRestoreScroll(120);

    await main.render('a\nb\n', 'code', 'txt');

    expect(main._mmdScrollTarget().scrollTop).toBe(120);
  });

  test('注入位置は 1 回の描画で消費され、次の描画では現在位置を保つ', async () => {
    const { main } = loadViewerMain({});
    main._mmdSetRestoreScroll(120);
    await main.render('a\nb\n', 'code', 'txt');
    // ソース表示のスクロール実体は描画のたびに作り直されるため都度取り直す
    main._mmdScrollTarget().scrollTop = 40;

    // 内部再描画(カラースキーム変更相当)では注入位置は残っていない
    await main.render('a\nb\n', 'code', 'txt');

    expect(main._mmdScrollTarget().scrollTop).toBe(40);
  });
});

describe('スクロール通知のデバウンス', () => {
  function scroll(loaded) {
    loaded.document.querySelector('.viewer')
      .dispatchEvent(new loaded.window.Event('scroll'));
  }

  test('連続したスクロールは 1 本の通知にまとめる', () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);

    scroll(loaded);
    scroll(loaded);

    expect(scheduled.length).toBe(2);
    expect(scheduled[0].cancelled).toBe(true);
    expect(scheduled[1].delay).toBe(200);
    expect(received).toEqual([]);

    scheduled[1].fn();

    expect(received.length).toBe(1);
    expect(received[0].payload.mode).toBe('rendered');
  });

  test('Swift 主導の切替では保留中の通知を破棄する', async () => {
    const loaded = loadViewerMain({});
    const scheduled = installTimerStub(loaded.window);
    scroll(loaded);

    loaded.main._mmdSetRestoreScroll(0);
    await loaded.main.render('a\nb\n', 'code', 'txt');

    expect(scheduled[0].cancelled).toBe(true);
  });

  test('内部再描画では保留中の通知を残す', async () => {
    const loaded = loadViewerMain({});
    const scheduled = installTimerStub(loaded.window);
    scroll(loaded);

    // 注入位置なし(=ファイル/モードは変わらない)の再描画では確定保存を失わない
    await loaded.main.render('a\nb\n', 'code', 'txt');

    expect(scheduled[0].cancelled).toBe(false);
  });
});

describe('mermaid のパースエラー表示', () => {
  test('mmd 表示ではエラーパネルを出して図の領域を隠す', () => {
    const { main, document } = loadViewerMain({});
    // mermaid.min.js は jsdom では読み込めず await が解決しないため、型の記録が
    // 終わっている同期部分だけを使う(render の型ディスパッチのテストと同じ理由)。
    main.render('graph TD; A-->B;', 'mmd');

    main._mmdMermaidParseError(new Error('boom'));

    expect(document.getElementById('mmd-error').style.display).toBe('block');
    expect(document.getElementById('mmd-error').textContent).toBe('boom');
    expect(document.getElementById('diagram-wrap').style.display).toBe('none');
  });

  test('Markdown 内の図では図の領域を隠さない', async () => {
    const { main, document } = loadViewerMain({});
    // markdown-it 未ロードのハーネスでは本文は縮退するが、型は md として記録される
    await main.render('# title', 'md');

    main._mmdMermaidParseError(new Error('boom'));

    expect(document.getElementById('mmd-error').style.display).toBe('block');
    expect(document.getElementById('diagram-wrap').style.display).toBe('block');
  });
});
