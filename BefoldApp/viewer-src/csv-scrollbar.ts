// 数千行の表でも、表示領域の下端から横スクロールを操作できるようにする。
var cleanup: (() => void) | undefined;
var activeTable: HTMLTableElement | undefined;

function removeCsvScrollbar(): void {
  cleanup?.();
  cleanup = undefined;
  activeTable = undefined;
}

function installCsvScrollbar(table: HTMLTableElement): void {
  if (activeTable === table) return;
  removeCsvScrollbar();
  var scroller = table.closest<HTMLElement>('.csv-scroll');
  if (!scroller) return;
  activeTable = table;
  var banner = document.getElementById('mmd-truncated-banner');
  var bar = document.createElement('div');
  bar.className = 'csv-viewport-scrollbar';
  bar.tabIndex = 0;
  bar.setAttribute('role', 'region');
  bar.setAttribute(
    'aria-label',
    window._mmdUIStrings?.csvScrollHorizontally || 'Scroll table horizontally',
  );
  var track = document.createElement('div');
  bar.append(track);
  document.body.append(bar);
  function syncFromTable(): void {
    bar.scrollLeft = scroller!.scrollLeft;
  }
  function syncFromBar(): void {
    scroller!.scrollLeft = bar.scrollLeft;
  }
  function update(event?: Event): void {
    if (event?.target === bar) return;
    var rect = scroller!.getBoundingClientRect();
    var viewer = table.closest<HTMLElement>('.viewer')?.getBoundingClientRect();
    var bottom = Math.min(window.innerHeight, viewer?.bottom ?? window.innerHeight);
    // 「さらに読み込む」バナーはビューアに重なる固定表示なので、その上に配置する。
    var bannerRect = banner?.getBoundingClientRect();
    if (bannerRect && bannerRect.height > 0) bottom = Math.min(bottom, bannerRect.top);
    var left = Math.max(0, rect.left);
    var right = Math.min(window.innerWidth, rect.right);
    bar.hidden =
      scroller!.scrollWidth <= scroller!.clientWidth + 1 ||
      rect.bottom <= 0 ||
      rect.top >= bottom ||
      right <= left;
    bar.style.left = left + 'px';
    bar.style.width = Math.max(0, right - left) + 'px';
    bar.style.bottom = Math.max(0, window.innerHeight - bottom) + 'px';
    // 文書のズーム時も、レイアウト上の px 単位でスクロール可能な距離を一致させる。
    track.style.width =
      Math.max(0, right - left + scroller!.scrollWidth - scroller!.clientWidth) + 'px';
    syncFromTable();
  }
  bar.addEventListener('scroll', syncFromBar);
  scroller.addEventListener('scroll', syncFromTable);
  window.addEventListener('resize', update);
  document.addEventListener('scroll', update, true);
  var observer =
    typeof ResizeObserver === 'undefined'
      ? undefined
      : new ResizeObserver(() => {
          update();
        });
  observer?.observe(scroller);
  observer?.observe(table);
  if (banner) observer?.observe(banner);
  update();
  cleanup = () => {
    observer?.disconnect();
    window.removeEventListener('resize', update);
    document.removeEventListener('scroll', update, true);
    scroller!.removeEventListener('scroll', syncFromTable);
    bar.remove();
  };
}

export { installCsvScrollbar, removeCsvScrollbar };
