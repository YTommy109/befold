// キーボード操作の配線と、キーからスクロール量を決める規則。

import { isHostFeatureEnabled } from './bridge.js';
import { _mmdFind } from './find.js';
import { _mmdScrollTarget } from './scroll.js';
import { _mmdZoomIn, _mmdZoomOut } from './zoom.js';

// Space の1ページスクロール量。表示領域(clientHeight)の90%とし、
// ウィンドウサイズが変わっても常に「ほぼ1画面分」になるようにする。
var PAGE_SCROLL_RATIO = 0.9;
// 行送り(矢印/vimキー)で行の高さを取得できなかった場合のフォールバック値。
var DEFAULT_LINE_SCROLL_STEP = 24;

// ページ単位のスクロール量(px)。表示領域の高さに対する比率で決まるため、
// ウィンドウサイズによらず「ほぼ1画面分」になる。
function pageScrollStep(clientHeight) {
  return clientHeight * PAGE_SCROLL_RATIO;
}

// 半ページ単位のスクロール量(px)。Shift 修飾時に使う。
function halfPageScrollStep(clientHeight) {
  return pageScrollStep(clientHeight) / 2;
}

// 行単位のスクロール量(px)。CSS の line-height 計算値(例: "22.4px")を渡す。
// 取得できない/数値でない場合は fallback を返す。
function lineScrollStep(lineHeightPx, fallback) {
  var lh = parseFloat(lineHeightPx);
  return isNaN(lh) ? fallback : lh;
}

// キーボードスクロールのキー→動作解決。Safari に合わせ、Space=下/Shift+Space=上(バックスクロール)は
// 同じフルページ量のまま方向だけ反転させ、矢印/vim キーは Shift でハーフページに切り替える。
// Backspace はバックスクロールとして扱わない(未対応キーとして null を返す)。
function resolveScrollKey(key, shiftKey) {
  if (key === ' ') {
    return { down: !shiftKey, amount: 'page' };
  }
  var down;
  if (key === 'ArrowDown' || key === 'j') {
    down = true;
  } else if (key === 'ArrowUp' || key === 'k') {
    down = false;
  } else {
    return null;
  }
  return { down: down, amount: shiftKey ? 'half' : 'line' };
}

function _mmdInitKeyboard() {
  document.addEventListener('keydown', function(e) {
    // IME 変換中の Escape(候補キャンセル)では検索バーを閉じない。
    // Enter 側の変換確定判定(検索コントローラの keydown ハンドラ)と同じ理由:
    // Safari/WKWebView は compositionend → keydown の順で発火するため isComposing は
    // 既に false になりうるが、keyCode は 229 のまま残るためこれも合わせて判定する。
    if (e.key === 'Escape' && _mmdFind.isOpen() && !e.isComposing && e.keyCode !== 229) {
      e.preventDefault();
      _mmdFind.close();
      return;
    }
    document.body.classList.toggle('cmd-held', e.metaKey);
    if (e.metaKey) {
      if (e.key === '-') { e.preventDefault(); _mmdZoomOut(); }
      else if (e.key === '=' || e.key === '+') { e.preventDefault(); _mmdZoomIn(); }
      return;
    }
    var action = resolveScrollKey(e.key, e.shiftKey);
    if (!action) { return; }
    if (e.key === ' ' && !isHostFeatureEnabled(window._mmdHostFeatures, 'spaceScroll')) { return; }
    // 検索入力欄など編集可能要素にフォーカスがある間は、Space/矢印/vim jk を
    // 文字入力・カーソル移動としてそのまま素通りさせる(ビューアのスクロールに奪わない)。
    var active = document.activeElement;
    if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)) {
      return;
    }
    var scrollEl = _mmdScrollTarget();
    if (!scrollEl) { return; }
    e.preventDefault();
    var step;
    if (action.amount === 'page') {
      step = pageScrollStep(scrollEl.clientHeight);
    } else if (action.amount === 'half') {
      step = halfPageScrollStep(scrollEl.clientHeight);
    } else {
      step = lineScrollStep(getComputedStyle(scrollEl).lineHeight, DEFAULT_LINE_SCROLL_STEP);
    }
    scrollEl.scrollBy({ top: action.down ? step : -step, behavior: 'auto' });
  });

  document.addEventListener('keyup', function(e) {
    if (!e.metaKey) document.body.classList.remove('cmd-held');
  });
  // ウィンドウがフォーカスを失ったときも解除する
  window.addEventListener('blur', function() {
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
  _mmdInitKeyboard,
};
