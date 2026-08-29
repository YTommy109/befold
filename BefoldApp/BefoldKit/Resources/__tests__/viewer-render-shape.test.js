const { renderShape } = require('../../../viewer-src/main.js');

// 「表示モードと種別から、いま DOM に描く形を決める」判定の単体テスト。
//
// この形は render() の分岐と appendChunk() の追記戦略の両方の元になる。
// 判定が 2 箇所に分かれていた頃は、source 表示中の追記が type だけで
// md と判断され、行番号付きソースの下に描画済み Markdown が挟まった（TASK-414）。
describe('renderShape', () => {
  // レンダリング表示: 種別ごとの描画形がそのまま出る。
  test.each([
    ['md', 'markdown'],
    ['csv', 'csv-table'],
    ['code', 'code'],
    ['mmd', 'mmd'],
    ['svg', 'svg'],
    ['html', 'html'],
    ['image', 'image'],
  ])('rendered モードの %s は %s になる', (type, expected) => {
    expect(renderShape(type, 'rendered')).toBe(expected);
  });

  // ソース表示: テキスト種別はすべて行番号付きのコード表になる。
  test.each([
    ['md', 'code'],
    ['svg', 'code'],
    ['html', 'code'],
    ['code', 'code'],
    ['plaintext', 'code'],
  ])('source モードの %s は code（行番号付きソース）になる', (type) => {
    expect(renderShape(type, 'source')).toBe('code');
  });

  // CSV/TSV のソース表示だけは列構造を持つ別の形（レインボー着色）。
  test('source モードの csv は csv-source になる', () => {
    expect(renderShape('csv', 'source')).toBe('csv-source');
  });

  // 画像はソース表示を持たない。モードに関わらず同じ形になる。
  // PDF はここに現れない(viewer.html を通らず PDFView が描く / ADR 0009)。
  test('image は source モードでも形が変わらない', () => {
    expect(renderShape('image', 'source')).toBe(renderShape('image', 'rendered'));
  });

  // コードファイルは常にソース表示。モードで形が変わらないことを固定する
  // (「.md では差分が出るのに .swift では出ない」形の分岐差を再発させない)。
  test('code はモードによらず code のまま', () => {
    expect(renderShape('code', 'rendered')).toBe('code');
    expect(renderShape('code', 'source')).toBe('code');
  });

  // 未知のモード文字列でレンダリング表示側へ倒れること（setViewMode が
  // 'rendered'/'source' 以外を弾くため、ここへ来るのは実質ありえないが、
  // 判定が真偽の取り違えで source 側へ倒れないことを固定する）。
  test('未知のモードはレンダリング表示として扱う', () => {
    expect(renderShape('md', 'unknown')).toBe('markdown');
  });
});
