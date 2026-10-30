import { _mmdScrollTarget } from './scroll.js';

// これを超える件数のときだけ、画面付近の一致に絞って登録する。間引きの二分探索は
// 「文書順の一致は画面上でも上から下へ並ぶ」前提に立つため、float や position で
// 文書順より上に描かれる内容（Markdown の生 HTML で起きうる）があると崩れる
// （非表示の内容の矩形 0 は「窓の内側」と判定されて登録範囲が広がるだけで、害はない）。
// 件数が少なければ全件を登録して前提を持ち込まない。
// ponytail: 閾値を超え、かつ文書順と縦の並びが一致しない文書では見えている一致が
// 塗られないことがある。起きたら文書位置（caretRangeFromPoint）で窓を決める形へ。
var CULL_THRESHOLD = 2000;

var nativeMatches: StaticRangeInit[] = [];
var paintedStart = -1;
var paintedEnd = -1;
var highlightFrame: number | null = null;
var highlightResize: ResizeObserver | null = null;
var highlightStyles: MutationObserver | null = null;
var printingHighlights = false;

export function clearNativeHighlights(): void {
  CSS.highlights.delete('mmd-find-match');
  CSS.highlights.delete('mmd-find-match-current');
  nativeMatches = [];
  paintedStart = paintedEnd = -1;
  if (highlightFrame !== null) window.cancelAnimationFrame(highlightFrame);
  highlightFrame = null;
  highlightResize?.disconnect();
  highlightStyles?.disconnect();
}

// 前回の登録と描画済み区間はここで必ず捨てる（件数が同じ別のクエリで、区間が
// 一致して古い範囲が残ることを呼び出し側の手順に頼らず防ぐ）。
export function setNativeHighlights(root: Node, matches: StaticRangeInit[]): void {
  clearNativeHighlights();
  nativeMatches = matches;
  // 間引かない件数では全件を登録し終えるので、スクロールや style の変化を見張らない。
  if (matches.length > CULL_THRESHOLD) watchHighlightViewport(root);
  updateNativeHighlights();
}

function scheduleNativeHighlights(): void {
  if (highlightFrame !== null || nativeMatches.length === 0) return;
  highlightFrame = window.requestAnimationFrame(function () {
    highlightFrame = null;
    updateNativeHighlights();
  });
}

function watchHighlightViewport(root: Node): void {
  window.addEventListener('scroll', scheduleNativeHighlights, true);
  window.addEventListener('resize', scheduleNativeHighlights);
  window.addEventListener('beforeprint', showPrintHighlights);
  window.addEventListener('afterprint', restoreViewportHighlights);
  var viewport = _mmdScrollTarget();
  if (viewport && typeof ResizeObserver !== 'undefined') {
    highlightResize ??= new ResizeObserver(scheduleNativeHighlights);
    highlightResize.observe(viewport);
  }
  // Zoom, font settings, and resized CSV columns can change wrapping without a scroll.
  highlightStyles ??= new MutationObserver(scheduleNativeHighlights);
  highlightStyles.observe(root, {
    attributes: true,
    subtree: true,
    attributeFilter: ['style', 'class'],
  });
  highlightStyles.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['style'],
  });
}

function showPrintHighlights(): void {
  // shortcut: printing paints every match; batch this if dense-query printing must stay interactive.
  printingHighlights = true;
  updateNativeHighlights();
}

function restoreViewportHighlights(): void {
  printingHighlights = false;
  updateNativeHighlights();
}

function updateNativeHighlights(): void {
  if (nativeMatches.length === 0) return;
  var start = 0;
  var end = nativeMatches.length;
  if (!printingHighlights && nativeMatches.length > CULL_THRESHOLD) {
    var viewport = _mmdScrollTarget()!.getBoundingClientRect();
    // One viewport of overscan keeps continuous scrolling painted between animation frames.
    var top = viewport.top - viewport.height;
    var bottom = viewport.bottom + viewport.height;
    var range = document.createRange();
    var bounds = function (index: number): DOMRect {
      var match = nativeMatches[index]!;
      // CSV cells can wrap differently; their row bounds remain in document order.
      var row = match.startContainer.parentElement!.closest('tr');
      if (row) return row.getBoundingClientRect();
      range.setStart(match.startContainer, match.startOffset);
      range.setEnd(match.endContainer, match.endOffset);
      return range.getBoundingClientRect();
    };
    // 全ヒットの位置を毎回測らず、表示区間の端だけを二分探索する。
    var low = 0;
    var high = end;
    var middle: number;
    while (low < high) {
      middle = Math.floor((low + high) / 2);
      if (bounds(middle).bottom < top) low = middle + 1;
      else high = middle;
    }
    start = low;
    high = end;
    while (low < high) {
      middle = Math.floor((low + high) / 2);
      if (bounds(middle).top <= bottom) low = middle + 1;
      else high = middle;
    }
    end = low;
  }
  if (start === paintedStart && end === paintedEnd) return;
  // 全ヒットの Range 生成・登録は高コストなので、画面周辺だけを生成する（印刷時は全件）。
  var highlight = new Highlight();
  for (var i = start; i < end; i++) highlight.add(new StaticRange(nativeMatches[i]!));
  CSS.highlights.delete('mmd-find-match');
  CSS.highlights.set('mmd-find-match', highlight);
  paintedStart = start;
  paintedEnd = end;
}
