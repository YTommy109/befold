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
