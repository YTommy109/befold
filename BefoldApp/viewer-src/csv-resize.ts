// CSV/TSV の列幅は表示中の文書だけで保持する。保存や原文の変更はしない。
import { installCsvScrollbar, removeCsvScrollbar } from './csv-scrollbar.js';
import { _mmdZoom } from './zoom.js';

var MIN_WIDTH = 40;
// 表示領域に収まらない表の初期幅の規則（initialWidths）。
var INITIAL_MAX_WIDTH = 360;
var INITIAL_WIDTH_PERCENTILE = 0.9;
// これを超える行数の表は、ドラッグ中に幅を更新せず案内線だけ動かし、離したときに 1 回だけ確定する。
// 幅変更 1 回は全行の再レイアウトで、実測（TASK-669）は 10,000 行で約 0.13 秒、50,000 行で
// 約 0.37 秒。ライブで追従したときのフレーム時間は 1,000 行で 14ms、2,000 行で 20ms
// （30fps の目安 33ms 以内）、10,000 行で約 105ms。2,000 行は余裕を持って追従できる上限。
var LIVE_RESIZE_MAX_ROWS = 2000;
var widths: number[] = [];
// widths のうち、ユーザーが変えた列の幅。自動の幅は内容から決まるので再描画で捨てる。
var manualWidths = new Map<number, number>();
var path: string | null = null;
var cancelDrag: (() => void) | undefined;

// 手動の幅の持ち主は文書のパス。同じパスの再描画（保存による内容変更・表示切替）では保持する。
// パス不明（null）は別文書かもしれないので、常に捨てる。自動の幅は再描画のたびに測り直す。
// チャンク追記はここを通らないので、読んでいる表の幅は動かない。
function prepareCsvResize(newPath: string | null): void {
  cancelDrag?.();
  removeCsvScrollbar();
  if (newPath === null || path !== newPath) manualWidths.clear();
  widths = [];
  manualWidths.forEach((width, column) => {
    widths[column] = width;
  });
  path = newPath;
}

function applyWidths(table: HTMLTableElement): void {
  if (widths.length === 0) return;
  var headers = table.tHead!.rows[0]!.cells;
  // 列が減った再描画では、消えた列の幅を合計に残さない。
  widths.length = Math.min(widths.length, headers.length);
  for (var manualColumn of manualWidths.keys()) {
    if (manualColumn >= headers.length) manualWidths.delete(manualColumn);
  }
  // 列幅を書き込む前に自然幅をまとめて読む（交互に行うと列ごとに全行を再レイアウトする）。
  for (var column = 0; column < headers.length; column++) {
    if (widths[column] === undefined)
      widths[column] = Math.max(MIN_WIDTH, headers[column]!.offsetWidth);
  }
  var group = table.querySelector('colgroup');
  if (!group) {
    group = document.createElement('colgroup');
    table.prepend(group);
  }
  while (group.children.length < headers.length) group.append(document.createElement('col'));
  for (var i = 0; i < headers.length; i++) {
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

/**
 * ユーザー操作で指定した列幅を適用する。下限は 40px、上限は設けない。
 * 初期幅の 360px 上限は、ドラッグ・キー操作・内容へのフィットには適用しない。
 */
function setWidth(table: HTMLTableElement, index: number, width: number): void {
  if (widths.length === 0)
    widths = Array.from(table.tHead!.rows[0]!.cells, (cell) =>
      Math.max(MIN_WIDTH, cell.offsetWidth),
    );
  widths[index] = Math.max(MIN_WIDTH, width);
  manualWidths.set(index, widths[index]);
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

/**
 * 列境界のダブルクリック（または Enter）で、現在読み込み済みの内容に列幅を合わせる。
 * 「さらに読み込む」で追加された行や画面外の行も対象にし、360px の上限は適用しない。
 * 測定対象はヘッダーと、全読み込み済み行から表示上の長さで選んだ上位最大 200 セル。
 * 桁区切り・負数表記・セル内余白を含む実際の表示幅を測る。
 * 初回表示の既定幅の規則は {@link initialWidths} を参照。
 */
function fitColumn(table: HTMLTableElement, index: number): void {
  const probe = createProbe(table);
  if (!probe) return;
  for (var cell of fitCandidates(table, index)) {
    var copy = copyForMeasurement(cell);
    if (copy) probe.insertRow().append(copy);
  }
  table.parentElement!.append(probe);
  var width = probe.offsetWidth || MIN_WIDTH;
  probe.remove();
  setWidth(table, index, width);
}

// 実測用の不可視の表。セルを同じ CSS の下で折り返さず測る。WebKit の font shorthand や
// tabular-nums を canvas に転写せず、実際の書式と明示的改行をそのまま使う。
function createProbe(table: HTMLTableElement): HTMLTableElement | null {
  const probe = table.cloneNode(false);
  if (!(probe instanceof HTMLTableElement)) return null;
  probe.classList.remove('csv-sized');
  probe.setAttribute('aria-hidden', 'true');
  probe.style.cssText =
    'position:absolute;visibility:hidden;display:table;table-layout:auto;width:max-content;padding-right:0;pointer-events:none';
  return probe;
}

function copyForMeasurement(cell: HTMLTableCellElement): HTMLTableCellElement | null {
  const copy = cell.cloneNode(true);
  if (!(copy instanceof HTMLTableCellElement)) return null;
  copy.querySelector('.csv-resize-handle')?.remove();
  copy.style.whiteSpace = 'pre';
  return copy;
}

/**
 * 初回表示時に、幅が未確定の列へ既定幅を設定する。
 *
 * - 読み込み済みデータ行の先頭最大 200 行を標本とし、その列の空白セルを除外する。
 * - 書式設定とセル内余白を含む、実際に描画される幅を測る。
 * - 全列の標本の最大幅の合計が表示領域に収まるなら、幅を設定しない。表は自動レイアウトの
 *   ままで、内容を切り取らない。追記や再描画のたびに判定し直す。
 * - 手動で変えた列があれば、その幅と残りの列の最大幅の合計で判定する。収まれば残りの列は
 *   最大幅にする。
 * - 以降は収まらない表の規則。
 * - 標本のおよそ 90% が収まる幅として、90 パーセンタイルの幅を採用する。
 * - ヘッダーの方が広ければ、ヘッダーの幅を採用する。
 * - 最後に 40〜360px の範囲へ制限する。ヘッダーがそれ以上の幅を必要としても同じ。
 * - 数値（td.csv-num）は桁が欠けると別の値に読めるので、標本の最大幅を下回らせず、
 *   上限も適用しない。
 * - 長い内容は自動折り返しせず、列の境界で省略記号を付けて切り取る。
 *   この表示は style.css の csv-sized が担い、データ自体に含まれる改行は保持する。
 *
 * ウィンドウの幅に合わせた列幅の伸縮は行わず、はみ出した分は横スクロールで表示する。
 * 「さらに読み込む」で行を追加しても、既存の列幅は既定幅・手動調整済みの幅ともに保持する。
 * 追加行の長い内容も省略記号を付けて切り取り、再標本化や自動拡張で閲覧中の表を動かさない。
 *
 * ユーザーは次の操作で幅を調整できる。
 * - 列境界のドラッグ：下限は 40px、上限なし（{@link setWidth}）。
 * - 列境界のダブルクリック：追加行を含む現在読み込み済みの内容に合わせる（{@link fitColumn}）。
 *   360px の上限は適用せず、処理量を抑えるため、ヘッダーと全読み込み済み行の長い値から
 *   選んだ上位最大 200 セルを測定する。
 *
 * @remarks
 * 後続の行で新しい列が増えた場合、その列の幅だけを別途初期化する。その列のセルが無い行は
 * 標本に数えないので、追記された行の値で測る。
 */
function initialWidths(table: HTMLTableElement): void {
  var headers = table.tHead!.rows[0]!.cells;
  var missing = Array.from(headers, (_, index) => index).filter(
    (index) => widths[index] === undefined,
  );
  if (missing.length === 0) return;
  const probe = createProbe(table);
  if (!probe) return;
  var samples = missing.map((index) => {
    var cells: HTMLTableCellElement[] = [];
    // ヘッダー + データ FIT_SAMPLE 個。列のセルが無い行（追記で増えた列の古い行）は数えない。
    for (var rowIndex = 0; rowIndex < table.rows.length && cells.length <= FIT_SAMPLE; rowIndex++) {
      var original = table.rows[rowIndex]!.cells[index];
      var copy = original ? copyForMeasurement(original) : null;
      if (!copy) continue;
      copy.style.display = 'block';
      copy.style.width = 'max-content';
      probe.insertRow().append(copy);
      cells.push(copy);
    }
    return cells;
  });
  table.parentElement!.append(probe);
  // 測定で本体の表まで自動レイアウトさせない（実測: 10,000 行の再描画が 375ms から 3,300ms に
  // 悪化した）。追記では隠さない。文書が縮んで読んでいる位置が失われ、render と違って
  // 復元する経路が無いため。設置済みの表はハンドルの有無で分かる。
  var hideDuringMeasurement = !table.querySelector('.csv-resize-handle');
  if (hideDuringMeasurement) table.style.display = 'none';
  var measured = samples.map((cells) => {
    var header = cells[0]?.offsetWidth ?? 0;
    var numeric = 0;
    var data = cells
      .slice(1)
      .filter((cell) => cell.textContent?.trim())
      .map((cell) => {
        var width = cell.offsetWidth;
        if (cell.classList.contains('csv-num')) numeric = Math.max(numeric, width);
        return width;
      });
    data.sort((a, b) => a - b);
    var typical = data[Math.max(0, Math.ceil(data.length * INITIAL_WIDTH_PERCENTILE) - 1)] ?? 0;
    return {
      initial: Math.max(header, typical),
      natural: Math.max(header, data.at(-1) ?? 0),
      numeric,
    };
  });
  probe.remove();
  // border-collapse の外枠 1px は applyWidths の合計と同じ。手動の幅も表の幅に含める。
  var kept = widths.slice(0, headers.length).reduce((sum, width) => sum + width, 1);
  var fits = measured.reduce((sum, width) => sum + width.natural, kept) <= tableContentWidth(table);
  if (hideDuringMeasurement) table.style.display = '';
  // 全列が収まるなら幅を決めず、表を自動レイアウトのままにする。
  if (fits && missing.length === headers.length) return;
  missing.forEach((index, sample) => {
    // 非表示のビューアは幅を実測できないため、表示状態で再描画されたときに再試行する。
    var width = measured[sample]!;
    if (width.initial > 0)
      widths[index] = fits
        ? Math.max(MIN_WIDTH, width.natural)
        : Math.max(MIN_WIDTH, Math.min(INITIAL_MAX_WIDTH, width.initial), width.numeric);
  });
}

// 表が横スクロールなしで使える幅。.csv-scroll の右端の余白は表の幅に含めない。
function tableContentWidth(table: HTMLTableElement): number {
  var scroller = table.parentElement!;
  var style = getComputedStyle(scroller);
  return scroller.clientWidth - pixels(style.paddingLeft) - pixels(style.paddingRight);
}

function pixels(value: string): number {
  return Number(value.replace('px', ''));
}

function installCsvResize(table: HTMLTableElement): void {
  var headers = table.tHead?.rows[0]?.cells;
  if (!headers) return;
  initialWidths(table);
  var strings = window._mmdUIStrings || {};
  // ハンドルの追加もレイアウトを無効化するため、全列を先に測る。
  var measuredWidths = Array.from(headers, (header, index) =>
    header.querySelector('.csv-resize-handle') ? 0 : (widths[index] ?? header.offsetWidth),
  );
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
    handle.setAttribute('aria-valuenow', String(measuredWidths[index]));
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
  installCsvScrollbar(table);
}

export { prepareCsvResize, installCsvResize };
