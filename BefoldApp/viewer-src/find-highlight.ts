import { _mmdScrollTarget } from './scroll.js';

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

export function setNativeHighlights(root: Node, matches: StaticRangeInit[]): void {
  nativeMatches = matches;
  watchHighlightViewport(root);
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
  if (!printingHighlights) {
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
  var highlight = new Highlight();
  for (var i = start; i < end; i++) highlight.add(new StaticRange(nativeMatches[i]!));
  CSS.highlights.delete('mmd-find-match');
  CSS.highlights.set('mmd-find-match', highlight);
  paintedStart = start;
  paintedEnd = end;
}
