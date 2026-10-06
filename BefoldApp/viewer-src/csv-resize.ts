// CSV/TSV の列幅は表示中の文書だけで保持する。保存や原文の変更はしない。
import { _mmdZoom } from './zoom.js';

var MIN_WIDTH = 40;
// これを超える行数の表は、ドラッグ中に幅を更新せず案内線だけ動かし、離したときに 1 回だけ確定する。
// 幅変更 1 回は全行の再レイアウトで、実測（TASK-669）は 10,000 行で約 0.13 秒、50,000 行で
// 約 0.37 秒。ライブで追従したときのフレーム時間は 1,000 行で 14ms、2,000 行で 20ms
// （30fps の目安 33ms 以内）、10,000 行で約 105ms。2,000 行は余裕を持って追従できる上限。
var LIVE_RESIZE_MAX_ROWS = 2000;
var widths: number[] = [];
var path: string | null = null;
var cancelDrag: (() => void) | undefined;

// 幅の持ち主は文書のパス。同じパスの再描画（保存による内容変更・表示切替）では保持する。
// パス不明（null）は別文書かもしれないので、常に捨てる。
function prepareCsvResize(newPath: string | null): void {
  cancelDrag?.();
  if (newPath === null || path !== newPath) widths = [];
  path = newPath;
}

function applyWidths(table: HTMLTableElement): void {
  if (widths.length === 0) return;
  var headers = table.tHead!.rows[0]!.cells;
  // 列が減った再描画では、消えた列の幅を合計に残さない。
  widths.length = Math.min(widths.length, headers.length);
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

// 測定表へ入れるセルの上限（ヘッダー除く）。全行を入れると行数に比例して遅くなる
// （実測 TASK-668: 10,000 行で約 0.3 秒、50,000 行で約 1.5 秒）。
var FIT_SAMPLE = 200;

// 表示上の長さの目安（全角は 2）。最長の行を選ぶための順位づけにだけ使い、
// 幅そのものは下で DOM に測らせる。
function displayLength(text: string): number {
  var longest = 0;
  for (var line of text.split('\n')) {
    var length = 0;
    for (var ch of line) length += ch.codePointAt(0)! >= 0x2e80 ? 2 : 1;
    longest = Math.max(longest, length);
  }
  return longest;
}

// 長さの上位 FIT_SAMPLE 個（とヘッダー）だけを測る。順位は文字数の近似なので、
// 比例幅フォントで僅差の行が漏れても、差は上位に入った行との僅差に収まる。
function fitCandidates(table: HTMLTableElement, index: number): HTMLTableCellElement[] {
  var cells: HTMLTableCellElement[] = [];
  for (var row of table.rows) {
    var cell = row.cells[index];
    if (cell) cells.push(cell);
  }
  if (cells.length <= FIT_SAMPLE + 1) return cells;
  var [header, ...body] = cells;
  var ranked = body.map((candidate) => ({
    cell: candidate,
    length: displayLength(candidate.textContent ?? ''),
  }));
  ranked.sort((a, b) => b.length - a.length);
  return [header!, ...ranked.slice(0, FIT_SAMPLE).map((entry) => entry.cell)];
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
  for (var cell of fitCandidates(table, index)) {
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
    // Tab で止まるのは表全体で 1 つ（roving tabindex）。列数ぶん止まると、
    // 100 列の表では Tab を 100 回押さないと表を抜けられない。
    handle.tabIndex = index === 0 ? 0 : -1;
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
      'Drag or use Left/Right to resize. Double-click or press Enter to fit loaded rows. Alt+Left/Right moves to another column.';
    handle.addEventListener('dblclick', function (event) {
      event.preventDefault();
      fitColumn(table, index);
    });
    handle.addEventListener('focus', function () {
      for (var other of table.querySelectorAll<HTMLElement>('.csv-resize-handle'))
        other.tabIndex = other === handle ? 0 : -1;
    });
    handle.addEventListener('keydown', function (event) {
      if (!['ArrowLeft', 'ArrowRight', 'Enter'].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      if (event.key === 'Enter') fitColumn(table, index);
      else if (event.altKey) {
        var handles = table.querySelectorAll<HTMLElement>('.csv-resize-handle');
        handles[index + (event.key === 'ArrowRight' ? 1 : -1)]?.focus();
      } else setWidth(table, index, header.offsetWidth + (event.key === 'ArrowRight' ? 10 : -10));
    });
    handle.addEventListener('pointerdown', function (event) {
      if (event.button !== 0) return;
      event.preventDefault();
      cancelDrag?.();
      var startX = event.clientX;
      var startWidth = header.offsetWidth;
      var zoom = _mmdZoom.value();
      // ライブか案内線かは開始時に 1 回だけ決める（ドラッグ中に行数が変わっても切り替えない）。
      var guided = (table.tBodies[0]?.rows.length ?? 0) > LIVE_RESIZE_MAX_ROWS;
      var width: number | undefined;
      // カーソルと選択の抑止は、表へクラスやスタイルを触らず全面オーバーレイで行う。
      // 継承プロパティ（cursor・user-select）を表で切り替えると、全セルのスタイル再計算が
      // 走り、幅変更 1 回分（10,000 行で約 0.1 秒）かかる（TASK-669）。
      var overlay = document.createElement('div');
      overlay.className = 'csv-resize-overlay';
      overlay.setAttribute('aria-hidden', 'true');
      var guide: HTMLElement | undefined;
      if (guided) {
        guide = document.createElement('div');
        guide.className = 'csv-resize-guide';
        guide.style.left = startX + 'px';
        overlay.append(guide);
      }
      document.body.append(overlay);
      handle.setPointerCapture(event.pointerId);
      function move(e: PointerEvent): void {
        width = Math.max(MIN_WIDTH, startWidth + (e.clientX - startX) / zoom);
        // 案内線の位置は確定幅と同じ式の逆変換。下限で止まる位置も一致させる。
        if (guide) guide.style.left = startX + (width - startWidth) * zoom + 'px';
        else setWidth(table, index, width);
      }
      // 確定は pointerup だけ。取り消し・再描画では、古い表へ幅を書かない。
      function end(commit: boolean): void {
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', onUp);
        handle.removeEventListener('lostpointercapture', onCancel);
        handle.removeEventListener('pointercancel', onCancel);
        overlay.remove();
        if (handle.hasPointerCapture(event.pointerId))
          handle.releasePointerCapture(event.pointerId);
        cancelDrag = undefined;
        // 動かさずに離しただけの操作では、幅も表のレイアウトも変えない。
        if (commit && guided && width !== undefined) setWidth(table, index, width);
      }
      function onUp(): void {
        end(true);
      }
      function onCancel(): void {
        end(false);
      }
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', onUp);
      handle.addEventListener('lostpointercapture', onCancel);
      handle.addEventListener('pointercancel', onCancel);
      cancelDrag = onCancel;
    });
    header.append(handle);
  });
  applyWidths(table);
}

export { prepareCsvResize, installCsvResize };
