// 検索バーの DOM 配線: 入力欄の取得、ホスト（Swift）設定の反映、イベント結線、件数表示。
// コントローラの状態は引数で受け取り、ここでは保持しない。

import { wireBarControls } from './bar-controls.js';
import { buildFindRegExp, walk } from './find-scan.js';
import type { FindOptions } from './find-scan.js';
import { isComposingKeyEvent } from './ime.js';
import { formatNavigationCount, moveCurrentHighlight } from './navigation.js';

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

// 印の付け替えとスクロールは navigation.ts に集約する（ジャンプバーと同じ挙動）。
// 直前の要素だけを渡すので、マッチが何万件あっても走査は起きない。
export function moveFindHighlight(
  previous: HTMLElement | undefined,
  current: HTMLElement | undefined,
): void {
  moveCurrentHighlight(
    previous ? [previous] : [],
    current ? [current] : [],
    'mmd-find-match-current',
    current,
  );
}

// 直前のマークを消した後の文書を検索し、document 順のマッチを返す。
// 不正な正規表現のときは入力欄にエラー表示を付け、マッチは空になる。
export function searchDocument(query: string, options: FindOptions): HTMLElement[] {
  var regex = buildFindRegExp(query, options);
  findInputElement().classList.toggle('mmd-find-error', query.length > 0 && regex === null);
  var found: HTMLElement[] = [];
  if (regex) {
    walk(document.getElementById('diagram-wrap')!, regex, found);
  }
  return found;
}
