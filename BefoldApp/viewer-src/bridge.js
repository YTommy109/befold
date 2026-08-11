// Swift ホストとの境界。postMessage の送信口とホスト機能フラグの判定を持つ。
//
// メッセージ名は ViewerBridge.swift と同期する（ViewerBridgeContractTests が
// 成果物の文字列を照合する）。

var _MSG_ZOOM_CHANGED = 'zoomChanged';
var _MSG_REFERENCE_ACTIVATED = 'referenceActivated';
var _MSG_REFERENCE_CONTEXT_MENU = 'referenceContextMenu';
var _MSG_FIND_OPTIONS_CHANGED = 'findOptionsChanged';
var _MSG_SCROLL_POSITION_CHANGED = 'scrollPositionChanged';
var _MSG_LOAD_MORE_LINES = 'loadMoreLines';
var _MSG_RESOLVE_REFERENCES = 'resolveReferences';

// postMessage を一箇所に集約するヘルパー。ハンドラ未登録の WebView
// （例: 機能限定ホスト)でも安全に呼べるよう存在チェックを内包する。
// 実際に送れたかどうかを返す(応答を前提に状態を進める呼び出し側が、
// 送れなかった場合にその状態変更を取り消せるようにするため)。
function _mmdPostMessage(name, payload) {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
    window.webkit.messageHandlers[name].postMessage(payload);
    return true;
  }
  return false;
}

// ホスト機能フラグ(Swift 側が window._mmdHostFeatures として注入)を読む。
// 未注入、またはキー未指定の場合はその機能が有効であるとみなす
// (フラグを送らないホストは全機能サポートとして扱う後方互換のため)。
function isHostFeatureEnabled(hostFeatures, key) {
  if (!hostFeatures) { return true; }
  return hostFeatures[key] !== false;
}

export {
  _MSG_ZOOM_CHANGED,
  _MSG_REFERENCE_ACTIVATED,
  _MSG_REFERENCE_CONTEXT_MENU,
  _MSG_FIND_OPTIONS_CHANGED,
  _MSG_SCROLL_POSITION_CHANGED,
  _MSG_LOAD_MORE_LINES,
  _MSG_RESOLVE_REFERENCES,
  _mmdPostMessage,
  isHostFeatureEnabled,
};
