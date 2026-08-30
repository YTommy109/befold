// スクロール対象の決定と、位置の復元。

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

// 注入された復元位置を 1 つの owner に閉じる。Swift 側(ViewerWebView)が render() 呼び出しの
// 直前に評価し、次の render() が復元すべき scrollTop を渡してくる。復元時に消費する。
//
// **位置を Swift へ継続的に送る仕掛けは持たない（TASK-574.3）。** かつては scroll イベントを
// 200ms デバウンスして送っていたが、その目的は「アプリ終了時やウィンドウ破棄時にも最新の
// 位置が保存されるよう」だった（位置を UserDefaults へ永続化していた頃 / 36cdc7c5）。
// TASK-565 で永続化をやめ窓の生存期間だけの記憶にした時点で目的が失われ、位置は
// ファイル/モード切替の直前に Swift 側が確定保存する 1 本だけで足りるようになった。
//
// 文書パスの採用(adoptPending)もここは持たない。かつて同じ owner に置いていたのは
// 「デバウンス通知の破棄とパスの採用が同時でなければ、旧文書の位置が新パスのキーで
// 通知される」ためで、通知そのものが無くなった時点でこの結び付きは消えた。
// 採用は render() が直接行う。
function _createScrollSync() {
  var pendingRestore: number | null = null;

  return {
    setRestore: function (position: number): void {
      pendingRestore = position;
    },
    // 注入された復元位置があればそれを、無ければ fallback を返して消費する。
    // fallback は Swift を経由しない内部再描画で現在位置を保つための値。
    takeRestorePosition: function (fallback: unknown): number {
      var position =
        pendingRestore === null ? (typeof fallback === 'number' ? fallback : 0) : pendingRestore;
      pendingRestore = null;
      return position;
    },
  };
}

var _mmdScroll = _createScrollSync();

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

export { _mmdScrollTarget, _mmdScroll, _mmdSetRestoreScroll, _mmdRestoreScrollPosition };
