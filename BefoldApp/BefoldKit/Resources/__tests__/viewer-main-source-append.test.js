// ソース表示中の描画と追記が、レンダリング表示側と同じ規則で動くことのテスト。
//
// render() と appendChunk() が表示形をそれぞれ別に判定していた頃、同じ文書で
// 3 通りの挙動が出ていた（TASK-414）:
//   - source 表示中の「さらに読み込む」で、行番号付きソースの下に
//     描画済み Markdown が挟まる（appendChunk が type だけで md と判断していた）
//   - source 表示の初回描画でパス参照が注釈されない（render が早期 return していた）
//   - 追記された行だけがリンクになり、上の行は死んだまま

const { loadViewerMain } = require('./support/viewerMainHarness');

const MD = ['# title', '', 'see ./notes.md for details', ''].join('\n');

async function renderIn(main, mode, content, type, lang) {
  main.setViewMode(mode);
  return main.render(content, type, lang);
}

function codeTableRows(document) {
  return document.querySelectorAll('#diagram-wrap table.code-table tr');
}

function lineNumbers(document) {
  return Array.from(document.querySelectorAll('#diagram-wrap td.line-number')).map(
    (cell) => cell.textContent
  );
}

describe('ソース表示中のチャンク追記', () => {
  test('追記分がソース行として入り、描画済み Markdown が混ざらない', async () => {
    const { document, main } = loadViewerMain({});
    main.setLineNumbers(true);
    await renderIn(main, 'source', '# title\n', 'md');
    const before = codeTableRows(document).length;

    main.appendChunk('## second\n', 'md');

    // 追記はコード表の行として入る。
    expect(codeTableRows(document).length).toBe(before + 1);
    // md.render の結果（<h2>）が紛れ込んでいない。ソースは記号のまま読める。
    expect(document.querySelector('#diagram-wrap h2')).toBeNull();
    expect(document.querySelector('#diagram-wrap').textContent).toContain('## second');
  });

  test('追記後も行番号が 1 から連続する', async () => {
    const { document, main } = loadViewerMain({});
    main.setLineNumbers(true);
    await renderIn(main, 'source', 'one\ntwo\n', 'md');

    main.appendChunk('three\nfour\n', 'md');

    expect(lineNumbers(document)).toEqual(['1', '2', '3', '4']);
  });

  test('レンダリング表示では従来どおり描画済み Markdown が追記される', async () => {
    const { document, main } = loadViewerMain({});
    await renderIn(main, 'rendered', '# title\n', 'md');

    main.appendChunk('## second\n', 'md');

    expect(document.querySelector('#diagram-wrap h2')).not.toBeNull();
  });

  // type だけでは追記先が決まらない代表例。同じ 'csv' でも、レンダリング表示なら
  // <tbody> の行、ソース表示ならレインボー着色のソース行になる。
  test('CSV は同じ type でも表示モードで追記先が変わる', async () => {
    const rendered = loadViewerMain({});
    const source = loadViewerMain({});

    await renderIn(rendered.main, 'rendered', 'a,b\n1,2\n', 'csv', ',');
    rendered.main.appendChunk('3,4\n', 'csv', ',');

    await renderIn(source.main, 'source', 'a,b\n1,2\n', 'csv', ',');
    source.main.appendChunk('3,4\n', 'csv', ',');

    // レンダリング表示はテーブルの行が増える。
    expect(rendered.document.querySelectorAll('#diagram-wrap tbody tr').length).toBe(2);
    // ソース表示はソースのまま増え、テーブル行にはならない。
    expect(source.document.querySelector('#diagram-wrap tbody tr')).toBeNull();
    expect(source.document.querySelector('#diagram-wrap code.csv-source')).not.toBeNull();
    expect(source.document.querySelector('#diagram-wrap').textContent).toContain('3,4');
  });

  // render が判定を更新したら appendChunk 側もそれに従う。両者が別々に判定を
  // 持っていると、モードを切り替えた直後の追記だけが前の形のまま入る。
  test('モードを切り替えて描き直すと、追記先もその形へ変わる', async () => {
    const { document, main } = loadViewerMain({});
    await renderIn(main, 'source', '# title\n', 'md');
    main.appendChunk('## second\n', 'md');
    expect(document.querySelector('#diagram-wrap h2')).toBeNull();

    await renderIn(main, 'rendered', '# title\n## second\n', 'md');
    main.appendChunk('### third\n', 'md');

    expect(document.querySelector('#diagram-wrap h3')).not.toBeNull();
  });
});

describe('ソース表示のパス参照', () => {
  test('初回描画でパス参照が注釈される', async () => {
    const { document, main } = loadViewerMain({});

    await renderIn(main, 'source', MD, 'md');

    expect(document.querySelectorAll('#diagram-wrap .befold-path-ref').length).toBeGreaterThan(0);
  });

  // .swift（code 種別）は常にソース表示で、以前から注釈されていた。
  // 同じ文字列が .md のソース表示では死んでいたため、両者の一致を固定する。
  test('.md のソース表示と .swift で挙動が一致する', async () => {
    const md = loadViewerMain({});
    const code = loadViewerMain({});

    // コメント行にするのは、ハイライトがパス文字列を span で割らない形にするため。
    // 素の `see ./notes.md ...` は swift ハイライトが `./` を hljs-operator として
    // 切り出し、テキストノードが分かれてパス参照として認識されない(TASK-455)。
    await renderIn(md.main, 'source', '// see ./notes.md for details\n', 'md');
    await renderIn(code.main, 'source', '// see ./notes.md for details\n', 'code', 'swift');

    const mdRefs = md.document.querySelectorAll('#diagram-wrap .befold-path-ref').length;
    const codeRefs = code.document.querySelectorAll('#diagram-wrap .befold-path-ref').length;
    expect(mdRefs).toBe(codeRefs);
    expect(mdRefs).toBeGreaterThan(0);
  });

  test('チャンク追記の前後でパス参照の扱いが変わらない', async () => {
    const { document, main } = loadViewerMain({});
    await renderIn(main, 'source', 'see ./first.md now\n', 'md');
    const beforeRefs = document.querySelectorAll('#diagram-wrap .befold-path-ref').length;
    expect(beforeRefs).toBeGreaterThan(0);

    main.appendChunk('see ./second.md too\n', 'md');

    // 追記された行も注釈され、先に描かれた行の注釈も残っている。
    const refs = Array.from(document.querySelectorAll('#diagram-wrap .befold-path-ref')).map(
      (el) => el.getAttribute('data-path')
    );
    expect(refs).toContain('./first.md');
    expect(refs).toContain('./second.md');
  });
});
