// スクロール対象の決定・位置の復元・位置変化の Swift への通知。

import { _MSG_SCROLL_POSITION_CHANGED, _mmdPostMessage } from './bridge.js';
import { _mmdDocPath } from './doc-path.js';
import { _mmdViewOptions } from './view-options.js';

// 実際にスクロールする要素は表示モードで異なる（style.css の .code-body 参照）。
// ソースコード表示では #diagram-wrap.code-body pre code が、それ以外は .viewer 自体が
// スクロールコンテナになるため、都度どちらが実体かを見て決める。
function _mmdScrollTarget(): Element | null {
  var codeEl = document.querySelector('#diagram-wrap.code-body pre code');
  if (codeEl) {
    return codeEl;
  }
  return document.querySelector('.viewer');
}

// スクロール位置の受け渡しを 1 つの owner に閉じる。持つのは 2 つ:
// - 注入された復元位置: Swift 側(ViewerWebView)が render() 呼び出しの直前に評価し、
//   次の render() が復元すべき scrollTop を渡してくる。復元時に消費する。
// - 通知デバウンスのタイマ: スクロールイベントを 200ms まとめて Swift へ送る。
// この 2 つは描画開始時に組み合わせて判定する(beginRender 参照)ため同じ owner に置く。
function _createScrollSync(notify: () => void, docPathTracker: { adoptPending: () => void }) {
  var pendingRestore: number | null = null;
  var debounceTimer: ReturnType<typeof setTimeout> | null = null;

  function cancelPendingNotify(): void {
    if (debounceTimer === null) {
      return;
    }
    clearTimeout(debounceTimer);
    debounceTimer = null;
  }

  return {
    setRestore: function (position: number): void {
      pendingRestore = position;
    },
    // 復元位置が注入されている(=Swift 主導のファイル/モード切替)ときだけ保留中の
    // デバウンス通知を破棄する。無条件に破棄すると、Swift を経由しない内部再描画
    // (カラースキーム変更時など、ファイル/モードは変わらない)で直前のスクロール確定
    // 保存が失われたまま二度と発火しなくなるため。
    // 文書パスの採用も同じ時点で行う。破棄と採用が同時なので、旧文書の位置が
    // 新パスのキーで通知されることはない。
    beginRender: function (): void {
      if (pendingRestore !== null) {
        cancelPendingNotify();
      }
      docPathTracker.adoptPending();
    },
    // 注入された復元位置があればそれを、無ければ fallback を返して消費する。
    // fallback は Swift を経由しない内部再描画で現在位置を保つための値。
    takeRestorePosition: function (fallback: unknown): number {
      var position =
        pendingRestore !== null ? pendingRestore : typeof fallback === 'number' ? fallback : 0;
      pendingRestore = null;
      return position;
    },
    notifyDebounced: function (): void {
      cancelPendingNotify();
      debounceTimer = setTimeout(function () {
        debounceTimer = null;
        notify();
      }, 200);
    },
  };
}

// スクロール位置の変化を Swift 側へ通知する(継続的な保存用、200ms デバウンス経由でのみ呼ばれる)。
// ファイル/モード切替直前の退場側位置は、Swift 側(ViewerWindowController)が
// 切替処理の中で明示的に旧 URL・旧モードのキーへ確定保存するため、ここでは扱わない。
// path はこの位置が属する文書(いま DOM に出ている文書)。文書が定まらない間は null で、
// Swift 側はその通知を捨てる。
function _mmdPostScrollPosition(): void {
  var el = _mmdScrollTarget();
  if (!el) return;
  _mmdPostMessage(_MSG_SCROLL_POSITION_CHANGED, {
    position: el.scrollTop,
    mode: _mmdViewOptions.mode(),
    path: _mmdDocPath.current(),
  });
}

// 通知先(_mmdPostScrollPosition)は関数宣言として巻き上げられるため、ここで束ねられる。
var _mmdScroll = _createScrollSync(_mmdPostScrollPosition, _mmdDocPath);

function _mmdSetRestoreScroll(position: number): void {
  _mmdScroll.setRestore(position);
}

// fallbackScrollTop は Swift 由来の pending 値が無いとき(カラースキーム変更時の
// 内部再描画など、Swift を経由しない render() 呼び出し)に使う復元位置。
// render() が DOM を書き換える直前の scrollTop を渡すことで、内部再描画では
// 現在位置がそのまま保たれる。
function _mmdRestoreScrollPosition(fallbackScrollTop: unknown): void {
  var el = _mmdScrollTarget();
  if (!el) return;
  el.scrollTop = _mmdScroll.takeRestorePosition(fallbackScrollTop);
}

// スクロールイベントをデバウンスして Swift 側へ通知する。アプリ終了時やウィンドウ
// 破棄時にも最新の位置が保存されるよう継続的に送る(ファイル/モード切替直前の確定保存は
// Swift 側が別途行う。上記コメント参照)。
function _mmdInitScrollNotify(): void {
  document.addEventListener(
    'scroll',
    function () {
      _mmdScroll.notifyDebounced();
    },
    true,
  );
}

export {
  _mmdScrollTarget,
  _mmdScroll,
  _mmdSetRestoreScroll,
  _mmdRestoreScrollPosition,
  _mmdPostScrollPosition,
  _mmdInitScrollNotify,
};
