import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, test } from '@jest/globals';

import { loadViewerMain, type LoadedViewer } from './support/viewerMainHarness.js';

const CSV = 'Name,Amount\n日本語,1200\n"two\nlines",2500\n';

function tableIn(viewer: LoadedViewer): HTMLTableElement {
  return viewer.document.querySelector<HTMLTableElement>('#diagram-wrap table')!;
}

// jsdom はレイアウトを持たない。幅とテキスト実測だけを差し替え、操作・描画経路は本番と同じ。
function measureHeaders(table: HTMLTableElement): void {
  Array.from(table.tHead!.rows[0]!.cells).forEach((cell, index) => {
    Object.defineProperty(cell, 'offsetWidth', {
      get: () =>
        Number((table.querySelectorAll('col')[index]?.style.width || '100').replace('px', '')),
      configurable: true,
    });
    cell.style.padding = '6px 12px';
    cell.style.font = 'normal bold 13px sans-serif';
  });
  Array.from(table.querySelectorAll('td')).forEach((cell) => {
    if (cell instanceof table.ownerDocument.defaultView!.HTMLElement) {
      cell.style.padding = '6px 12px';
      cell.style.font = 'normal normal 13px sans-serif';
    }
  });
}

// 初期幅の方針は本番の render 経由で検証し、jsdom に無い実測だけを置き換える。
// 文字幅 10px + セル内余白 24px として、分位点・上下限の差を観測できるようにする。
function measureCellText(viewer: LoadedViewer): void {
  Object.defineProperty(viewer.window.HTMLTableCellElement.prototype, 'offsetWidth', {
    get(this: HTMLTableCellElement) {
      return (this.textContent?.length ?? 0) * 10 + 24;
    },
    configurable: true,
  });
}

function key(viewer: LoadedViewer, index: number, value: string): void {
  const handle = tableIn(viewer).querySelectorAll('.csv-resize-handle')[index]!;
  handle.dispatchEvent(new viewer.window.KeyboardEvent('keydown', { key: value, bubbles: true }));
}

function columnWidths(viewer: LoadedViewer): string[] {
  return Array.from(tableIn(viewer).querySelectorAll('col'), (col) => col.style.width);
}

// ポインタ捕捉は jsdom に無いので、捕捉の有無だけ記録する差し替えを付ける。
function pointerOn(viewer: LoadedViewer, handle: HTMLElement) {
  let captured = false;
  Object.assign(handle, {
    setPointerCapture: () => {
      captured = true;
    },
    hasPointerCapture: () => captured,
    releasePointerCapture: () => {
      captured = false;
    },
  });
  return {
    captured: () => captured,
    fire(type: string, clientX: number): void {
      const event = new viewer.window.MouseEvent(type, {
        clientX,
        button: 0,
        bubbles: true,
        cancelable: true,
      });
      Object.defineProperty(event, 'pointerId', { value: 7 });
      handle.dispatchEvent(event);
    },
  };
}

const overlayIn = (viewer: LoadedViewer): Element | null =>
  viewer.document.querySelector('.csv-resize-overlay');
const guideIn = (viewer: LoadedViewer): HTMLElement | null =>
  viewer.document.querySelector<HTMLElement>('.csv-resize-guide');

describe('CSV/TSV の列幅', () => {
  test('列幅はパス注釈の後に測り、全文を二度レイアウトしない', async () => {
    const viewer = loadViewerMain();
    const annotatedAtMeasurement: number[] = [];
    Object.defineProperty(viewer.window.HTMLTableCellElement.prototype, 'offsetWidth', {
      get() {
        annotatedAtMeasurement.push(tableIn(viewer).querySelectorAll('.befold-path-ref').length);
        return 120;
      },
      configurable: true,
    });
    await viewer.main.render('Path,Count\nsrc/app.ts,1\n', 'csv', ',');
    expect(annotatedAtMeasurement).toEqual([1, 1, 1, 1]);
  });

  test('ハンドルを追加する前に全列の自然幅を測り、列ごとの再レイアウトを避ける', async () => {
    const viewer = loadViewerMain();
    const handleCountsAtMeasurement: number[] = [];
    Object.defineProperty(viewer.window.HTMLTableCellElement.prototype, 'offsetWidth', {
      get() {
        handleCountsAtMeasurement.push(
          viewer.document.querySelectorAll('.csv-resize-handle').length,
        );
        return 120;
      },
      configurable: true,
    });
    await viewer.main.render('A,B,C\n1,2,3\n', 'csv', ',');
    expect(handleCountsAtMeasurement).toEqual([0, 0, 0, 0, 0, 0]);
    expect(
      Array.from(tableIn(viewer).querySelectorAll('.csv-resize-handle'), (handle) =>
        handle.getAttribute('aria-valuenow'),
      ),
    ).toEqual(['120', '120', '120']);
    handleCountsAtMeasurement.length = 0;
    viewer.main.appendChunk('4,5,6\n', 'csv', ',');
    expect(handleCountsAtMeasurement).toEqual([]);
    viewer.main.appendChunk('7,8,9,10\n', 'csv', ',');
    expect(handleCountsAtMeasurement).toEqual([3, 3]);
  });

  test.each([',', '\t'])(
    '左右キーは対象列だけを変更し、40px 未満にはしない (%s)',
    async (delimiter) => {
      const viewer = loadViewerMain();
      await viewer.main.render(CSV.replaceAll(',', delimiter), 'csv', delimiter);
      measureHeaders(tableIn(viewer));
      key(viewer, 0, 'ArrowRight');
      expect(columnWidths(viewer)).toEqual(['110px', '100px']);
      for (let i = 0; i < 20; i++) key(viewer, 0, 'ArrowLeft');
      expect(columnWidths(viewer)).toEqual(['40px', '100px']);
      expect(
        tableIn(viewer).querySelector('.csv-resize-handle')!.getAttribute('aria-valuenow'),
      ).toBe('40');
    },
  );

  test('表示モード切替とチャンク追記で保持し、文書切替でリセットする', async () => {
    const viewer = loadViewerMain();
    viewer.main._mmdSetRenderDocPath('/a.csv');
    await viewer.main.render(CSV, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    viewer.main.setViewMode('source');
    await viewer.main.render(CSV, 'csv', ',');
    viewer.main.appendChunk('new,3000,extra\n', 'csv', ',');
    viewer.main.setViewMode('rendered');
    await viewer.main.render(CSV + 'new,3000,extra\n', 'csv', ',');
    // 手動の 1 列目だけ保持する。残りは測り直す（jsdom は layout が無く下限 40px）。
    expect(columnWidths(viewer)).toEqual(['110px', '40px', '40px']);
    viewer.main._mmdSetRenderDocPath('/b.csv');
    await viewer.main.render(CSV, 'csv', ',');
    expect(columnWidths(viewer)).toEqual([]);
  });

  // TASK-666: 保存（内容変更）のたびに手で調整した幅を失わない。
  test('同じパスの内容変更では手動の幅を保持し、列が減った分は捨て、残りは測り直す', async () => {
    const viewer = loadViewerMain();
    viewer.main._mmdSetRenderDocPath('/a.csv');
    await viewer.main.render(CSV + 'x,1,2\n', 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 1, 'ArrowRight');
    await viewer.main.render(CSV + 'changed,9000\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['40px', '110px']);
    await viewer.main.render('Name\n日本語\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['40px']);
    // 消えた列の手動の幅は復活しない。手動の幅が残らないので、測れない jsdom では幅が付かない。
    await viewer.main.render(CSV, 'csv', ',');
    expect(columnWidths(viewer)).toEqual([]);
  });

  test('文書のパスが不明（null）の再描画は別文書として列幅を捨てる', async () => {
    const viewer = loadViewerMain();
    await viewer.main.render(CSV, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    await viewer.main.render(CSV, 'csv', ',');
    expect(columnWidths(viewer)).toEqual([]);
  });

  // 行数がしきい値（2,000）を超える CSV。
  const BIG_CSV = 'Name,Amount\n' + 'a,1\n'.repeat(2001);

  test('ズームを割り戻してドラッグし、表外での終了・再描画で捕捉を解除する', async () => {
    const viewer = loadViewerMain();
    await viewer.main.render(CSV, 'csv', ',');
    const table = tableIn(viewer);
    measureHeaders(table);
    viewer.main._mmdZoomIn();
    viewer.main._mmdZoomIn();
    const drag = pointerOn(viewer, table.querySelector<HTMLElement>('.csv-resize-handle')!);
    drag.fire('pointerdown', 100);
    drag.fire('pointermove', 250);
    expect(columnWidths(viewer)).toEqual(['200px', '100px']);
    expect(overlayIn(viewer)).not.toBeNull();
    drag.fire('pointerup', 250);
    drag.fire('pointermove', 400);
    expect(columnWidths(viewer)).toEqual(['200px', '100px']);
    expect(drag.captured()).toBe(false);
    expect(overlayIn(viewer)).toBeNull();
    drag.fire('pointerdown', 250);
    await viewer.main.render(CSV + 'changed,9000\n', 'csv', ',');
    expect(drag.captured()).toBe(false);
    expect(overlayIn(viewer)).toBeNull();
    expect(columnWidths(viewer)).toEqual([]);
  });

  // TASK-669: 継承プロパティ（cursor・user-select）を表へ切り替えると全セルが再計算され、
  // 幅変更 1 回分かかる。カーソルと選択の抑止は表の外のオーバーレイだけで行う。
  test('ドラッグ中は表のクラスを変えず、全面オーバーレイでカーソルと選択を抑える。小さい表は案内線なしでライブ更新する', async () => {
    const viewer = loadViewerMain();
    await viewer.main.render(CSV, 'csv', ',');
    const table = tableIn(viewer);
    measureHeaders(table);
    const before = table.className;
    const drag = pointerOn(viewer, table.querySelector<HTMLElement>('.csv-resize-handle')!);
    drag.fire('pointerdown', 100);
    expect(table.className).toBe(before);
    expect(overlayIn(viewer)?.parentElement).toBe(viewer.document.body);
    expect(guideIn(viewer)).toBeNull();
    drag.fire('pointermove', 130);
    expect(columnWidths(viewer)).toEqual(['130px', '100px']);
    drag.fire('pointerup', 130);
    expect(table.className).toBe('csv-sized');
    expect(overlayIn(viewer)).toBeNull();
  });

  describe('行数の多い表（案内線）', () => {
    async function bigDrag(viewer: LoadedViewer) {
      await viewer.main.render(BIG_CSV, 'csv', ',');
      const table = tableIn(viewer);
      measureHeaders(table);
      return pointerOn(viewer, table.querySelector<HTMLElement>('.csv-resize-handle')!);
    }

    test('ドラッグ中は幅を更新せず案内線だけ動かし、離したときに 1 回だけ確定する', async () => {
      const viewer = loadViewerMain();
      const drag = await bigDrag(viewer);
      const before = tableIn(viewer).className;
      drag.fire('pointerdown', 100);
      expect(guideIn(viewer)!.style.left).toBe('100px');
      drag.fire('pointermove', 160);
      drag.fire('pointermove', 180);
      expect(guideIn(viewer)!.style.left).toBe('180px');
      expect(columnWidths(viewer)).toEqual([]);
      expect(tableIn(viewer).className).toBe(before);
      drag.fire('pointerup', 180);
      expect(columnWidths(viewer)).toEqual(['180px', '100px']);
      expect(overlayIn(viewer)).toBeNull();
    });

    test('ズームを割り戻し、下限（40px）では案内線も確定幅も同じ位置で止まる', async () => {
      const viewer = loadViewerMain();
      const drag = await bigDrag(viewer);
      drag.fire('pointerdown', 100);
      drag.fire('pointermove', -500);
      expect(guideIn(viewer)!.style.left).toBe('40px');
      drag.fire('pointerup', -500);
      expect(columnWidths(viewer)).toEqual(['40px', '100px']);
    });

    test('動かさずに離しただけでは幅も表のレイアウトも変えない', async () => {
      const viewer = loadViewerMain();
      const drag = await bigDrag(viewer);
      drag.fire('pointerdown', 100);
      drag.fire('pointerup', 100);
      expect(columnWidths(viewer)).toEqual([]);
      expect(tableIn(viewer).classList.contains('csv-sized')).toBe(false);
    });

    test('取り消し（pointercancel・捕捉の喪失・再描画）では確定せず、オーバーレイを残さない', async () => {
      const viewer = loadViewerMain();
      const drag = await bigDrag(viewer);
      drag.fire('pointerdown', 100);
      drag.fire('pointermove', 160);
      drag.fire('pointercancel', 160);
      expect(columnWidths(viewer)).toEqual([]);
      expect(overlayIn(viewer)).toBeNull();
      drag.fire('pointerdown', 100);
      drag.fire('pointermove', 160);
      drag.fire('lostpointercapture', 160);
      expect(columnWidths(viewer)).toEqual([]);
      expect(overlayIn(viewer)).toBeNull();
      drag.fire('pointerdown', 100);
      drag.fire('pointermove', 160);
      await viewer.main.render(BIG_CSV + 'changed,9000\n', 'csv', ',');
      expect(overlayIn(viewer)).toBeNull();
      expect(columnWidths(viewer)).toEqual([]);
    });
  });

  test('追加の列にもハンドルを作り、既存の幅を保持する', async () => {
    const viewer = loadViewerMain();
    await viewer.main.render(CSV, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    viewer.main.appendChunk('new,3000,extra\n', 'csv', ',');
    expect(tableIn(viewer).querySelectorAll('.csv-resize-handle')).toHaveLength(3);
    expect(columnWidths(viewer)).toEqual(['110px', '100px', '40px']);
  });

  test('auto-fit は全読み込み済み行を測り、明示的改行と書式を考慮する', async () => {
    const viewer = loadViewerMain();
    const measured: string[] = [];
    // jsdom にはレイアウトがないため、測定用セルの自然幅だけを差し替える。
    Object.defineProperty(viewer.window.HTMLTableElement.prototype, 'offsetWidth', {
      get(this: HTMLTableElement) {
        const lines = Array.from(this.rows, (row) => row.cells[0]!.textContent!.split('\n')).flat();
        measured.push(...lines);
        return Math.max(...lines.map((line) => line.length * 10 + 26));
      },
      configurable: true,
    });
    await viewer.main.render(CSV, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 1, 'Enter');
    expect(measured).toContain('1,200');
    expect(columnWidths(viewer)[1]).toBe('86px');
    viewer.main.appendChunk('a much longer offscreen value,9000\n', 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'Enter');
    expect(measured).toContain('a much longer offscreen value');
    expect(measured).toContain('two');
    expect(measured).toContain('lines');
    expect(columnWidths(viewer)[0]).toBe('316px');
    const widths = columnWidths(viewer);
    tableIn(viewer)
      .querySelector('.csv-resize-handle')!
      .dispatchEvent(new viewer.window.MouseEvent('dblclick', { bubbles: true }));
    expect(columnWidths(viewer)).toEqual(widths);
    expect(viewer.document.querySelector('table[aria-hidden]')).toBeNull();
  });

  // TASK-668: 測定表の行数を固定し、行数に比例して遅くならないようにする。
  test('auto-fit は行数が多くても測定表を一定の行数に抑え、最長の行（全角は 2 倍）を落とさない', async () => {
    const viewer = loadViewerMain();
    const probes: string[][] = [];
    Object.defineProperty(viewer.window.HTMLTableElement.prototype, 'offsetWidth', {
      get(this: HTMLTableElement) {
        probes.push(Array.from(this.rows, (row) => row.cells[0]!.textContent!));
        return 100;
      },
      configurable: true,
    });
    // 表示長 120。半角 100 文字より長い
    const wide = '幅'.repeat(60);
    const latin = 'x'.repeat(100);
    const rows = Array.from({ length: 3000 }, (_, i) => `row${i},${i}`);
    rows[1700] = `${wide},1`;
    rows[2500] = `${latin},1`;
    await viewer.main.render(`Name,Amount\n${rows.join('\n')}\n`, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'Enter');
    const probe = probes.at(-1)!;
    expect(probe.length).toBeLessThanOrEqual(201);
    expect(probe).toContain('Name');
    expect(probe).toContain(wide);
    expect(probe).toContain(latin);
  });

  // TASK-667: Tab で止まるハンドルは表全体で 1 つ。Alt+左右で隣の列へ移る。
  describe('キーボード操作', () => {
    function handles(viewer: LoadedViewer): HTMLElement[] {
      return Array.from(tableIn(viewer).querySelectorAll<HTMLElement>('.csv-resize-handle'));
    }
    function tabbable(viewer: LoadedViewer): number[] {
      return handles(viewer).flatMap((handle, index) => (handle.tabIndex === 0 ? [index] : []));
    }

    test('Tab で止まるハンドルは 1 つで、フォーカスした列に移る。追記で増えた列は止まらない', async () => {
      const viewer = loadViewerMain();
      await viewer.main.render(CSV, 'csv', ',');
      expect(tabbable(viewer)).toEqual([0]);
      handles(viewer)[1]!.focus();
      expect(tabbable(viewer)).toEqual([1]);
      viewer.main.appendChunk('new,3000,extra\n', 'csv', ',');
      expect(handles(viewer)).toHaveLength(3);
      expect(tabbable(viewer)).toEqual([1]);
    });

    test('Alt+左右は隣の列のハンドルへフォーカスを移し、幅は変えない。端では動かない', async () => {
      const viewer = loadViewerMain();
      await viewer.main.render(CSV, 'csv', ',');
      measureHeaders(tableIn(viewer));
      handles(viewer)[0]!.focus();
      const press = (index: number, keyName: string): void => {
        handles(viewer)[index]!.dispatchEvent(
          new viewer.window.KeyboardEvent('keydown', {
            key: keyName,
            altKey: true,
            bubbles: true,
          }),
        );
      };
      press(0, 'ArrowLeft');
      expect(viewer.document.activeElement).toBe(handles(viewer)[0]);
      press(0, 'ArrowRight');
      expect(viewer.document.activeElement).toBe(handles(viewer)[1]);
      expect(tabbable(viewer)).toEqual([1]);
      press(1, 'ArrowRight');
      expect(viewer.document.activeElement).toBe(handles(viewer)[1]);
      expect(columnWidths(viewer)).toEqual([]);
    });
  });

  test('ラベルを注入し、Markdown 表にはハンドルを付けない', async () => {
    const viewer = loadViewerMain({
      uiStrings: {
        csvResizeColumn: '列 {column} の幅を変更',
        csvResizeHint: '幅を変更',
        csvScrollHorizontally: '表を横方向にスクロール',
      },
    });
    await viewer.main.render(CSV, 'csv', ',');
    const handle = tableIn(viewer).querySelector('.csv-resize-handle')!;
    expect(handle.getAttribute('aria-label')).toBe('列 1 の幅を変更');
    expect(handle.getAttribute('title')).toBe('幅を変更');
    expect(
      viewer.document.querySelector('.csv-viewport-scrollbar')!.getAttribute('aria-label'),
    ).toBe('表を横方向にスクロール');
    await viewer.main.render('| A | B |\n|---|---|\n|1|2|', 'md');
    expect(viewer.document.querySelector('.csv-resize-handle')).toBeNull();
  });
});

test('初期幅は中央値や最大値ではなく 90 パーセンタイルを使い、追記時も手動調整を保持する', async () => {
  const viewer = loadViewerMain();
  measureCellText(viewer);
  viewer.main._mmdSetRenderDocPath('/sizing.csv');
  await viewer.main.render(
    'Code,Description\n' +
      [100, 20, 12, 19, 13, 18, 14, 17, 15, 16]
        .map((length) => 'AB,' + 'x'.repeat(length))
        .join('\n'),
    'csv',
    ',',
  );
  // 12〜20 文字と外れ値 100 文字。90% 点は 20 文字で、中央値でも最大値でもない。
  expect(columnWidths(viewer)).toEqual(['64px', '224px']);
  measureHeaders(tableIn(viewer));
  key(viewer, 1, 'ArrowRight');
  viewer.main.appendChunk('CD,' + 'y'.repeat(200) + '\n', 'csv', ',');
  expect(columnWidths(viewer)).toEqual(['64px', '234px']);
  viewer.main._mmdSetRenderDocPath('/wide.tsv');
  await viewer.main.render('A\tB\n' + 'z'.repeat(100) + '\t1', 'csv', '\t');
  expect(columnWidths(viewer)).toEqual(['360px', '40px']);
});

describe('全列が表示領域に収まる表', () => {
  // jsdom はレイアウトを持たないので、.csv-scroll の幅と余白だけを本番の形で与える。
  function withContentWidth(viewer: LoadedViewer, contentWidth: number): void {
    const padding = 32;
    const style = viewer.document.createElement('style');
    style.textContent = `.csv-scroll { padding-right: ${padding}px; }`;
    viewer.document.head.append(style);
    Object.defineProperty(viewer.window.HTMLDivElement.prototype, 'clientWidth', {
      get: () => contentWidth + padding,
      configurable: true,
    });
    measureCellText(viewer);
  }
  const isNaturalLayout = (viewer: LoadedViewer): boolean =>
    columnWidths(viewer).length === 0 && !tableIn(viewer).classList.contains('csv-sized');
  // 列幅は 1 文字 10px + 余白 24px（measureCellText）。Code が 64px、60 文字の値が 624px。
  const NARROW = `Code,Description\nAB,${'x'.repeat(60)}\n`;
  const NARROW_TOTAL = 64 + 624 + 1;

  test('合計が内容幅ちょうどなら幅を設定せず、上限 360px も分位点も適用しない', async () => {
    const viewer = loadViewerMain();
    withContentWidth(viewer, NARROW_TOTAL);
    await viewer.main.render(NARROW, 'csv', ',');
    expect(isNaturalLayout(viewer)).toBe(true);
  });

  test('内容幅を 1px でも超えれば、従来の初期幅を設定する', async () => {
    const viewer = loadViewerMain();
    withContentWidth(viewer, NARROW_TOTAL - 1);
    await viewer.main.render(NARROW, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['64px', '360px']);
    expect(tableIn(viewer).classList.contains('csv-sized')).toBe(true);
  });

  test('判定は分位点ではなく最大幅で行い、外れ値が収まらなければ切り取る側へ倒す', async () => {
    const viewer = loadViewerMain();
    withContentWidth(viewer, 500);
    const rows = [100, 20, 12, 19, 13, 18, 14, 17, 15, 16].map((n) => 'AB,' + 'x'.repeat(n));
    await viewer.main.render('Code,Description\n' + rows.join('\n'), 'csv', ',');
    // 90% 点の 224px なら収まるが、最大の 1024px は収まらない。
    expect(columnWidths(viewer)).toEqual(['64px', '224px']);
  });

  test('追記しても収まる間は切り取らず、列が増えて収まらなくなると全列に幅を設定する', async () => {
    const viewer = loadViewerMain();
    withContentWidth(viewer, NARROW_TOTAL);
    await viewer.main.render(NARROW, 'csv', ',');
    viewer.main.appendChunk(`CD,${'y'.repeat(60)}\n`, 'csv', ',');
    expect(isNaturalLayout(viewer)).toBe(true);
    viewer.main.appendChunk('EF,z,extra\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['64px', '360px', '74px']);
  });

  test('自動レイアウトの表でも手動で幅を変えられ、以後の再描画で保持する', async () => {
    const viewer = loadViewerMain();
    withContentWidth(viewer, NARROW_TOTAL);
    viewer.main._mmdSetRenderDocPath('/narrow.csv');
    await viewer.main.render(NARROW, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    expect(columnWidths(viewer)).toEqual(['110px', '100px']);
    // 手動の 110px を含めると 110 + 624 + 1 = 735px で、689px に収まらない。
    await viewer.main.render(NARROW, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['110px', '360px']);
  });

  test('手動の幅を含めても収まるなら、残りの列は上限をかけず最大幅にする', async () => {
    const viewer = loadViewerMain();
    withContentWidth(viewer, 110 + 624 + 1);
    viewer.main._mmdSetRenderDocPath('/narrow.csv');
    await viewer.main.render(NARROW, 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    await viewer.main.render(NARROW, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['110px', '624px']);
  });
});

describe('再描画での列幅の測り直し', () => {
  const widthsAfter = async (first: string, second: string): Promise<string[]> => {
    const viewer = loadViewerMain();
    measureCellText(viewer);
    viewer.main._mmdSetRenderDocPath('/live.csv');
    await viewer.main.render(first, 'csv', ',');
    await viewer.main.render(second, 'csv', ',');
    return columnWidths(viewer);
  };

  test('保存で値が長くなると、手動で変えていない列は広がる', async () => {
    const widths = await widthsAfter('Name,Note\nab,cd\n', `Name,Note\n${'x'.repeat(20)},cd\n`);
    expect(widths).toEqual(['224px', '64px']);
  });

  test('ヘッダーだけの CSV に行が増えると、値に合わせて広がる', async () => {
    const widths = await widthsAfter('Name,Note\n', `Name,Note\n${'x'.repeat(20)},cd\n`);
    expect(widths).toEqual(['224px', '64px']);
  });

  test('桁区切りの設定を変えると、数値の列は新しい表示に合わせて広がる', async () => {
    const viewer = loadViewerMain();
    measureCellText(viewer);
    viewer.main._mmdSetRenderDocPath('/number.csv');
    viewer.window._mmdCsvGrouping = false;
    viewer.main._mmdInitCsvNumberFormat();
    await viewer.main.render('Name,N\nx,1234567890\n', 'csv', ',');
    expect(columnWidths(viewer)[1]).toBe('124px');
    viewer.window._mmdCsvGrouping = true;
    viewer.main._mmdInitCsvNumberFormat();
    await new Promise((resolve) => {
      setTimeout(resolve, 0);
    });
    expect(columnWidths(viewer)[1]).toBe('154px');
  });

  test('チャンク追記では自動の幅も手動の幅も動かさない', async () => {
    const viewer = loadViewerMain();
    measureCellText(viewer);
    viewer.main._mmdSetRenderDocPath('/chunk.csv');
    await viewer.main.render('Name,Note\nab,cd\n', 'csv', ',');
    viewer.main.appendChunk(`${'x'.repeat(20)},${'y'.repeat(20)}\n`, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['64px', '64px']);
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    viewer.main.appendChunk(`${'x'.repeat(30)},z\n`, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['74px', '64px']);
  });

  test('初回の測定中だけ本体の表を隠し、追記では隠さない（読んでいる位置を失わないため）', async () => {
    const viewer = loadViewerMain();
    const displays: string[] = [];
    Object.defineProperty(viewer.window.HTMLTableCellElement.prototype, 'offsetWidth', {
      get() {
        displays.push(tableIn(viewer).style.display);
        return 100;
      },
      configurable: true,
    });
    await viewer.main.render('Name\nab\n', 'csv', ',');
    expect(displays[0]).toBe('none');
    expect(tableIn(viewer).style.display).toBe('');
    displays.length = 0;
    viewer.main.appendChunk('cd,new\n', 'csv', ',');
    expect(displays.length).toBeGreaterThan(0);
    expect(displays.every((display) => display === '')).toBe(true);
  });

  test('手動で変えた列の幅は、別のパスへ移ると捨てる', async () => {
    const viewer = loadViewerMain();
    measureCellText(viewer);
    viewer.main._mmdSetRenderDocPath('/a.csv');
    await viewer.main.render('Name,Note\nab,cd\n', 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    viewer.main._mmdSetRenderDocPath('/b.csv');
    await viewer.main.render('Name,Note\nab,cd\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['64px', '64px']);
  });
});

describe('切り取りと数値', () => {
  test('数値の列は分位点ではなく標本の最大幅を使い、上限 360px も適用しない', async () => {
    const viewer = loadViewerMain();
    measureCellText(viewer);
    const small = Array.from({ length: 9 }, (_, index) => `${index + 1}`);
    const rows = [...small, '1234567890'].map((amount) => `x,${amount}`).join('\n');
    await viewer.main.render(`Name,Amount\n${rows}\n`, 'csv', ',');
    // 90% 点は 1 文字（ヘッダーの 84px が勝つ）だが、最大の 1,234,567,890（13 文字）に合わせる。
    expect(columnWidths(viewer)[1]).toBe('154px');
    const huge = '1'.repeat(50);
    viewer.main._mmdSetRenderDocPath('/huge.csv');
    await viewer.main.render(`Name,Amount\nx,1\ny,${huge}\n`, 'csv', ',');
    // 50 桁 + 桁区切り 16 個で 66 文字。上限 360px を超えても桁を欠かさない。
    expect(columnWidths(viewer)[1]).toBe('684px');
  });

  test('文字列の列は従来どおり 90 パーセンタイルと上限 360px のまま', async () => {
    const viewer = loadViewerMain();
    measureCellText(viewer);
    const rows = [100, 20, 12, 19, 13, 18, 14, 17, 15, 16].map((n) => 'a'.repeat(n)).join('\n');
    await viewer.main.render(`Text\n${rows}\n`, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['224px']);
  });

  test('style.css は切り取ったセルに省略記号を付ける', () => {
    const css = readFileSync(join(__dirname, '..', 'BefoldKit', 'Resources', 'style.css'), 'utf8');
    expect(css).toMatch(/table\.csv-sized td \{[^}]*text-overflow: ellipsis/u);
  });

  // @media print は jsdom で適用されない。実際の PDF での確認は TASK-906.4 の Notes を参照。
  test('style.css は印刷時に列幅と切り取りを解除する', () => {
    const css = readFileSync(join(__dirname, '..', 'BefoldKit', 'Resources', 'style.css'), 'utf8');
    const print = css.slice(css.indexOf('@media print'));
    expect(print).toMatch(/table\.csv-sized \{[^}]*table-layout: auto[^}]*width: auto !important/u);
    expect(print).toMatch(/table\.csv-sized col \{[^}]*width: auto !important/u);
    expect(print).toMatch(
      /table\.csv-sized td \{[^}]*white-space: pre-line[^}]*overflow: visible/u,
    );
  });
});

test('追記で増えた列は、201 行目以降でも追記された行の値で測る', async () => {
  const viewer = loadViewerMain();
  measureCellText(viewer);
  const rows = Array.from({ length: 250 }, (_, index) => `a${index},b`).join('\n');
  await viewer.main.render(`Name,Note\n${rows}\n`, 'csv', ',');
  viewer.main.appendChunk(`c,d,${'x'.repeat(20)}\n`, 'csv', ',');
  // 古い行にこの列のセルは無い。追記された 20 文字の値（224px）で測る。
  expect(columnWidths(viewer)[2]).toBe('224px');
});

test('初期幅の分位点から空セルと空白だけのセルを除外する', async () => {
  const viewer = loadViewerMain();
  measureCellText(viewer);
  const rows = Array.from({ length: 90 }, (_, index) => `${index % 2 === 0 ? '' : '   '},${index}`);
  rows.push(...Array.from({ length: 10 }, (_, index) => `${'x'.repeat(12 + index)},${90 + index}`));
  await viewer.main.render(`Value,Row\n${rows.join('\n')}\n`, 'csv', ',');
  // 非空セル 10 個の 90% 点は 20 文字。空白を含めるとヘッダー幅まで縮んでしまう。
  expect(columnWidths(viewer)[0]).toBe('224px');
});

test('初期幅はヘッダーより狭くせず、ヘッダー自体にも 360px の上限を適用する', async () => {
  const viewer = loadViewerMain();
  measureCellText(viewer);
  await viewer.main.render(`${'H'.repeat(40)},Header,A\nx,x,x\n`, 'csv', ',');
  expect(columnWidths(viewer)).toEqual(['360px', '84px', '40px']);
});

test('初期幅の標本は空セルを含む先頭 200 データ行で、200 行目は含め 201 行目は含めない', async () => {
  const viewer = loadViewerMain();
  measureCellText(viewer);
  const rows = Array.from({ length: 199 }, (_, index) => `,${index + 1}`);
  rows.push(`${'x'.repeat(20)},200`, `${'x'.repeat(100)},201`);
  await viewer.main.render(`Value,Row\n${rows.join('\n')}\n`, 'csv', ',');
  // 200 行目を落とすとヘッダー幅、201 行目まで含めると上限 360px になる。
  expect(columnWidths(viewer)[0]).toBe('224px');
});

test('横スクロールバーは幅超過時に表示され、双方向に同期し、モード切替で解除される', async () => {
  const viewer = loadViewerMain();
  await viewer.main.render(CSV, 'csv', ',');
  const scroller = viewer.document.querySelector<HTMLElement>('.csv-scroll')!;
  const bar = viewer.document.querySelector<HTMLElement>('.csv-viewport-scrollbar')!;
  expect(bar.getAttribute('aria-label')).toBe('Scroll table horizontally');
  Object.defineProperties(scroller, {
    scrollWidth: { value: 1400, configurable: true },
    clientWidth: { value: 600 },
  });
  viewer.document.querySelector<HTMLElement>('.viewer')!.getBoundingClientRect = () =>
    ({ bottom: 768 }) as DOMRect;
  scroller.getBoundingClientRect = () =>
    ({ left: 20, right: 620, top: 0, bottom: 5000 }) as DOMRect;
  viewer.window.dispatchEvent(new viewer.window.Event('resize'));
  expect(bar.hidden).toBe(false);
  scroller.scrollLeft = 300;
  scroller.dispatchEvent(new viewer.window.Event('scroll'));
  expect(bar.scrollLeft).toBe(300);
  bar.scrollLeft = 700;
  bar.dispatchEvent(new viewer.window.Event('scroll'));
  expect(scroller.scrollLeft).toBe(700);
  Object.defineProperty(scroller, 'scrollWidth', { value: 600 });
  viewer.window.dispatchEvent(new viewer.window.Event('resize'));
  expect(bar.hidden).toBe(true);
  viewer.main.setViewMode('source');
  await viewer.main.render(CSV, 'csv', ',');
  expect(viewer.document.querySelector('.csv-viewport-scrollbar')).toBeNull();
});

test('横スクロールバーは追加読み込みバナーの表示・高さ変更・非表示に追従する', async () => {
  const viewer = loadViewerMain();
  const observers: TestResizeObserver[] = [];
  class TestResizeObserver implements ResizeObserver {
    readonly targets = new Set<Element>();
    disconnected = false;
    constructor(private readonly callback: ResizeObserverCallback) {
      observers.push(this);
    }
    observe(target: Element): void {
      this.targets.add(target);
    }
    unobserve(target: Element): void {
      this.targets.delete(target);
    }
    disconnect(): void {
      this.disconnected = true;
      this.targets.clear();
    }
    notify(): void {
      this.callback([], this);
    }
  }
  Object.defineProperty(viewer.window, 'ResizeObserver', { value: TestResizeObserver });
  await viewer.main.render(CSV, 'csv', ',');
  const scroller = viewer.document.querySelector<HTMLElement>('.csv-scroll')!;
  const bar = viewer.document.querySelector<HTMLElement>('.csv-viewport-scrollbar')!;
  const banner = viewer.document.getElementById('mmd-truncated-banner')!;
  const viewportHeight = viewer.window.innerHeight;
  let bannerHeight = 32;
  Object.defineProperties(scroller, {
    scrollWidth: { value: 1400 },
    clientWidth: { value: 600 },
  });
  viewer.document.querySelector<HTMLElement>('.viewer')!.getBoundingClientRect = () =>
    new viewer.window.DOMRect(0, 0, 1024, viewportHeight);
  scroller.getBoundingClientRect = () => new viewer.window.DOMRect(20, 0, 600, 5000);
  banner.getBoundingClientRect = () => {
    const height = banner.style.display === 'none' ? 0 : bannerHeight;
    return new viewer.window.DOMRect(0, viewportHeight - height, 1024, height);
  };
  const observer = observers.find((candidate) => candidate.targets.has(scroller))!;
  expect(observer.targets.has(banner)).toBe(true);
  observer.notify();
  expect(bar.hidden).toBe(false);
  expect(bar.style.bottom).toBe('0px');

  viewer.main._mmdSetTruncated(true, 1000, false);
  observer.notify();
  expect(bar.hidden).toBe(false);
  expect(viewportHeight - Number(bar.style.bottom.replace('px', ''))).toBe(
    banner.getBoundingClientRect().top,
  );
  expect(bar.style.bottom).toBe('32px');

  bannerHeight = 64;
  observer.notify();
  expect(bar.style.bottom).toBe('64px');
  viewer.main._mmdSetTruncated(false, 1000, false);
  observer.notify();
  expect(bar.style.bottom).toBe('0px');

  await viewer.main.render('# Another document', 'md');
  expect(observer.disconnected).toBe(true);
  expect(observer.targets.size).toBe(0);
  expect(viewer.document.querySelector('.csv-viewport-scrollbar')).toBeNull();
});
