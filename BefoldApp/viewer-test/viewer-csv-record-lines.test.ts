// CSV/TSV のレコードとソース行の対応表（csvRecordLineRanges / TASK-483.1）のテスト。
// git diff は行単位で届くため、レンダリング差分はこの対応表で行をレコードへ引き当てる。

import { describe, expect, test } from '@jest/globals';

import { csvRecordLineRanges, parseCsv } from '../viewer-src/main.js';

describe('csvRecordLineRanges', () => {
  test('改行を含まない CSV ではレコード番号とソース行番号が一致する', () => {
    expect(csvRecordLineRanges('a,b\n1,2\n3,4\n', ',')).toEqual([
      [0, 1],
      [1, 2],
      [2, 3],
    ]);
  });

  test('TSV でも同じ', () => {
    expect(csvRecordLineRanges('a\tb\n1\t2', '\t')).toEqual([
      [0, 1],
      [1, 2],
    ]);
  });

  test('引用符内の改行を含むレコードは複数行を占める', () => {
    const content = 'id,memo\n1,"line1\nline2\nline3"\n2,plain\n';
    expect(csvRecordLineRanges(content, ',')).toEqual([
      [0, 1],
      [1, 4],
      [4, 5],
    ]);
    // テーブル表示と同じレコード数になる（対応表がテーブルの行と食い違わない）。
    expect(parseCsv(content, ',')).toHaveLength(3);
  });

  test('CRLF の改行も 1 行として数える', () => {
    expect(csvRecordLineRanges('a,b\r\n1,"x\r\ny"\r\n2,z\r\n', ',')).toEqual([
      [0, 1],
      [1, 3],
      [3, 4],
    ]);
  });

  test('空行も 1 レコードとして 1 行を占める', () => {
    expect(csvRecordLineRanges('a\n\nb\n', ',')).toEqual([
      [0, 1],
      [1, 2],
      [2, 3],
    ]);
  });

  test('空文字列はレコードなし', () => {
    expect(csvRecordLineRanges('', ',')).toEqual([]);
  });
});
