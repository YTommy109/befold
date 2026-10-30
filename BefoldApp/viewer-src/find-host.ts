// 検索バーの DOM 配線: 入力欄の取得、ホスト（Swift）設定の反映、イベント結線、件数表示。
// コントローラの状態は引数で受け取り、ここでは保持しない。

import { wireBarControls } from './bar-controls.js';
import { buildFindRegExp, walk } from './find-scan.js';
import type { FindOptions } from './find-scan.js';
import { isComposingKeyEvent } from './ime.js';
import { formatNavigationCount } from './navigation.js';

// viewer.html に静的に置かれている <input>。getElementById は HTMLElement までしか
// 返さないため、instanceof で <input> であることを確かめてから返す。要素が消えた
// 場合は呼び出し側が value を触った時点ではなくここで TypeError になる（どちらも
// 復帰できない構成の壊れで、握り潰さない点は変えていない）。
export function findInputElement(): HTMLInputElement {
  var el = document.getElementById('mmd-find-input');
  if (!(el instanceof HTMLInputElement)) {
    throw new TypeError('#mmd-find-input is missing');
  }
  return el;
}

// マッチなしを専用文言で表示すると文字幅の違いでバーが伸縮するため、
// 常に「現在位置/件数」形式(マッチなし時は 0/0)のみを表示する。
// 段階読み込み中(truncated)は表示済み DOM だけが検索対象であることを示すため
// 「表示範囲内」ラベルを付与する。
export function renderFindCount(
  query: string,
  currentIndex: number,
  total: number,
  truncated: boolean,
): void {
  var countEl = document.getElementById('mmd-find-count')!;
  var input = findInputElement();
  if (query.length === 0 || input.classList.contains('mmd-find-error')) {
    countEl.textContent = '';
  } else {
    var strings: ViewerFindStrings = window._mmdFindStrings || {};
    countEl.textContent = formatNavigationCount(
      currentIndex,
      total,
      truncated,
      strings.withinDisplayedRange || 'Displayed range',
    );
  }
}

// ロード時に保存済みトグル状態(window._mmdInitialFindOptions、Swift から注入)と
// ローカライズ済み文字列(window._mmdFindStrings、Swift から注入)を反映する。
export function applyFindHostSettings(options: FindOptions): void {
  var opts: ViewerFindOptions = window._mmdInitialFindOptions || {};
  options.caseSensitive = !!opts.caseSensitive;
  options.wholeWord = !!opts.wholeWord;
  options.useRegex = !!opts.useRegex;
  document.getElementById('mmd-find-case')!.classList.toggle('active', options.caseSensitive);
  document.getElementById('mmd-find-word')!.classList.toggle('active', options.wholeWord);
  document.getElementById('mmd-find-regex')!.classList.toggle('active', options.useRegex);

  var strings: ViewerFindStrings = window._mmdFindStrings || {};
  var input = findInputElement();
  if (strings.placeholder) {
    input.placeholder = strings.placeholder;
  }
  if (strings.previous) {
    document.getElementById('mmd-find-prev')!.title = strings.previous;
  }
  if (strings.next) {
    document.getElementById('mmd-find-next')!.title = strings.next;
  }
  if (strings.matchCase) {
    document.getElementById('mmd-find-case')!.title = strings.matchCase;
  }
  if (strings.matchWholeWord) {
    document.getElementById('mmd-find-word')!.title = strings.matchWholeWord;
  }
  if (strings.useRegularExpression) {
    document.getElementById('mmd-find-regex')!.title = strings.useRegularExpression;
  }
  if (strings.close) {
    document.getElementById('mmd-find-close')!.title = strings.close;
  }
}

export interface FindControlHandlers {
  run: () => void;
  next: () => void;
  prev: () => void;
  close: () => void;
  toggleOption: (optionName: keyof FindOptions, buttonId: string) => void;
}

export function wireFindControls(h: FindControlHandlers): void {
  document.getElementById('mmd-find-input')!.addEventListener('input', function () {
    h.run();
  });
  document.getElementById('mmd-find-input')!.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      // 変換確定の Enter では検索を進めない（判定は ime.ts に集約）。
      if (isComposingKeyEvent(e)) {
        return;
      }
      e.preventDefault();
      if (e.shiftKey) {
        h.prev();
      } else {
        h.next();
      }
    }
    // Escape はここでは処理しない: document の keydown ハンドラがバブリングで捕捉し、
    // isOpen() 時に preventDefault + close() を行う(同じ挙動になる)。
  });
  wireBarControls({
    prevId: 'mmd-find-prev',
    nextId: 'mmd-find-next',
    closeId: 'mmd-find-close',
    onPrev: h.prev,
    onNext: h.next,
    onClose: h.close,
  });
  document.getElementById('mmd-find-case')!.addEventListener('click', function () {
    h.toggleOption('caseSensitive', 'mmd-find-case');
  });
  document.getElementById('mmd-find-word')!.addEventListener('click', function () {
    h.toggleOption('wholeWord', 'mmd-find-word');
  });
  document.getElementById('mmd-find-regex')!.addEventListener('click', function () {
    h.toggleOption('useRegex', 'mmd-find-regex');
  });
}

// 現在位置の 1 件を専用の Highlight に差し替え、そこまでスクロールする。
// 一覧側の Highlight には触れないので、マッチが何万件あっても走査は起きない。
// 中央寄せ・smooth はジャンプバー（navigation.ts の moveCurrentHighlight）と同じ見え方。
export function moveFindHighlight(current: StaticRangeInit): void {
  var highlight = new Highlight(new StaticRange(current));
  highlight.priority = 1;
  // Older WebKit does not repaint replacement entries (webkit.org/b/321567).
  CSS.highlights.delete('mmd-find-match-current');
  CSS.highlights.set('mmd-find-match-current', highlight);
  scrollFindRange(current);
}

// 直前のハイライトを消した後の文書を検索し、document 順のマッチを返す。
// 不正な正規表現のときは入力欄にエラー表示を付け、マッチは空になる。
export function searchDocument(query: string, options: FindOptions): StaticRangeInit[] {
  var regex = buildFindRegExp(query, options);
  findInputElement().classList.toggle('mmd-find-error', query.length > 0 && regex === null);
  return regex ? walk(document.getElementById('diagram-wrap')!, regex) : [];
}

// Center the exact text, including wrapped lines, without changing the user's selection.
function scrollFindRange(match: StaticRangeInit): void {
  var range = document.createRange();
  range.setStart(match.startContainer, match.startOffset);
  range.setEnd(match.endContainer, match.endOffset);
  var rect = range.getBoundingClientRect();
  var left = rect.left;
  var top = rect.top;
  for (var el = match.startContainer.parentElement; el; el = el.parentElement) {
    var style = getComputedStyle(el);
    var scrollX =
      /^(auto|scroll|hidden)$/u.test(style.overflowX) && el.scrollWidth > el.clientWidth;
    var scrollY =
      /^(auto|scroll|hidden)$/u.test(style.overflowY) && el.scrollHeight > el.clientHeight;
    if (!scrollX && !scrollY) continue;
    var bounds = el.getBoundingClientRect();
    var scale = el.offsetWidth ? bounds.width / el.offsetWidth : 1;
    var x = left - bounds.left - el.clientLeft * scale;
    var y = top - bounds.top - el.clientTop * scale;
    var width = el.clientWidth * scale;
    var dx = 0;
    // Match scrollIntoView's inline:nearest behavior, including a range wider than its viewport.
    if (x < 0 && x + rect.width < width) dx = Math.max(x, x + rect.width - width);
    if (x + rect.width > width && x > 0) dx = Math.min(x, x + rect.width - width);
    var nextLeft = scrollX
      ? Math.max(0, Math.min(el.scrollWidth - el.clientWidth, el.scrollLeft + dx / scale))
      : el.scrollLeft;
    var nextTop = scrollY
      ? Math.max(
          0,
          Math.min(
            el.scrollHeight - el.clientHeight,
            el.scrollTop + (y + rect.height / 2) / scale - el.clientHeight / 2,
          ),
        )
      : el.scrollTop;
    left -= (nextLeft - el.scrollLeft) * scale;
    top -= (nextTop - el.scrollTop) * scale;
    el.scrollTo({ left: nextLeft, top: nextTop, behavior: 'smooth' });
  }
}
