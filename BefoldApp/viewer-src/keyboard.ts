// キーボード操作の配線と、キーからスクロール量を決める規則。

import type { OpenBar } from './bar.js';
import { closeCurrentBar, currentBar } from './bar.js';
import { isHostFeatureEnabled } from './bridge.js';
import { _mmdScrollTarget } from './scroll.js';
import { _mmdZoomIn, _mmdZoomOut } from './zoom.js';

// Space の1ページスクロール量。表示領域(clientHeight)の90%とし、
// ウィンドウサイズが変わっても常に「ほぼ1画面分」になるようにする。
var PAGE_SCROLL_RATIO = 0.9;
// 行送り(矢印/vimキー)で行の高さを取得できなかった場合のフォールバック値。
var DEFAULT_LINE_SCROLL_STEP = 24;

// ページ単位のスクロール量(px)。表示領域の高さに対する比率で決まるため、
// ウィンドウサイズによらず「ほぼ1画面分」になる。
function pageScrollStep(clientHeight: number): number {
  return clientHeight * PAGE_SCROLL_RATIO;
}

// 半ページ単位のスクロール量(px)。Shift 修飾時に使う。
function halfPageScrollStep(clientHeight: number): number {
  return pageScrollStep(clientHeight) / 2;
}

// 行単位のスクロール量(px)。CSS の line-height 計算値(例: "22.4px")を渡す。
// 取得できない/数値でない場合は fallback を返す。
function lineScrollStep(lineHeightPx: string, fallback: number): number {
  // CSS の計算値は "22.4px" のように単位付きで来る。Number() は単位付き文字列を
  // NaN にしてしまい、常に fallback へ落ちる。数値前置部だけを読む parseFloat が要件。
  // oxlint-disable-next-line unicorn/prefer-number-coercion
  var lh = parseFloat(lineHeightPx);
  return isNaN(lh) ? fallback : lh;
}

// キーボードスクロールで解決した動作。down は向き、amount はスクロール量の種別。
interface ScrollAction {
  down: boolean;
  amount: 'page' | 'half' | 'line';
}

// キーボードスクロールのキー→動作解決。Safari に合わせ、Space=下/Shift+Space=上(バックスクロール)は
// 同じフルページ量のまま方向だけ反転させ、矢印/vim キーは Shift でハーフページに切り替える。
// Backspace はバックスクロールとして扱わない(未対応キーとして null を返す)。
function resolveScrollKey(key: string, shiftKey: boolean): ScrollAction | null {
  if (key === ' ') {
    return { down: !shiftKey, amount: 'page' };
  }
  var down: boolean;
  if (key === 'ArrowDown' || key === 'j') {
    down = true;
  } else if (key === 'ArrowUp' || key === 'k') {
    down = false;
  } else {
    return null;
  }
  return { down: down, amount: shiftKey ? 'half' : 'line' };
}

// Escape が「開いているバー（検索 / 文書内ジャンプ）を閉じる」にあたるかの判定。
// IME 変換中の Escape(候補キャンセル)では閉じない。Enter 側の変換確定判定
// (検索コントローラの keydown ハンドラ)と同じ理由: Safari/WKWebView は
// compositionend → keydown の順で発火するため isComposing は既に false に
// なりうるが、keyCode は 229 のまま残るためこれも合わせて判定する。
//
// ハンドラ内の分岐ではなく純粋関数にしてあるのは、resolveScrollKey と同じく
// Help > キーボードショートカット の一覧と突き合わせるため(TASK-503)。
function resolveBarCloseKey(
  key: string,
  openBar: OpenBar,
  isComposing: boolean,
  keyCode: number,
): boolean {
  return key === 'Escape' && openBar !== null && !isComposing && keyCode !== 229;
}

function _mmdInitKeyboard(): void {
  document.addEventListener('keydown', function (e) {
    if (resolveBarCloseKey(e.key, currentBar(), e.isComposing, e.keyCode)) {
      e.preventDefault();
      closeCurrentBar();
      return;
    }
    document.body.classList.toggle('cmd-held', e.metaKey);
    if (e.metaKey) {
      if (e.key === '-') {
        e.preventDefault();
        _mmdZoomOut();
      } else if (e.key === '=' || e.key === '+') {
        e.preventDefault();
        _mmdZoomIn();
      }
      return;
    }
    var action = resolveScrollKey(e.key, e.shiftKey);
    if (!action) {
      return;
    }
    if (e.key === ' ' && !isHostFeatureEnabled(window._mmdHostFeatures, 'spaceScroll')) {
      return;
    }
    // 検索入力欄など編集可能要素にフォーカスがある間は、Space/矢印/vim jk を
    // 文字入力・カーソル移動としてそのまま素通りさせる(ビューアのスクロールに奪わない)。
    // isContentEditable は HTMLElement にしかないため、instanceof で絞り込む。
    // activeElement が null／HTMLElement 以外のときに素通りする点は元と同じ
    // （SVG 要素などは tagName も isContentEditable も一致しなかった）。
    var active = document.activeElement;
    if (
      active instanceof HTMLElement &&
      (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)
    ) {
      return;
    }
    var scrollEl = _mmdScrollTarget();
    if (!scrollEl) {
      return;
    }
    e.preventDefault();
    var step: number;
    if (action.amount === 'page') {
      step = pageScrollStep(scrollEl.clientHeight);
    } else if (action.amount === 'half') {
      step = halfPageScrollStep(scrollEl.clientHeight);
    } else {
      step = lineScrollStep(getComputedStyle(scrollEl).lineHeight, DEFAULT_LINE_SCROLL_STEP);
    }
    // 'auto'(既定)は瞬間移動で、1 回のキー操作で表示位置が飛び、読んでいた行を
    // 見失う(TASK-486)。実測では 'auto' が最初のフレームで目標へ到達するのに対し、
    // 'smooth' は 600px を約 16 フレームかけて踏む。キーリピート相当(30ms 間隔で
    // 10 連打)でも到達位置は 400px に対し 385px で、取りこぼしはしない。
    //
    // ここだけを 'smooth' にして CSS の scroll-behavior は使わない。CSS で指定すると
    // scrollTop への代入まで animate してしまい、ファイル切替・再描画時の位置復元
    // (viewer-src/scroll.ts の _mmdRestoreScrollPosition)が滑って着地しなくなる。
    scrollEl.scrollBy({ top: action.down ? step : -step, behavior: 'smooth' });
  });

  document.addEventListener('keyup', function (e) {
    if (!e.metaKey) document.body.classList.remove('cmd-held');
  });
  // ウィンドウがフォーカスを失ったときも解除する
  window.addEventListener('blur', function () {
    document.body.classList.remove('cmd-held');
  });
}

export {
  PAGE_SCROLL_RATIO,
  DEFAULT_LINE_SCROLL_STEP,
  pageScrollStep,
  halfPageScrollStep,
  lineScrollStep,
  resolveScrollKey,
  resolveBarCloseKey,
  _mmdInitKeyboard,
};
