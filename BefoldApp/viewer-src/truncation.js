// 段階読み込み中のバナー表示と「続きを読み込む」の要求。

import { _MSG_LOAD_MORE_LINES, _mmdPostMessage, isHostFeatureEnabled } from './bridge.js';
import { _mmdFind } from './find.js';

// 段階読み込み中(ファイルの一部だけを表示している間)のバナー表示を切り替える。
// failed が true の場合、チャンク読込エラーで打ち切られたことを示す。正常な
// 段階読込(「続きを読み込む」ボタン)とは異なる文言に切り替え、ボタンは隠す
// (再試行しても同じエラーになるため)。
function _mmdSetTruncated(isTruncated, lineCount, failed) {
  _mmdFind.setTruncated(isTruncated);
  var banner = document.getElementById('mmd-truncated-banner');
  if (!isTruncated) {
      banner.style.display = 'none';
      return;
  }
  banner.style.display = 'flex';
  var strings = window._mmdBannerStrings || {};
  var textEl = document.getElementById('mmd-truncated-text');
  var btn = document.getElementById('mmd-load-more-btn');
  if (failed) {
      textEl.textContent = strings.loadError || 'Failed to load the rest of the file';
      btn.style.display = 'none';
  } else if (typeof lineCount === 'number') {
      textEl.textContent = (strings.showing || 'Showing {count} lines').replace('{count}', lineCount);
      if (isHostFeatureEnabled(window._mmdHostFeatures, 'loadMore')) {
          btn.textContent = strings.loadMore || 'Load More';
          btn.style.display = 'inline-block';
      } else {
          btn.style.display = 'none';
      }
  } else {
      textEl.textContent = strings.showing
          ? strings.showing.replace('{count}', '?')
          : 'Showing partial content';
      btn.style.display = 'none';
  }
}

function _mmdLoadMore() {
  // 多層防御: ボタン非表示(_mmdSetTruncated 参照)だけでは XSS からの直接呼び出しを
  // 防げないため、ここでも hostFeatures を見て抑止する(Swift 側もハンドラ未登録)。
  if (!isHostFeatureEnabled(window._mmdHostFeatures, 'loadMore')) { return; }
  _mmdPostMessage(_MSG_LOAD_MORE_LINES, {});
}

// CSP のため onclick ではなく addEventListener で配線する。
function _mmdInitLoadMore() {
  document.getElementById('mmd-load-more-btn').addEventListener('click', function(e) {
    if (!e.isTrusted) return;
    _mmdLoadMore();
  });
}

export { _mmdSetTruncated, _mmdLoadMore, _mmdInitLoadMore };
