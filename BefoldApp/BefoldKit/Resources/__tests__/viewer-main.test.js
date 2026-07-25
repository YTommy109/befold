// viewer-main.js(命令的レンダリング層)のテスト。
// エクスポート境界の導入により、jsdom + viewer.html の DOM 上でロジックを
// 読み込み・初期化・単体呼び出しできることを確認する。

const { loadViewerMain, captureBridgeMessages } = require('./support/viewerMainHarness');

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
    expect(main._mmdFindIsOpen()).toBe(false);
  });

  test('閉じるボタンで検索バーが閉じる', () => {
    const { document, main } = loadViewerMain({});

    main._mmdOpenFind();
    expect(main._mmdFindIsOpen()).toBe(true);
    expect(document.getElementById('mmd-find-bar').style.display).toBe('flex');

    document.getElementById('mmd-find-close').click();

    expect(main._mmdFindIsOpen()).toBe(false);
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
