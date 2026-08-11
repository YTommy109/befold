// ソース表示に差分を差し込む経路(setDiff → _renderSource)のテスト。
// 差分 HTML の組み立てそのものは viewer-diff.test.js が見る。ここでは
// 「届いていれば差分を出す」「無い/壊れていれば通常のソース表示へ戻る」を確かめる。

const { loadViewerMain } = require('./support/viewerMainHarness');

// カラースキーム変更を発火できる matchMedia に差し替える（ハーネス既定のスタブは
// addEventListener が空実装のため）。蓄積済み内容からの描き直しを観測するのに使う。
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

const DIFF = [
  'diff --git a/a.swift b/a.swift',
  '--- a/a.swift',
  '+++ b/a.swift',
  '@@ -1,2 +1,2 @@',
  '-let x = 1',
  '+let x = 2',
  ' let y = 3',
  '',
].join('\n');

function renderSource(main, content, type, lang) {
  main.setViewMode('source');
  return main.render(content, type, lang);
}

describe('ソース表示への差分の差し込み', () => {
  test('差分が届いていれば差分表示になる', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    await renderSource(main, 'let x = 2\nlet y = 3', 'code', 'swift');

    const table = document.querySelector('#diagram-wrap table.diff-table');
    expect(table).not.toBeNull();
    expect(document.querySelectorAll('#diagram-wrap tr.diff-add')).toHaveLength(1);
    expect(document.querySelectorAll('#diagram-wrap tr.diff-del')).toHaveLength(1);
  });

  // 差分テーブルも class に code-table を持つため、追記先を探すセレクタに
  // 引っかかる。通常のソース行(1 本ガター)を差分テーブル(記号 + 2 本ガター)へ
  // 混ぜると桁がずれ、行数から求める行番号の基準も狂う。
  test('差分表示中はチャンクを DOM へ追記しない', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    await renderSource(main, 'let x = 2\nlet y = 3', 'code', 'swift');
    const before = document.querySelectorAll('#diagram-wrap table.diff-table tr').length;

    main.appendChunk('let z = 4\n', 'code', 'swift');

    const rows = document.querySelectorAll('#diagram-wrap table.diff-table tr');
    expect(rows).toHaveLength(before);
    expect(document.querySelector('#diagram-wrap').textContent).not.toContain('let z = 4');
  });

  // DOM への追記は止めるが、蓄積そのものは続ける。止めると、蓄積済み内容から
  // 描き直す経路(カラースキーム変更)で追記分が失われる。
  test('差分表示中に追記したチャンクも蓄積されている', async () => {
    const loaded = loadViewerMain({ init: false });
    const colorScheme = installColorSchemeStub(loaded.window);
    loaded.main._mmdInit();
    loaded.main.setDiff(DIFF);
    await renderSource(loaded.main, 'let x = 2\n', 'code', 'swift');
    loaded.main.appendChunk('let z = 4\n', 'code', 'swift');
    loaded.main.setDiff(null);
    loaded.document.getElementById('diagram-wrap').innerHTML = '';

    colorScheme.fireChange();

    expect(loaded.document.querySelector('#diagram-wrap').textContent).toContain('let z = 4');
  });

  test('差分が無ければ通常のソース表示のまま', async () => {
    const { document, main } = loadViewerMain({});

    await renderSource(main, 'let x = 2', 'code', 'swift');

    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
    expect(document.querySelector('#diagram-wrap pre code').textContent).toContain('let x = 2');
  });

  // 差分が壊れていても内容は必ず読めること(表示が空にならない)。
  test('パースできない差分では通常のソース表示へ戻る', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff('これは unified diff ではない\n');
    await renderSource(main, 'let x = 2', 'code', 'swift');

    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
    expect(document.querySelector('#diagram-wrap pre code').textContent).toContain('let x = 2');
  });

  test('setDiff(null) で差分表示を解除できる', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    await renderSource(main, 'let x = 2\nlet y = 3', 'code', 'swift');
    expect(document.querySelector('#diagram-wrap table.diff-table')).not.toBeNull();

    main.setDiff(null);
    await renderSource(main, 'let x = 2\nlet y = 3', 'code', 'swift');
    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
  });

  // CSV/TSV のソース表示は独自の列構造を持つため差分表示の対象にしない。
  test('CSV のソース表示は差分が届いていても従来どおり', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    await renderSource(main, 'a,b\n1,2\n', 'csv', ',');

    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
    expect(document.querySelector('#diagram-wrap code.csv-source')).not.toBeNull();
  });

  // レンダリング表示(Markdown 等)は差分の対象外。差分が届いていても
  // 描画結果に混ざらないこと。コードファイルは常にソース表示のため対象になる。
  test('レンダリング表示中は差分が届いていても差分を出さない', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    main.setViewMode('rendered');
    await main.render('# Title', 'md');

    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
  });

  // 差分は表示モード・種別を問わず取得されるため、差分表示を行わない経路でも
  // diff() は非 null になる。そこで追記を止めると、変更済みの大きな .md /
  // .csv で 2 チャンク目以降が永久に出なくなる。
  test('レンダリング表示の Markdown は差分が届いていてもチャンクを追記する', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    main.setViewMode('rendered');
    await main.render('# Title', 'md');

    main.appendChunk('追記された段落\n', 'md');

    expect(document.querySelector('#diagram-wrap').textContent).toContain('追記された段落');
  });

  test('CSV のソース表示は差分が届いていてもチャンクを追記する', async () => {
    const { document, main } = loadViewerMain({});

    main.setDiff(DIFF);
    await renderSource(main, 'a,b\n1,2\n', 'csv', ',');

    main.appendChunk('3,4\n', 'csv', ',');

    expect(document.querySelector('#diagram-wrap').textContent).toContain('3,4');
  });

  // 抑止の判定を DOM(table.diff-table の有無)で行うと、markdown-it が html:true で
  // 通したユーザーコンテンツ内の同名テーブルにも一致し、先頭チャンクの描画以降の
  // 追記がすべて捨てられて文書が黙って途切れる(TASK-339)。
  test('ユーザーコンテンツの diff-table では追記を止めない', async () => {
    const { document, main } = loadViewerMain({});

    main.setViewMode('rendered');
    await main.render('<table class="diff-table"><tr><td>a</td></tr></table>\n', 'md');
    expect(document.querySelector('#diagram-wrap table.diff-table')).not.toBeNull();

    main.appendChunk('追記された段落\n', 'md');

    expect(document.querySelector('#diagram-wrap').textContent).toContain('追記された段落');
  });
});
