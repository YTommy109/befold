// CSV/TSV のテーブル表示へ差分を重ねる経路(TASK-483.2)のテスト。
// 表の組み立て(buildCsvDiffTable / orderCsvDiffRecords)と、render() を通した
// 表示・追記抑止・差分ジャンプ・通常表示への縮退を見る。

import { describe, expect, test } from '@jest/globals';

import { buildCsvDiffTable, orderCsvDiffRecords, parseUnifiedDiff } from '../viewer-src/main.js';
import { loadViewerMain } from './support/viewerMainHarness.js';

// 全文差分(-U1000000 相当)を組む。lines は ' ' / '+' / '-' 接頭辞付きの行。
function wholeFileDiff(lines: string[]): string {
  const oldCount = lines.filter((l) => !l.startsWith('+')).length;
  const newCount = lines.filter((l) => !l.startsWith('-')).length;
  return [
    'diff --git a/t.csv b/t.csv',
    '--- a/t.csv',
    '+++ b/t.csv',
    `@@ -1,${oldCount} +1,${newCount} @@`,
    ...lines,
    '',
  ].join('\n');
}

// 1 レコード 1 行の対応表。
function ranges(n: number): [number, number][] {
  return Array.from({ length: n }, (_, i) => [i, i + 1] as [number, number]);
}

function bodyRows(html: string): { cls: string; block: string | null; text: string }[] {
  const doc = new DOMParser().parseFromString(html, 'text/html');
  return Array.from(doc.querySelectorAll('tbody tr'), (tr) => ({
    cls: tr.className,
    block: (tr as HTMLElement).dataset['diffBlock'] ?? null,
    text: Array.from(tr.querySelectorAll('td'), (td) => td.textContent).join('|'),
  }));
}

describe('buildCsvDiffTable', () => {
  test('追加・削除されたレコードに色と変更ブロック番号が付く', () => {
    const diff = wholeFileDiff([' id,name', ' 1,a', '-2,b', '+2,B', ' 3,c', '+4,d']);
    const table = buildCsvDiffTable(diff, ',')!;
    expect(bodyRows(table.html)).toEqual([
      { cls: '', block: null, text: '1|a' },
      { cls: 'diff-del', block: '0', text: '2|b' },
      { cls: 'diff-add', block: '0', text: '2|B' },
      { cls: '', block: null, text: '3|c' },
      { cls: 'diff-add', block: '1', text: '4|d' },
    ]);
  });

  // 行番号をそのままレコードへ当てると、2 行目以降の色が 1 つずつずれる。
  test('引用符内に改行を含むレコードでも色が正しいレコードに当たる', () => {
    const diff = wholeFileDiff([' id,memo', ' 1,"x', '-y"', '+Y"', ' 2,z']);
    expect(bodyRows(buildCsvDiffTable(diff, ',')!.html)).toEqual([
      { cls: 'diff-del', block: '0', text: '1|x\ny' },
      { cls: 'diff-add', block: '0', text: '1|x\nY' },
      { cls: '', block: null, text: '2|z' },
    ]);
  });

  // csv-resize は tHead.rows[0] を見出しとして扱うため、thead は 1 行に保つ。
  test('ヘッダが変わったら新ヘッダは追加色、旧ヘッダは本文先頭の削除行になる', () => {
    const diff = wholeFileDiff(['-id,name', '+id,label', ' 1,a']);
    const doc = new DOMParser().parseFromString(buildCsvDiffTable(diff, ',')!.html, 'text/html');
    expect(doc.querySelectorAll('thead tr')).toHaveLength(1);
    expect(doc.querySelector('thead tr')!.className).toBe('diff-add');
    expect(doc.querySelector('thead tr')!.textContent).toBe('idlabel');
    expect(bodyRows(doc.body.innerHTML)[0]).toEqual({
      cls: 'diff-del',
      block: '0',
      text: 'id|name',
    });
  });

  test('TSV でも組める', () => {
    const diff = wholeFileDiff([' a\tb', '+1\t2']);
    expect(bodyRows(buildCsvDiffTable(diff, '\t')!.html)).toEqual([
      { cls: 'diff-add', block: '0', text: '1|2' },
    ]);
  });

  test('全文差分でない・壊れた差分では null(通常表示へ落とす)', () => {
    expect(buildCsvDiffTable('unified diff ではない', ',')).toBeNull();
    const partial = wholeFileDiff([' a', '+b']).replace('@@ -1,1 +1,2 @@', '@@ -5,1 +5,2 @@');
    expect(buildCsvDiffTable(partial, ',')).toBeNull();
  });

  test('削除のあとに続く追加は同じブロック、追加のあとの削除は別ブロック', () => {
    const lines = parseUnifiedDiff(wholeFileDiff([' h', '+a', '-b', ' c']))[0]!.hunks[0]!.lines;
    expect(orderCsvDiffRecords(lines, ranges(3), ranges(3)).map((r) => [r.type, r.block])).toEqual([
      ['context', null],
      ['add', 0],
      ['del', 1],
      ['context', null],
    ]);
  });
});

describe('レンダリング表示の CSV へ差分を重ねる', () => {
  const DIFF = wholeFileDiff([' a,b', '-1,2', '+1,3']);

  test('差分が届いていればテーブル表示のまま色分けされ、差分ジャンプの対象になる', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff(DIFF);
    main.setViewMode('rendered');
    await main.render('a,b\n1,3\n', 'csv', ',');

    expect(document.querySelector('#diagram-wrap table.diff-table')).toBeNull();
    expect(document.querySelectorAll('#diagram-wrap .csv-scroll table tr.diff-del')).toHaveLength(
      1,
    );
    expect(document.querySelectorAll('#diagram-wrap .csv-scroll table tr.diff-add')).toHaveLength(
      1,
    );
    expect(document.querySelectorAll('#diagram-wrap [data-diff-block="0"]')).toHaveLength(2);
  });

  // 表は差分の全文から組んであるため、追記すると行が二重になる。
  test('差分表示中はチャンクを DOM へ追記しない', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff(DIFF);
    main.setViewMode('rendered');
    await main.render('a,b\n', 'csv', ',');

    main.appendChunk('1,3\n', 'csv', ',');

    expect(document.querySelectorAll('#diagram-wrap tbody tr')).toHaveLength(2);
  });

  test('差分が無ければ通常のテーブル表示で、追記も続く', async () => {
    const { document, main } = loadViewerMain({});
    main.setViewMode('rendered');
    await main.render('a,b\n1,2\n', 'csv', ',');
    main.appendChunk('3,4\n', 'csv', ',');

    expect(document.querySelector('#diagram-wrap tr.diff-add')).toBeNull();
    expect(document.querySelectorAll('#diagram-wrap tbody tr')).toHaveLength(2);
  });

  test('描けない差分では通常のテーブル表示へ落ちる', async () => {
    const { document, main } = loadViewerMain({});
    main.setDiff('これは unified diff ではない\n');
    main.setViewMode('rendered');
    await main.render('a,b\n1,2\n', 'csv', ',');

    expect(document.querySelector('#diagram-wrap tr.diff-add')).toBeNull();
    expect(document.querySelector('#diagram-wrap tbody')!.textContent).toContain('2');
  });
});
