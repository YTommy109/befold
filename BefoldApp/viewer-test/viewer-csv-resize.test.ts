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

  test('表示モード切替とチャンク追記で保持し、文書切替・内容変更でリセットする', async () => {
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
    await viewer.main.render(CSV + 'changed,9000\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual([]);
    measureHeaders(tableIn(viewer));
    key(viewer, 0, 'ArrowRight');
    viewer.main._mmdSetRenderDocPath('/b.csv');
    await viewer.main.render(CSV + 'changed,9000\n', 'csv', ',');
    expect(columnWidths(viewer)).toEqual([]);
  });

  test('ズームを割り戻してドラッグし、表外での終了・再描画で捕捉を解除する', async () => {
    const viewer = loadViewerMain();
    await viewer.main.render(CSV, 'csv', ',');
    const table = tableIn(viewer);
    measureHeaders(table);
    viewer.main._mmdZoomIn();
    viewer.main._mmdZoomIn();
    const handle = table.querySelector<HTMLElement>('.csv-resize-handle')!;
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
    function pointer(type: string, clientX: number): void {
      const event = new viewer.window.MouseEvent(type, {
        clientX,
        button: 0,
        bubbles: true,
        cancelable: true,
      });
      Object.defineProperty(event, 'pointerId', { value: 7 });
      handle.dispatchEvent(event);
    }
    pointer('pointerdown', 100);
    pointer('pointermove', 250);
    expect(columnWidths(viewer)).toEqual(['200px', '100px']);
    expect(table.classList.contains('csv-resizing')).toBe(true);
    pointer('pointerup', 250);
    pointer('pointermove', 400);
    expect(columnWidths(viewer)).toEqual(['200px', '100px']);
    expect(captured).toBe(false);
    expect(table.classList.contains('csv-resizing')).toBe(false);
    pointer('pointerdown', 250);
    await viewer.main.render(CSV + 'changed,9000\n', 'csv', ',');
    expect(captured).toBe(false);
    expect(table.classList.contains('csv-resizing')).toBe(false);
    expect(columnWidths(viewer)).toEqual([]);
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
