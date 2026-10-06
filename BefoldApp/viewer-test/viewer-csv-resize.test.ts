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
    expect(columnWidths(viewer)).toEqual(['110px', '100px', '40px']);
    viewer.main._mmdSetRenderDocPath('/b.csv');
    await viewer.main.render(CSV, 'csv', ',');
    expect(columnWidths(viewer)).toEqual([]);
  });

  // TASK-666: 保存（内容変更）のたびに手で調整した幅を失わない。
  test('同じパスの内容変更では列幅を保持し、列が減った分は捨て、増えた列は自然幅にする', async () => {
    const viewer = loadViewerMain();
    viewer.main._mmdSetRenderDocPath('/a.csv');
    await viewer.main.render(CSV + 'x,1,2\n', 'csv', ',');
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    await viewer.main.render(CSV + 'changed,9000\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['110px', '100px']);
    await viewer.main.render('Name\n日本語\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['110px']);
    // 戻った 2 列目は捨てた幅を復活させず自然幅から始まる（jsdom は layout が無く下限 40px）。
    await viewer.main.render(CSV, 'csv', ',');
    expect(columnWidths(viewer)).toEqual(['110px', '40px']);
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
      uiStrings: { csvResizeColumn: '列 {column} の幅を変更', csvResizeHint: '幅を変更' },
    });
    await viewer.main.render(CSV, 'csv', ',');
    const handle = tableIn(viewer).querySelector('.csv-resize-handle')!;
    expect(handle.getAttribute('aria-label')).toBe('列 1 の幅を変更');
    expect(handle.getAttribute('title')).toBe('幅を変更');
    await viewer.main.render('| A | B |\n|---|---|\n|1|2|', 'md');
    expect(viewer.document.querySelector('.csv-resize-handle')).toBeNull();
  });
});
