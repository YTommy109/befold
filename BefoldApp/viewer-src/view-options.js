// 表示モード・行番号・差分の設定を保持する。どれも Swift 側(ViewerWebView)が
// 変更直後に必ず render を送るため、ここは状態を持つだけで再描画はしない。

// モード切替の持ち越し。setViewMode() が mark() で立て、直後の描画後処理
// (_mmdFindRefreshAfterRender)が consume() で 1 度だけ取り出して検索位置の
// 先頭リセットに使う。書き手と読み手をこの 2 メソッドに限定することで、
// 「setViewMode → render」という順序前提を型で示す。
var _mmdModeSwitch = (function () {
  var pending = false;
  return {
    mark: function () {
      pending = true;
    },
    consume: function () {
      var value = pending;
      pending = false;
      return value;
    },
  };
})();

// モード切替の持ち越しを立てるのも setMode() の責務に含め、「変わったときだけ
// mark する」判定を旧モードを知っているこの owner に閉じる。
function _createViewOptions() {
  var mode = 'rendered';
  var lineNumbers = false;
  // ソース表示中に差し込む unified diff。null なら差分表示をしない。
  var diff = null;
  // 差分のレイアウト。'inline'(1 列) と 'side-by-side'(左右分割)。
  var diffLayout = 'inline';

  return {
    mode: function () {
      return mode;
    },
    setMode: function (newMode) {
      if (newMode !== 'rendered' && newMode !== 'source') {
        return;
      }
      if (newMode !== mode) {
        _mmdModeSwitch.mark();
      }
      mode = newMode;
    },
    lineNumbers: function () {
      return lineNumbers;
    },
    setLineNumbers: function (show) {
      lineNumbers = show;
    },
    diff: function () {
      return diff;
    },
    setDiff: function (text) {
      diff = typeof text === 'string' && text !== '' ? text : null;
    },
    diffLayout: function () {
      return diffLayout;
    },
    setDiffLayout: function (layout) {
      if (layout !== 'inline' && layout !== 'side-by-side') {
        return;
      }
      diffLayout = layout;
    },
  };
}

var _mmdViewOptions = _createViewOptions();

// 以下は Swift(evaluateJavaScript)から名前で呼ばれる入口。いずれも状態を持つだけで
// 再描画はしない: 呼び出し側(Swift)が常にこの直後に render() を送るため、
// ここで再描画すると古い内容による二重描画が発生する。

function setViewMode(mode) {
  _mmdViewOptions.setMode(mode);
}

// 行番号表示状態を更新する。ここで再描画すると全文再ハイライトが二重に走る。
function setLineNumbers(show) {
  _mmdViewOptions.setLineNumbers(show);
}

function setDiff(text) {
  _mmdViewOptions.setDiff(text);
}

function setDiffLayout(layout) {
  _mmdViewOptions.setDiffLayout(layout);
}

export { _mmdModeSwitch, _mmdViewOptions, setViewMode, setLineNumbers, setDiff, setDiffLayout };
