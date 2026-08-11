// 読み込み時の副作用(DOM 取得・リスナ登録・注入値の反映)をすべてここへ集約する。
// 呼び出し順は分割前のトップレベル実行順そのまま。viewer.html は body 末尾で
// バンドルを読むため、この時点で DOM は構築済み。

import { onColorSchemeChange } from './color-scheme.js';
import { _mmdFind, _mmdInitFind } from './find.js';
import { _mmdInitCodeFont, _mmdInitFontSize } from './fonts.js';
import { _mmdInitKeyboard } from './keyboard.js';
import { _mmdInitMarkdown } from './markdown.js';
import { _mmdReinitializeMermaidIfLoaded } from './mermaid.js';
import { _mmdInitReferenceClicks } from './reference-clicks.js';
import { _mmdRerenderCurrent } from './render.js';
import { _mmdInitScrollNotify } from './scroll.js';
import { _mmdInitLoadMore } from './truncation.js';
import { _mmdInitResize, _mmdInitWheelZoom, _mmdInitZoom } from './zoom.js';

// カラースキームが切り替わったら mermaid を現在のテーマで初期化し直し、直近の内容を
// 再描画する。mermaid とレンダラの双方に用がある配線なので、どちらでもなく
// ここ(配線の場所)に置く。
function _mmdInitColorScheme() {
  onColorSchemeChange(function() {
    _mmdReinitializeMermaidIfLoaded();
    _mmdRerenderCurrent();
  });
}

function _mmdInit() {
  _mmdInitKeyboard();
  _mmdInitReferenceClicks();
  _mmdInitWheelZoom();
  _mmdInitResize();
  _mmdInitColorScheme();
  _mmdInitMarkdown();
  _mmdFind.initControls();
  _mmdInitScrollNotify();
  _mmdInitLoadMore();
  _mmdInitZoom();
  _mmdInitFontSize();
  _mmdInitCodeFont();
  _mmdInitFind();
}

export { _mmdInit };
