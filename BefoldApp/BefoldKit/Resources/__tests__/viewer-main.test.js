// DOM に触れる層(描画・ズーム・検索・参照解決)のテスト。ファイル名は分割前の
// viewer-main.js に由来する。公開面の barrel 経由で、jsdom + viewer.html の DOM 上でロジックを
// 読み込み・初期化・単体呼び出しできることを確認する。

const {
  loadViewerMain,
  captureBridgeMessages,
  dispatchTrustedClick,
  dispatchTrustedContextMenu,
} = require('./support/viewerMainHarness');

// カラースキーム変更を発火できる matchMedia に差し替える。ハーネス既定のスタブは
// addEventListener が空実装のため、change を流すテストだけここで置き換える
// (_mmdInit() が matchMedia を呼ぶより前に差し替える必要がある)。
function installColorSchemeStub(window) {
  const listeners = [];
  window.matchMedia = function (query) {
    return {
      media: query,
      matches: false,
      addEventListener: function (type, fn) {
        listeners.push(fn);
      },
      removeEventListener: function () {},
    };
  };
  return { fireChange: () => listeners.forEach((fn) => fn()) };
}

// setTimeout/clearTimeout を記録するスタブに差し替える。スクロール通知のデバウンスは
// jsdom window のタイマを使うため jest のフェイクタイマーが効かず、また実時間を待つと
// テストが遅く不安定になる。予約と取り消しを直接観測する。
function installTimerStub(window) {
  const scheduled = [];
  window.setTimeout = function (fn, delay) {
    scheduled.push({ fn: fn, delay: delay, cancelled: false });
    return scheduled.length;
  };
  window.clearTimeout = function (id) {
    if (id) {
      scheduled[id - 1].cancelled = true;
    }
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
    const { window, main } = loadViewerMain({ initialZoom: '1.5' });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    // 注入値(1.5)が採用されていれば、既定倍率へのリセットは変化として通知される
    main._mmdZoomReset();

    expect(received.length).toBe(1);
    expect(received[0].payload.zoom).toBe(main.ZOOM_DEFAULT);
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
    expect(received[0].payload.zoom).toBeGreaterThan(1);
  });

  // 倍率も per-file に保存されるため、スクロール位置と同じく「その倍率が属する文書」を
  // 発火時に申告する。Swift 側の現在 URL を参照していた頃は、切替直後に配達された
  // 通知が切替先のキーを汚した(TASK-391)。
  test('zoomChanged に採用済みの文書パスを載せる', async () => {
    const { window, main } = loadViewerMain({ initialZoom: '1' });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    main._mmdZoomIn();

    expect(received[received.length - 1].payload.path).toBe('/mock/a.md');
  });

  test('文書が定まらない間(描画前)の zoomChanged は path に null を送る', () => {
    const { window, main } = loadViewerMain({ initialZoom: '1' });
    const received = captureBridgeMessages(window, ['zoomChanged']);

    main._mmdZoomIn();

    expect(received[received.length - 1].payload.path).toBeNull();
  });

  test('rename 後の zoomChanged は新しいパスを載せる', async () => {
    const { window, main } = loadViewerMain({ initialZoom: '1' });
    const received = captureBridgeMessages(window, ['zoomChanged']);
    main._mmdSetRenderDocPath('/mock/a.md');
    await main.render('a\nb\n', 'code', 'txt');

    main._mmdRenameDocPath('/mock/a.md', '/mock/b.md');
    main._mmdZoomIn();

    expect(received[received.length - 1].payload.path).toBe('/mock/b.md');
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

    expect(document.getElementById('mmd-truncated-text').textContent).toBe(
      '残りの読み込みに失敗しました',
    );
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
        placeholder: 'Find',
        previous: 'Previous',
        next: 'Next',
        matchCase: 'Match Case',
        matchWholeWord: 'Match Whole Word',
        useRegularExpression: 'Use Regular Expression',
        close: 'Close',
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
    expect(document.querySelector('#diagram-wrap .diagram-zoom-wrap').dataset.diagramIndex).toBe(
      '0',
    );
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

  // ベンダーはバンドル同梱(viewer-src/vendor.js)になったため「markdown-it 未ロード」
  // という状態は存在しない(TASK-432.5)。以前はこの経路の縮退表示を固定していた。
  test('md は markdown-it でレンダリングする', async () => {
    const { document, main } = loadViewerMain({});

    await main.render('# Title', 'md');

    expect(document.querySelector('#diagram-wrap h1').textContent).toBe('Title');
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

  // シンタックスハイライトの <span> 境界(や _PATH_RE のリンク化)でテキストノードが
  // 分割されていても、その境界をまたぐ文字列を検索できることを検証する(Issue #336)。
  function openFindOnHtml(html, query) {
    const loaded = loadViewerMain({});
    loaded.document.getElementById('diagram-wrap').innerHTML = html;
    loaded.main._mmdOpenFind();
    const input = loaded.document.getElementById('mmd-find-input');
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
    const mark = document.querySelector('mark.mmd-find-match');
    expect(mark.textContent).toBe('foo.bar');
  });

  test('span 境界をまたぐ .bar が先頭ドットだけでもヒットする', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      '.bar',
    );

    expect(count(document)).toBe('1/1');
    expect(document.querySelector('mark.mmd-find-match').textContent).toBe('.bar');
  });

  test('span 境界をまたぐ foo. が末尾ドットだけでもヒットする', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      'foo.',
    );

    expect(count(document)).toBe('1/1');
    expect(document.querySelector('mark.mmd-find-match').textContent).toBe('foo.');
  });

  test('span 境界をまたぐマッチはトグル(大小文字・単語一致・正規表現)を有効にしても検出できる', () => {
    const { document } = openFindOnHtml(
      '<span class="hljs-title">Foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">Bar</span>',
      '',
    );
    document.getElementById('mmd-find-case').click();
    document.getElementById('mmd-find-word').click();
    document.getElementById('mmd-find-regex').click();
    const input = document.getElementById('mmd-find-input');
    input.value = 'Foo\\.Bar';
    input.dispatchEvent(new document.defaultView.Event('input'));

    expect(count(document)).toBe('1/1');
    expect(document.querySelector('mark.mmd-find-match').textContent).toBe('Foo.Bar');
  });

  test('span をまたいだハイライト解除後もテキスト内容が保たれる', () => {
    const { document, main } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      'foo.bar',
    );

    main._mmdCloseFind();

    expect(document.querySelectorAll('mark.mmd-find-match').length).toBe(0);
    expect(document.querySelector('#diagram-wrap').textContent).toBe('foo.bar');
  });

  // extractContents() は境界をまたぐマッチの端で、部分的にしか含まれない祖先 <span> を
  // 空のまま残す。1打鍵ごとに run() が呼ばれるため、これを放置すると空 <span> が
  // 際限なく増殖してレイアウトが壊れる(タイプするたびに崩れる、という形で顕在化した回帰)。
  test('span 境界をまたぐ検索を連続して打鍵しても空の span が増殖しない', () => {
    const { document, window } = openFindOnHtml(
      '<span class="hljs-title">foo</span><span class="hljs-punctuation">.</span><span class="hljs-property">bar</span>',
      '',
    );
    const input = document.getElementById('mmd-find-input');
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
    expect(document.querySelector('#diagram-wrap').textContent).toBe('foo.bar');
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
    expect(titleSpans[0].textContent).toBe('befold');
    expect(document.querySelector('mark.mmd-find-match').textContent).toBe('b');
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
    const input = document.getElementById('mmd-find-input');

    ['b', 'be', 'bef', 'befo', 'befol', 'befold'].forEach((q) => {
      input.value = q;
      input.dispatchEvent(new window.Event('input'));
    });

    const rows = document.querySelectorAll('#diagram-wrap table.code-table tr');
    expect(rows.length).toBe(2);
    expect(rows[0].querySelector('.line-content').textContent).toBe('befold path/to/diagram.mmd');
    expect(rows[1].querySelector('.line-content').textContent).toBe('befold --help');
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
    Array.from(document.querySelectorAll('#diagram-wrap table.code-table tr')).map(
      (tr) => tr.querySelector('.line-number').textContent,
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
    diagramWrap.innerHTML =
      '<pre class="mermaid">graph TD; A-->B;</pre><pre class="mermaid">graph TD; C-->D;</pre>';
    loaded.main._mmdWrapDiagrams(diagramWrap);
    return wraps(loaded.document);
  }

  test('個別ズームは対象のダイアグラムだけに効く', () => {
    const loaded = loadViewerMain({});
    const [first, second] = wrapTwoDiagrams(loaded);

    // 先頭以外を操作して、インデックスごとに独立していることを確かめる
    second.querySelector('.diagram-zoom-in').click();

    expect(labelOf(second)).toBe(
      loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT + loaded.main.ZOOM_STEP),
    );
    expect(labelOf(first)).toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));
    expect(loaded.main._mmdDiagramZoomValue(0)).toBe(loaded.main.ZOOM_DEFAULT);
    // 全体ズームは個別ズームでは動かない
    expect(loaded.main._mmdZoom.value()).toBe(loaded.main.ZOOM_DEFAULT);
  });

  test('個別ズームは再描画をまたいで維持される', () => {
    const loaded = loadViewerMain({});
    const [first] = wrapTwoDiagrams(loaded);
    first.querySelector('.diagram-zoom-in').click();
    const zoomed = labelOf(first);
    expect(zoomed).not.toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));

    // ライブリロード相当: DOM を作り直して同じ順番のダイアグラムを包み直す
    const [reFirst, reSecond] = wrapTwoDiagrams(loaded);

    expect(labelOf(reFirst)).toBe(zoomed);
    expect(labelOf(reSecond)).toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));
  });

  test('倍率ラベルのクリックで既定倍率に戻る', () => {
    const loaded = loadViewerMain({});
    const [first] = wrapTwoDiagrams(loaded);
    first.querySelector('.diagram-zoom-in').click();

    first.querySelector('.diagram-zoom-label').click();

    expect(labelOf(first)).toBe(loaded.main.zoomLabel(loaded.main.ZOOM_DEFAULT));
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
    loaded.document.getElementById('diagram-wrap').innerHTML = '';

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
    loaded.document.getElementById('diagram-wrap').innerHTML = '';

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

    expect(loaded.document.getElementById('diagram-wrap').innerHTML).toBe('');
  });
});

describe('行番号表示の反映', () => {
  // 行単位テーブルは行番号の有無に関わらず常に使うため、行番号セルの有無で判定する。
  const hasLineNumbers = (document) =>
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
      (c) => c.getAttribute('style') && c.getAttribute('style').includes('--indent-cols:4'),
    );
    expect(indented).toBeTruthy();
    expect(indented.getAttribute('style')).toContain('--indent-depth:1');
    // 行番号セルは付かない。
    expect(document.querySelector('#diagram-wrap td.line-number')).toBeNull();
  });
});

describe('PDF の blob URL', () => {
  // 生成/解放を記録する URL スタブ。ハーネス既定のスタブは解放を観測できない。
  function installBlobUrlRecorder(window) {
    const issued = [];
    const revoked = [];
    window.URL.createObjectURL = function () {
      const url = 'blob:https://localhost/recorded-' + issued.length;
      issued.push(url);
      return url;
    };
    window.URL.revokeObjectURL = function (url) {
      revoked.push(url);
    };
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
    expect(document.querySelector('#diagram-wrap iframe').getAttribute('src')).toBe(
      recorder.issued[1],
    );
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
    loaded.document.querySelector('.viewer').dispatchEvent(new loaded.window.Event('scroll'));
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

describe('スクロール通知の文書パス', () => {
  function scroll(loaded) {
    loaded.document.querySelector('.viewer').dispatchEvent(new loaded.window.Event('scroll'));
  }

  function lastNotifiedPath(loaded, received, scheduled) {
    scroll(loaded);
    scheduled[scheduled.length - 1].fn();
    return received[received.length - 1].payload.path;
  }

  test('render で採用された予告パスを通知に載せる', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);
    loaded.main._mmdSetRenderDocPath('/mock/a.md');
    await loaded.main.render('a\nb\n', 'code', 'txt');

    expect(lastNotifiedPath(loaded, received, scheduled)).toBe('/mock/a.md');
  });

  test('文書が定まらない間(描画前)は null を送る', () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);

    expect(lastNotifiedPath(loaded, received, scheduled)).toBeNull();
  });

  test('予告は render まで採用されない(採用前の通知は現在の文書のパスのまま)', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);
    loaded.main._mmdSetRenderDocPath('/mock/a.md');
    await loaded.main.render('a\nb\n', 'code', 'txt');

    // 切替先の予告だけがあり render がまだ実行されていない間、DOM は旧文書のまま。
    // ここで発火した通知が新パスを名乗ると、旧文書の位置が切替先のキーへ保存される。
    loaded.main._mmdSetRenderDocPath('/mock/b.md');

    expect(lastNotifiedPath(loaded, received, scheduled)).toBe('/mock/a.md');
  });

  test('予告なしの内部再描画では採用済みのパスを保つ', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);
    loaded.main._mmdSetRenderDocPath('/mock/a.md');
    await loaded.main.render('a\nb\n', 'code', 'txt');

    // カラースキーム変更相当(予告なしの render)でパスが消えてはならない
    await loaded.main.render('a\nb\n', 'code', 'txt');

    expect(lastNotifiedPath(loaded, received, scheduled)).toBe('/mock/a.md');
  });

  test('_mmdRenameDocPath は render を経ずに現在のパスを差し替える', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);
    loaded.main._mmdSetRenderDocPath('/mock/a.md');
    await loaded.main.render('a\nb\n', 'code', 'txt');

    loaded.main._mmdRenameDocPath('/mock/a.md', '/mock/b.md');

    expect(lastNotifiedPath(loaded, received, scheduled)).toBe('/mock/b.md');
  });

  test('_mmdRenameDocPath は現在のパスが一致しないとき何もしない', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);
    loaded.main._mmdSetRenderDocPath('/mock/a.md');
    await loaded.main.render('a\nb\n', 'code', 'txt');

    // 別文書へ切替中の rename 等。誤った付け替えより旧キーへの短時間の保存が安全。
    loaded.main._mmdRenameDocPath('/mock/x.md', '/mock/y.md');

    expect(lastNotifiedPath(loaded, received, scheduled)).toBe('/mock/a.md');
  });

  test('_mmdRenameDocPath は未採用の予告パスも差し替える', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['scrollPositionChanged']);
    const scheduled = installTimerStub(loaded.window);

    // 旧名の render が実行待ちのまま rename された場合、採用後のパスも新名になる
    loaded.main._mmdSetRenderDocPath('/mock/a.md');
    loaded.main._mmdRenameDocPath('/mock/a.md', '/mock/b.md');
    await loaded.main.render('a\nb\n', 'code', 'txt');

    expect(lastNotifiedPath(loaded, received, scheduled)).toBe('/mock/b.md');
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

describe('パス参照の表示時解決', () => {
  // #diagram-wrap に任意の HTML を流し込み、収集対象を組み立てる。
  // <a> は markdown-it 未ロードのハーネスでは render() から作れないため直接置く。
  function setWrapHtml(loaded, html) {
    loaded.document.getElementById('diagram-wrap').innerHTML = html;
  }

  function classesOf(loaded, selector) {
    return Array.from(loaded.document.querySelector(selector).classList).sort();
  }

  function click(loaded, selector, init) {
    dispatchTrustedClick(loaded.window, loaded.document.querySelector(selector), init);
  }

  test('描画後にローカルパス候補を一意化して resolveReferences を送る', async () => {
    const loaded = loadViewerMain({});
    const received = captureBridgeMessages(loaded.window, ['resolveReferences']);

    await loaded.main.render('src/a.swift\nsrc/a.swift\nsrc/b.swift\n', 'code', 'txt');

    expect(received.length).toBe(1);
    expect(received[0].payload.paths.sort()).toEqual(['src/a.swift', 'src/b.swift']);
    // 応答が返るまでは全候補が中立表示になる
    const refs = loaded.document.querySelectorAll('#diagram-wrap .befold-path-ref');
    expect(refs.length).toBe(3);
    refs.forEach((ref) => expect(ref.classList.contains('befold-link-pending')).toBe(true));
  });

  test('解決できたものだけをリンク化し、絶対パスを DOM に残す', async () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    await loaded.main.render('src/a.swift\nsrc/missing.swift\n', 'code', 'txt');

    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });

    const refs = loaded.document.querySelectorAll('#diagram-wrap .befold-path-ref');
    expect(Array.from(refs[0].classList).sort()).toEqual(['befold-link', 'befold-path-ref']);
    expect(refs[0].dataset.resolved).toBe('/repo/src/a.swift');
    expect(Array.from(refs[1].classList).sort()).toEqual(['befold-link-dead', 'befold-path-ref']);
    expect(refs[1].dataset.resolved).toBeUndefined();
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

    expect(received[0].payload.paths).toEqual(['./notes.md']);
    loaded.main._mmdApplyResolvedReferences({ './notes.md': '/repo/notes.md' });

    const refs = Array.from(loaded.document.querySelectorAll('#diagram-wrap .befold-path-ref'));
    expect(refs.length).toBeGreaterThan(1);
    refs.forEach((ref) => {
      expect(Array.from(ref.classList).sort()).toEqual(['befold-link', 'befold-path-ref']);
      dispatchTrustedClick(loaded.window, ref);
    });

    expect(
      received.filter((m) => m.name === 'referenceActivated').map((m) => m.payload.href),
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

    expect(loaded.document.getElementById('dead').hasAttribute('href')).toBe(false);
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
    ['#ext', '#mail', '#anchor'].forEach((sel) => expect(classesOf(loaded, sel)).toEqual([]));
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

    expect(received[0].payload.paths).toEqual(['viewer-main.js:12']);
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

    expect(received.map((m) => m.payload.paths)).toEqual([['src/a.swift'], ['src/b.swift']]);
    const refs = loaded.document.querySelectorAll('#diagram-wrap .befold-path-ref');
    expect(refs[0].classList.contains('befold-link')).toBe(true);
    expect(refs[1].classList.contains('befold-link-pending')).toBe(true);
  });

  test('未応答バッチが無い状態で応答が届いても何も起きない', async () => {
    const loaded = loadViewerMain({});
    captureBridgeMessages(loaded.window, ['resolveReferences']);
    await loaded.main.render('src/a.swift\n', 'code', 'txt');
    loaded.main._mmdApplyResolvedReferences({ 'src/a.swift': '/repo/src/a.swift' });
    const ref = loaded.document.querySelector('#diagram-wrap .befold-path-ref');

    // キューが空の状態での 2 度目の応答(Swift 側の重複応答を想定)
    loaded.main._mmdApplyResolvedReferences({});

    expect(Array.from(ref.classList).sort()).toEqual(['befold-link', 'befold-path-ref']);
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

    const ref = loaded.document.querySelector('#diagram-wrap .befold-path-ref');
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
      const el = loaded.document.querySelector(sel);
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

    expect(received[0].payload.paths.sort()).toEqual(['./doc.md', '__proto__']);
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

    expect(loaded.document.getElementById('fake').getAttribute('title')).toBe('/repo/secret.md');
    expect(loaded.document.getElementById('dead').hasAttribute('title')).toBe(false);
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
      loaded.document.querySelector('#diagram-wrap .befold-path-ref'),
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
      loaded.document.getElementById('diagram-wrap'),
    );

    expect(event.defaultPrevented).toBe(false);
    expect(received).toEqual([]);
  });
});

describe('Markdown のチャンク追記(Issue #307)', () => {
  const wrap = (document) => document.getElementById('diagram-wrap');

  test('追記したチャンクが末尾にレンダリングされる', async () => {
    const { main, document } = loadViewerMain({});
    await main.render('# first\n\n', 'md');

    main.appendChunk('## second\n\n', 'md');

    expect(wrap(document).querySelector('h1').textContent).toBe('first');
    expect(wrap(document).querySelector('h2').textContent).toBe('second');
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

    const img = wrap(document).querySelector('img');
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
