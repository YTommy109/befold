// 段階読み込み中のバナー表示と「続きを読み込む」の要求。

import { _mmdRequestMoreLines, isHostFeatureEnabled } from './bridge.js';
import { _mmdFind } from './find.js';
import { _mmdJump } from './jump.js';
import { _mmdLineReveal } from './reveal-line.js';

// 段階読み込み中(ファイルの一部だけを表示している間)のバナー表示を切り替える。
// failed が true の場合、チャンク読込エラーで打ち切られたことを示す。正常な
// 段階読込(「続きを読み込む」ボタン)とは異なる文言に切り替え、ボタンは隠す
// (再試行しても同じエラーになるため)。
// 要素 3 つは viewer.html に静的に置かれており、この関数が呼ばれる時点で必ず存在する。
// 非 null 表明（!）にしてあるのは、実行時の振る舞いを変えずに型を通すため。
// id が viewer.html 側で消えた場合は、表明の有無にかかわらず同じ行で
// TypeError になる（表明は検知を緩めていない）。
function _mmdSetTruncated(
  isTruncated: boolean,
  lineCount: number | undefined,
  failed: boolean,
): void {
  _mmdFind.setTruncated(isTruncated);
  _mmdJump.setTruncated(isTruncated);
  _mmdLineReveal.truncationChanged(isTruncated, failed);
  var banner = document.getElementById('mmd-truncated-banner')!;
  if (!isTruncated) {
    banner.style.display = 'none';
    return;
  }
  banner.style.display = 'flex';
  var strings: ViewerBannerStrings = window._mmdBannerStrings || {};
  var textEl = document.getElementById('mmd-truncated-text')!;
  var btn = document.getElementById('mmd-load-more-btn')!;
  if (failed) {
    textEl.textContent = strings.loadError || 'Failed to load the rest of the file';
    btn.style.display = 'none';
  } else if (typeof lineCount === 'number') {
    textEl.textContent = (strings.showing || 'Showing {count} lines').replace(
      '{count}',
      String(lineCount),
    );
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
  // 多層防御(hostFeatures の確認)は _mmdRequestMoreLines が持つ。
  _mmdRequestMoreLines();
}

// CSP のため onclick ではなく addEventListener で配線する。
function _mmdInitLoadMore() {
  document.getElementById('mmd-load-more-btn')!.addEventListener('click', function (e) {
    if (!e.isTrusted) return;
    _mmdLoadMore();
  });
}

export { _mmdSetTruncated, _mmdLoadMore, _mmdInitLoadMore };
