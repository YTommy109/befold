// ソース表示に差分を差し込む経路(setDiff → _renderSource)のテスト。
// 差分 HTML の組み立てそのものは viewer-diff.test.js が見る。ここでは
// 「届いていれば差分を出す」「無い/壊れていれば通常のソース表示へ戻る」を確かめる。

const { loadViewerMain } = require('./support/viewerMainHarness');

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
});
