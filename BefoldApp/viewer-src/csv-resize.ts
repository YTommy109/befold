// CSV/TSV の列幅は表示中の文書だけで保持する。保存や原文の変更はしない。
import { _mmdZoom } from './zoom.js';

var MIN_WIDTH = 40;
var widths: number[] = [];
var path: string | null = null;
var cancelDrag: (() => void) | undefined;

function prepareCsvResize(newPath: string | null, sameContent: boolean): void {
  cancelDrag?.();
  if (path !== newPath || !sameContent) widths = [];
  path = newPath;
}

function applyWidths(table: HTMLTableElement): void {
  if (widths.length === 0) return;
  var headers = table.tHead!.rows[0]!.cells;
  var group = table.querySelector('colgroup');
  if (!group) {
    group = document.createElement('colgroup');
    table.prepend(group);
  }
  while (group.children.length < headers.length) group.append(document.createElement('col'));
  for (var i = 0; i < headers.length; i++) {
    if (widths[i] === undefined) widths[i] = Math.max(MIN_WIDTH, headers[i]!.offsetWidth);
    var col = group.children[i];
    if (col instanceof HTMLElement) col.style.width = widths[i] + 'px';
    headers[i]!.querySelector('.csv-resize-handle')?.setAttribute(
      'aria-valuenow',
      String(Math.round(widths[i]!)),
    );
  }
  table.classList.add('csv-sized');
  // border-collapse の外枠 1px を列幅から差し引かせない。
  table.style.width = widths.reduce((sum, width) => sum + width, 1) + 'px';
}

function setWidth(table: HTMLTableElement, index: number, width: number): void {
  if (widths.length === 0)
    widths = Array.from(table.tHead!.rows[0]!.cells, (cell) =>
      Math.max(MIN_WIDTH, cell.offsetWidth),
    );
  widths[index] = Math.max(MIN_WIDTH, width);
  applyWidths(table);
}

// DOM の表示文言を測るので桁区切り・負数表記も含む。画面外の読み込み済み行も対象。
function fitColumn(table: HTMLTableElement, index: number): void {
  // セルを同じ CSS の下で折り返さず測る。WebKit の font shorthand や
  // tabular-nums を canvas に転写せず、実際の書式と明示的改行をそのまま使う。
  var probe = table.cloneNode(false);
  if (!(probe instanceof HTMLTableElement)) return;
  probe.classList.remove('csv-sized');
  probe.setAttribute('aria-hidden', 'true');
  probe.style.cssText =
    'position:absolute;visibility:hidden;display:table;table-layout:auto;width:max-content;padding-right:0;pointer-events:none';
  for (var row of table.rows) {
    var cell = row.cells[index];
    if (!cell) continue;
    var copy = cell.cloneNode(true);
    if (!(copy instanceof HTMLTableCellElement)) continue;
    copy.querySelector('.csv-resize-handle')?.remove();
    copy.style.whiteSpace = 'pre';
    probe.insertRow().append(copy);
  }
  table.parentElement!.append(probe);
  var width = probe.offsetWidth || MIN_WIDTH;
  probe.remove();
  setWidth(table, index, width);
}

function installCsvResize(table: HTMLTableElement): void {
  var headers = table.tHead?.rows[0]?.cells;
  if (!headers) return;
  var strings = window._mmdUIStrings || {};
  Array.from(headers).forEach(function (header, index) {
    if (header.querySelector('.csv-resize-handle')) return;
    var handle = document.createElement('span');
    handle.className = 'csv-resize-handle';
    handle.tabIndex = 0;
    handle.setAttribute('role', 'separator');
    handle.setAttribute('aria-orientation', 'vertical');
    handle.setAttribute('aria-valuemin', String(MIN_WIDTH));
    handle.setAttribute('aria-valuenow', String(widths[index] || header.offsetWidth));
    handle.setAttribute(
      'aria-label',
      (strings.csvResizeColumn || 'Resize column {column}').replace('{column}', String(index + 1)),
    );
    handle.title =
      strings.csvResizeHint ||
      'Drag or use Left/Right to resize. Double-click or press Enter to fit loaded rows.';
    handle.addEventListener('dblclick', function (event) {
      event.preventDefault();
      fitColumn(table, index);
    });
    handle.addEventListener('keydown', function (event) {
      if (!['ArrowLeft', 'ArrowRight', 'Enter'].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.key === 'Enter') fitColumn(table, index);
      else setWidth(table, index, header.offsetWidth + (event.key === 'ArrowRight' ? 10 : -10));
    });
    handle.addEventListener('pointerdown', function (event) {
      if (event.button !== 0) return;
      event.preventDefault();
      cancelDrag?.();
      var startX = event.clientX;
      var startWidth = header.offsetWidth;
      var zoom = _mmdZoom.value();
      handle.setPointerCapture(event.pointerId);
      table.classList.add('csv-resizing');
      function move(e: PointerEvent): void {
        setWidth(table, index, startWidth + (e.clientX - startX) / zoom);
      }
      function finish(): void {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', finish);
        handle.removeEventListener('lostpointercapture', finish);
        handle.removeEventListener('pointercancel', finish);
        table.classList.remove('csv-resizing');
        if (handle.hasPointerCapture(event.pointerId))
          handle.releasePointerCapture(event.pointerId);
        cancelDrag = undefined;
      }
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', finish);
      handle.addEventListener('lostpointercapture', finish);
      handle.addEventListener('pointercancel', finish);
      cancelDrag = finish;
    });
    header.append(handle);
  });
  applyWidths(table);
}

export { prepareCsvResize, installCsvResize };
