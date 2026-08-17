// リンク/パス参照のクリック・コンテキストメニューを Swift へ伝える。

import {
  _MSG_REFERENCE_ACTIVATED,
  _MSG_REFERENCE_CONTEXT_MENU,
  _mmdPostMessage,
  isHostFeatureEnabled,
} from './bridge.js';

// クリック/contextmenu で共有する要素判定。<a> / .befold-path-ref を対象にし、
// 解決待ち(pending)・解決失敗(dead)のパス参照は操作不可(通常テキスト扱い)として
// 除外する。対象外・href 無しなら null を返す。
function _mmdReferenceTargetHref(e: MouseEvent): string | null | undefined {
  // この 2 つのリスナは要素の上でしか発火しないが、EventTarget からは絞り込め
  // ないため instanceof で確かめる。要素でなければ対象外と同じ null を返す。
  var origin = e.target;
  if (!(origin instanceof Element)) return null;
  var anchor = origin.closest('a');
  var pathRef = origin.closest<HTMLElement>('.befold-path-ref');
  var target = anchor || pathRef;
  if (!target) return null;

  if (
    target.classList.contains('befold-link-pending') ||
    target.classList.contains('befold-link-dead')
  ) {
    return null;
  }

  // anchor が null のときの target は pathRef なので、ここでは必ず非 null。
  return anchor ? anchor.getAttribute('href') : pathRef!.dataset.path;
}

function _mmdInitReferenceClicks(): void {
  // #diagram-wrap は viewer.html に静的に存在する（truncation.ts の非 null 表明と同じ理由）。
  var wrap = document.getElementById('diagram-wrap')!;

  wrap.addEventListener('click', function (e) {
    // XSS から postMessage を自動発火させる攻撃を防ぐため、
    // ユーザー起因のイベントのみ処理する。
    if (!e.isTrusted) return;

    // ctrl+クリック(右クリック以外のボタンも含む)はコンテキストメニュー扱い。
    // macOS の WebKit は ctrl+左クリックで contextmenu に加え ctrlKey===true の
    // click も発火しうるため、ここで弾かないと NSMenu 表示と同時に現在タブの
    // 遷移も走ってしまう(OpenDisposition のドキュメント参照)。
    if (e.ctrlKey || e.button !== 0) return;

    var href = _mmdReferenceTargetHref(e);
    if (!href) return;

    // # で始まるアンカーリンクは JS 側で明示的にスクロールする
    // (decidePolicyFor が WKWebView のナビゲーションをキャンセルするため)
    if (href.charAt(0) === '#') {
      e.preventDefault();
      var id: string;
      try {
        id = decodeURIComponent(href.slice(1));
      } catch {
        // 不正な %エスケープを含む href は decode せず生のまま id として使う。
        id = href.slice(1);
      }
      var el =
        document.getElementById(id) || document.querySelector('[name="' + CSS.escape(id) + '"]');
      if (el) el.scrollIntoView({ behavior: 'smooth' });
      return;
    }

    e.preventDefault();

    // 多層防御: hostFeatures で無効化されたホスト(QuickLook 拡張等の静的1回描画)では
    // ここで抑止する(Swift 側もハンドラ未登録。ViewerWebView.messageHandlerNames 参照)。
    if (!isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation')) {
      return;
    }

    // <a> / .befold-path-ref とも同じ挙動。修飾キーの解釈は Swift 側(OpenDisposition)に
    // 集約しているため、ここでは押下状態をそのまま送るだけにする。
    _mmdPostMessage(_MSG_REFERENCE_ACTIVATED, {
      href: href,
      metaKey: e.metaKey,
      shiftKey: e.shiftKey,
    });
  });

  wrap.addEventListener('contextmenu', function (e) {
    if (!e.isTrusted) return;
    if (!isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation')) {
      return;
    }
    var href = _mmdReferenceTargetHref(e);
    // リンク/パス参照の上でなければ WKWebView 既定のメニューに任せる。
    if (!href || href.charAt(0) === '#') {
      return;
    }
    e.preventDefault();
    _mmdPostMessage(_MSG_REFERENCE_CONTEXT_MENU, { href: href });
  });
}

export { _mmdInitReferenceClicks };
