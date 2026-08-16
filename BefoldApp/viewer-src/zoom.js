// 全体ズームとダイアグラム個別ズーム。倍率の保持・クランプ計算と、それを DOM へ
// 適用する処理を 1 モジュールに置く(適用側は倍率の持ち主を知らないと書けないため)。

import { _MSG_ZOOM_CHANGED, _mmdPostMessage } from './bridge.js';
import { _mmdDocPath } from './doc-path.js';

var ZOOM_MIN = 0.5;
var ZOOM_MAX = 2.0;
var ZOOM_STEP = 0.25;
var ZOOM_DEFAULT = 1;
var BASE_SCALE = 0.75;
// ダイアグラム個別ズームの上限。全体ズーム(ZOOM_MAX)より広く取り、細部の確認に使う。
var DIAGRAM_ZOOM_MAX = 3.0;

function clampZoom(z, max) {
  if (max === undefined) {
    max = ZOOM_MAX;
  }
  return Math.max(ZOOM_MIN, Math.min(max, z));
}

function stepZoom(current, delta, max) {
  return clampZoom(Math.round((current + delta) * 100) / 100, max);
}

function wheelZoom(current, deltaY, max) {
  return clampZoom(Math.round((current - deltaY * 0.01) * 1000) / 1000, max);
}

function zoomLabel(zoom) {
  return Math.round(zoom * 100) + '%';
}

function parseStoredZoom(raw) {
  var z = parseFloat(raw);
  return isNaN(z) ? ZOOM_DEFAULT : z;
}

// .diagram-zoom-scroll(枠)の高さ。ズーム後の実寸とビューポート上限の小さい方。
// naturalHeight は 100% 時のレイアウト px。上限は .viewer の上下 padding(32px×2)を
// 差し引いたビューポート高で、レイアウト px は祖先の CSS zoom の影響を受けないため
// 実ピクセルの viewportHeight を全体ズームぶん割り戻して比較する。
function diagramScrollHeight(naturalHeight, diagramZoom, viewportHeight, globalZoom) {
  var viewportCap = (viewportHeight - 64) / globalZoom;
  return Math.min(naturalHeight * diagramZoom * BASE_SCALE, viewportCap);
}

// ラスター画像の初期フィットサイズ。アスペクト比を保ったまま利用可能領域に
// 収まるよう縮小する(ナチュラルサイズより拡大はしない)。戻り値は px の
// 実数値(% ではない)。% で表現すると祖先の #diagram-wrap に適用される
// CSS zoom(全体ズーム)が相殺されてしまい、Cmd+/Cmd-/Cmd0 が効かなくなる
// (diagramScrollHeight と同様、レイアウト px は祖先の CSS zoom の影響を
// 受けないため、px 実数値であれば zoom がそのまま乗算されて効く)。
function imageFitSize(naturalWidth, naturalHeight, availWidth, availHeight) {
  if (naturalWidth <= 0 || naturalHeight <= 0 || availWidth <= 0 || availHeight <= 0) {
    return { width: naturalWidth, height: naturalHeight };
  }
  var scale = Math.min(1, availWidth / naturalWidth, availHeight / naturalHeight);
  return { width: naturalWidth * scale, height: naturalHeight * scale };
}

// 全体ズーム(⌘+/-/0・Ctrl+ホイール)・直近通知値・ダイアグラム個別ズームの 3 つを
// このストアのクロージャに閉じる。倍率のクランプは書き込みメソッド側で必ず行うため、
// 読み手(適用関数)は value() / diagramValue() の値をそのまま使える。
function _createZoomStore() {
  var zoom = ZOOM_DEFAULT;
  // 直近で postMessage した倍率。adoptStored() が注入値で初期化し、実際に変化した
  // 時だけ通知する（ページ初期化や render() のたびに UserDefaults へ書き込まれるのを防ぐ）。
  var lastPosted = ZOOM_DEFAULT;
  // ブロック順インデックス → ズーム倍率。セッション内のみ保持し、再レンダリング
  // をまたいで維持する（永続化はしない。ウィンドウを閉じるとリセット）。
  // markdown 編集でブロックの順番が変わるとズームが別のダイアグラムに付くが、
  // 影響がセッション内に限られるため許容する（設計書参照）。
  var diagramZooms = new Map();

  function diagramValue(index) {
    return diagramZooms.has(index) ? diagramZooms.get(index) : ZOOM_DEFAULT;
  }

  return {
    value: function () {
      return zoom;
    },
    // Swift が注入した保存値を採用する。範囲外の保存値はクランプした値を採用しつつ、
    // 直近通知値には注入値そのままを記録する: 次の takePostable() が補正後の値を
    // 通知対象として返し、Swift 側の保存値が正される。
    adoptStored: function (raw) {
      var parsed = parseStoredZoom(raw);
      zoom = clampZoom(parsed);
      lastPosted = parsed;
    },
    step: function (delta) {
      zoom = stepZoom(zoom, delta);
    },
    wheel: function (deltaY) {
      zoom = wheelZoom(zoom, deltaY);
    },
    reset: function () {
      zoom = ZOOM_DEFAULT;
    },
    // 直近通知値と変わっていれば通知すべき倍率を返し、同時に直近通知値を更新する。
    // 変わっていなければ null を返す（通知は不要）。
    takePostable: function () {
      if (zoom === lastPosted) {
        return null;
      }
      lastPosted = zoom;
      return zoom;
    },
    diagramValue: diagramValue,
    diagramStep: function (index, delta) {
      diagramZooms.set(index, stepZoom(diagramValue(index), delta, DIAGRAM_ZOOM_MAX));
    },
    diagramWheel: function (index, deltaY) {
      diagramZooms.set(index, wheelZoom(diagramValue(index), deltaY, DIAGRAM_ZOOM_MAX));
    },
    diagramReset: function (index) {
      diagramZooms.set(index, ZOOM_DEFAULT);
    },
  };
}

var _mmdZoom = _createZoomStore();

function _mmdInitZoom() {
  _mmdZoom.adoptStored(window._mmdInitialZoom);
  _mmdApplyZoom();
}

function _mmdApplyZoom() {
  var zoom = _mmdZoom.value();
  var wrap = document.getElementById('diagram-wrap');
  if (wrap.classList.contains('pdf-body')) {
    // iframe 内の PDF プラグイン描画には CSS zoom が効かないため、
    // iframe(=wrap)の寸法自体を倍率で変える。PDF は幅フィットで
    // 描画されるので、幅が広がるほど拡大表示になる。
    wrap.style.zoom = 1;
    wrap.style.width = zoom * 100 + '%';
    wrap.style.height = zoom * 100 + '%';
  } else {
    wrap.style.width = '';
    wrap.style.height = '';
    wrap.style.zoom = zoom;
  }
  // 枠高さの上限は全体ズームに依存する（レイアウト px への割り戻し）ため再計算する。
  _mmdUpdateAllDiagramScrollHeights();
  var postable = _mmdZoom.takePostable();
  if (postable !== null) {
    // path はこの倍率が属する文書(いま DOM に出ている文書)。倍率と同じターンで
    // 読んで載せるため、切替直後に配達された通知でも出所を取り違えない
    // (Swift 側の現在 URL を参照していた頃の誤保存 = TASK-391)。
    // 文書が定まらない間は null で、Swift 側はその通知を捨てる。
    _mmdPostMessage(_MSG_ZOOM_CHANGED, { zoom: postable, path: _mmdDocPath.current() });
  }
}

function _mmdZoomIn() {
  _mmdZoom.step(ZOOM_STEP);
  _mmdApplyZoom();
}

function _mmdZoomOut() {
  _mmdZoom.step(-ZOOM_STEP);
  _mmdApplyZoom();
}

function _mmdZoomReset() {
  _mmdZoom.reset();
  _mmdApplyZoom();
}

function _mmdWheelZoom(deltaY) {
  _mmdZoom.wheel(deltaY);
  _mmdApplyZoom();
}

// Ctrl+ホイール（トラックパッドのピンチ含む）はポインタ位置で振り分ける:
// ダイアグラム上ならそのダイアグラムの個別ズーム、それ以外は全体ズーム。
function _mmdInitWheelZoom() {
  document.addEventListener(
    'wheel',
    function (e) {
      if (!e.ctrlKey) {
        return;
      }
      e.preventDefault();
      var wrap = e.target instanceof Element ? e.target.closest('.diagram-zoom-wrap') : null;
      if (wrap) {
        _mmdDiagramWheelZoom(wrap, e.deltaY);
      } else {
        _mmdWheelZoom(e.deltaY);
      }
    },
    { passive: false },
  );
}

// ウィンドウリサイズで枠高さの上限(ビューポート高)や画像のフィットサイズが
// 変わるため追従させる。
function _mmdInitResize() {
  window.addEventListener('resize', function () {
    _mmdUpdateAllDiagramScrollHeights();
    var wrap = document.getElementById('diagram-wrap');
    var img = wrap.classList.contains('image-body') ? wrap.querySelector('img') : null;
    if (img && img.complete && img.naturalWidth) {
      _mmdFitImage(img, wrap);
    }
  });
}

// 画像のフィットサイズ(px 実数値)を再計算して適用する。
// wrap 自身に全体ズーム(CSS zoom)がかかっているため、wrap.clientWidth/Height は
// ローカル座標系で実ビューポート/zoom を返す(diagramScrollHeight と同じ理由)。
// フィット計算は実ビューポート基準で行う必要があるため zoom を掛けて実寸に戻す。
function _mmdFitImage(img, wrap) {
  var zoom = _mmdZoom.value();
  var fit = imageFitSize(
    img.naturalWidth,
    img.naturalHeight,
    wrap.clientWidth * zoom,
    wrap.clientHeight * zoom,
  );
  img.style.width = fit.width + 'px';
  img.style.height = fit.height + 'px';
}

// --- ダイアグラム個別ズーム ---
// 倍率そのものは _mmdZoom ストアが持つ（インデックス → 倍率）。ここにあるのは
// その値を DOM へ適用する側だけ。

function _mmdDiagramZoomValue(index) {
  return _mmdZoom.diagramValue(index);
}

function _mmdUpdateAllDiagramScrollHeights() {
  document.querySelectorAll('.diagram-zoom-wrap').forEach(function (wrap) {
    _mmdUpdateDiagramScrollHeight(wrap);
  });
}

// 枠(.diagram-zoom-scroll)の高さをズーム倍率とウィンドウ高に追従させる。
// 拡大時は枠がウィンドウ高まで伸び、収まらない分は枠内の縦スクロールで見る。
function _mmdUpdateDiagramScrollHeight(wrap) {
  var zoom = _mmdDiagramZoomValue(Number(wrap.dataset.diagramIndex));
  var naturalHeight = Number(wrap.dataset.naturalHeight);
  wrap.querySelector('.diagram-zoom-scroll').style.height =
    diagramScrollHeight(naturalHeight, zoom, window.innerHeight, _mmdZoom.value()) + 'px';
}

function _mmdApplyDiagramZoom(wrap) {
  var index = Number(wrap.dataset.diagramIndex);
  var zoom = _mmdDiagramZoomValue(index);
  wrap.querySelector('.diagram-zoom-inner').style.zoom = zoom * BASE_SCALE;
  _mmdUpdateDiagramScrollHeight(wrap);
  wrap.querySelector('.diagram-zoom-label').textContent = zoomLabel(zoom);
  wrap.querySelector('.diagram-zoom-in').disabled = zoom >= DIAGRAM_ZOOM_MAX;
  wrap.querySelector('.diagram-zoom-out').disabled = zoom <= ZOOM_MIN;
}

function _mmdDiagramZoomStep(wrap, delta) {
  _mmdZoom.diagramStep(Number(wrap.dataset.diagramIndex), delta);
  _mmdApplyDiagramZoom(wrap);
}

function _mmdDiagramZoomReset(wrap) {
  _mmdZoom.diagramReset(Number(wrap.dataset.diagramIndex));
  _mmdApplyDiagramZoom(wrap);
}

function _mmdDiagramWheelZoom(wrap, deltaY) {
  _mmdZoom.diagramWheel(Number(wrap.dataset.diagramIndex), deltaY);
  _mmdApplyDiagramZoom(wrap);
}

// CSP により動的生成要素へ onclick 属性は使わず addEventListener で配線する。
function _mmdBuildDiagramControls(wrap) {
  var controls = document.createElement('div');
  controls.className = 'diagram-zoom-controls';
  var zoomOut = document.createElement('button');
  zoomOut.className = 'diagram-zoom-out';
  zoomOut.title = '縮小';
  zoomOut.textContent = '−';
  zoomOut.addEventListener('click', function () {
    _mmdDiagramZoomStep(wrap, -ZOOM_STEP);
  });
  var label = document.createElement('span');
  label.className = 'diagram-zoom-label';
  label.title = 'クリックでリセット';
  label.addEventListener('click', function () {
    _mmdDiagramZoomReset(wrap);
  });
  var zoomIn = document.createElement('button');
  zoomIn.className = 'diagram-zoom-in';
  zoomIn.title = '拡大';
  zoomIn.textContent = '+';
  zoomIn.addEventListener('click', function () {
    _mmdDiagramZoomStep(wrap, ZOOM_STEP);
  });
  controls.appendChild(zoomOut);
  controls.appendChild(label);
  controls.appendChild(zoomIn);
  return controls;
}

// 各 .mermaid 要素をズーム用ラッパーで包む。SVG サイズ確定後
// （mermaid.run() 完了後）に呼ぶこと。
function _mmdWrapDiagrams(diagramWrap) {
  diagramWrap.querySelectorAll('.mermaid').forEach(function (el, i) {
    var wrap = document.createElement('div');
    wrap.className = 'diagram-zoom-wrap';
    wrap.dataset.diagramIndex = i;
    var scroll = document.createElement('div');
    scroll.className = 'diagram-zoom-scroll';
    var inner = document.createElement('div');
    inner.className = 'diagram-zoom-inner';
    el.parentNode.insertBefore(wrap, el);
    inner.appendChild(el);
    scroll.appendChild(inner);
    wrap.appendChild(scroll);
    wrap.appendChild(_mmdBuildDiagramControls(wrap));
    // 100% 時の自然高を記録し、枠高さの計算(_mmdUpdateDiagramScrollHeight)に使う。
    // この時点では inner にまだ zoom が適用されていないため素の実測値になる。
    wrap.dataset.naturalHeight = inner.offsetHeight;
    _mmdApplyDiagramZoom(wrap);
  });
}

export {
  ZOOM_MIN,
  ZOOM_MAX,
  ZOOM_STEP,
  ZOOM_DEFAULT,
  BASE_SCALE,
  DIAGRAM_ZOOM_MAX,
  clampZoom,
  stepZoom,
  wheelZoom,
  zoomLabel,
  parseStoredZoom,
  diagramScrollHeight,
  imageFitSize,
  _mmdZoom,
  _mmdInitZoom,
  _mmdApplyZoom,
  _mmdZoomIn,
  _mmdZoomOut,
  _mmdZoomReset,
  _mmdWheelZoom,
  _mmdInitWheelZoom,
  _mmdInitResize,
  _mmdFitImage,
  _mmdDiagramZoomValue,
  _mmdApplyDiagramZoom,
  _mmdDiagramZoomStep,
  _mmdDiagramZoomReset,
  _mmdBuildDiagramControls,
  _mmdWrapDiagrams,
};
