// キーボード操作の配線と、キーからスクロール量を決める規則。

import type { OpenBar } from './bar.js';
import { closeCurrentBar, currentBar } from './bar.js';
import { isHostFeatureEnabled } from './bridge.js';
import { isComposingKeyEvent } from './ime.js';
import { _mmdJumpNextIfOpen, _mmdJumpPrevIfOpen } from './jump.js';
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
// IME 変換中の Escape(候補キャンセル)では閉じない。判定は他の 2 箇所（ジャンプの
// Enter・検索コントローラの Enter）と同じ isComposingKeyEvent に寄せてある。
//
// ハンドラ内の分岐ではなく純粋関数にしてあるのは、resolveScrollKey と同じく
// Help > キーボードショートカット の一覧と突き合わせるため(TASK-503)。
function resolveBarCloseKey(
  key: string,
  openBar: OpenBar,
  isComposing: boolean,
  keyCode: number,
): boolean {
  return key === 'Escape' && openBar !== null && !isComposingKeyEvent({ isComposing, keyCode });
}

// Enter / Shift+Enter が「文書内ジャンプの次へ / 前へ」にあたるかの判定。
// 戻り値は移動方向（該当しなければ null）。
//
// 検索バーと違いジャンプバーは入力欄を持たないためキーボードフォーカスが乗らず、
// バー要素の keydown では Enter を受け取れない（実機で 1/5 のまま動かないことを確認）。
// そのため document で拾う。検索バーが開いている間は openBar が 'find' なので
// ここは動かず、検索バー自身の入力欄が Enter を処理する（バーは同時に開かない）。
//
// IME 変換確定の Enter では動かさない（resolveBarCloseKey と同じ isComposingKeyEvent）。
//
// 素の Enter / Shift+Enter だけを見る。Cmd/Ctrl/Alt+Enter は別の受け手を持つ
// チョードなので、ジャンプバーが開いている間もそのまま通す（TASK-485.6）。
//
// 引数はすべて keydown イベント由来なので 1 つのオブジェクトへ畳んである。
// スカラを並べる形のままだと修飾キーを足すだけで 7 引数になり、呼び出し側で
// 順番を取り違えても型で気づけない。
interface JumpNavigationKeyEvent {
  key: string;
  shiftKey: boolean;
  metaKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  isComposing: boolean;
  keyCode: number;
}

function resolveJumpNavigationKey(
  event: JumpNavigationKeyEvent,
  openBar: OpenBar,
): 'next' | 'prev' | null {
  if (event.key !== 'Enter' || openBar !== 'jump' || isComposingKeyEvent(event)) {
    return null;
  }
  if (event.metaKey || event.ctrlKey || event.altKey) {
    return null;
  }
  return event.shiftKey ? 'prev' : 'next';
}

// Enter を既定動作として自分で処理する要素か（フォーカスが乗っているものを渡す）。
// リンク・ボタン・入力欄の上での Enter は、ジャンプの前後移動より要素側の既定動作を
// 優先する。markdown-it の出力するリンクは Tab でフォーカスできるため、これが無いと
// document で拾うジャンプがリンクを開く Enter まで奪う（TASK-485.6）。
//
// mermaid が出力する SVG のリンクは SVGAElement で HTMLElement ではないため、
// スクロール側の編集可能判定と違って instanceof HTMLElement では絞らない
// （isContentEditable は HTMLElement にしか無いのでそこだけ instanceof で見る）。
// SVG 要素の tagName は小文字で来るので大文字化してから比べる。
var ENTER_OWNING_TAGS = ['BUTTON', 'INPUT', 'TEXTAREA', 'SELECT'];

function ownsEnterKey(active: Element | null): boolean {
  if (active === null) {
    return false;
  }
  if (active instanceof HTMLElement && active.isContentEditable) {
    return true;
  }
  var tagName = active.tagName.toUpperCase();
  // href の無い <a> は Enter で何も起きないため、ジャンプを譲る理由が無い。
  if (tagName === 'A') {
    return active.hasAttribute('href');
  }
  return ENTER_OWNING_TAGS.includes(tagName);
}

function _mmdInitKeyboard(): void {
  document.addEventListener('keydown', function (e) {
    if (resolveBarCloseKey(e.key, currentBar(), e.isComposing, e.keyCode)) {
      e.preventDefault();
      closeCurrentBar();
      return;
    }
    var jumpDirection = resolveJumpNavigationKey(e, currentBar());
    // フォーカス判定をここに置くのは、下のスクロール側の素通し判定と同じ理由
    // （DOM を読む部分はハンドラに集め、キーの規則だけを純粋関数に残す）。
    if (jumpDirection && !ownsEnterKey(document.activeElement)) {
      e.preventDefault();
      if (jumpDirection === 'next') {
        _mmdJumpNextIfOpen();
      } else {
        _mmdJumpPrevIfOpen();
      }
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
  resolveJumpNavigationKey,
  ownsEnterKey,
  _mmdInitKeyboard,
};
