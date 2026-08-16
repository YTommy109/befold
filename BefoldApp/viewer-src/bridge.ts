// Swift ホストとの境界。postMessage の送信口とホスト機能フラグの判定を持つ。
//
// メッセージ名は ViewerBridge.swift と同期する（ViewerBridgeContractTests が
// 成果物の文字列を照合する）。
//
// 型（TASK-432.4）は手書きせず、下のリテラルから `as const` で導出している。
// 型を別に宣言すると、Swift・JS の値・JS の型の 3 つを揃える羽目になる。
// 値の一致は既に ViewerBridgeContractTests が担保しているので、その値だけを
// 単一情報源にする。
//
// **この宣言の形は変えないこと。** 契約テストは成果物を
// `(?:var|let|const)\s+(_MSG_[A-Z_]+)\s*=\s*"..."` で拾い、
// 送信サイトを `_mmdPostMessage(_MSG_*, { ... })` の直書きリテラルで拾う。
// オブジェクトへ畳んだり、ペイロードを変数へ逃がしたりすると抽出が空振りする
// （空振り自体は declaredMessagesHavePostSites が落として気づける）。

var _MSG_ZOOM_CHANGED = 'zoomChanged' as const;
var _MSG_REFERENCE_ACTIVATED = 'referenceActivated' as const;
var _MSG_REFERENCE_CONTEXT_MENU = 'referenceContextMenu' as const;
var _MSG_FIND_OPTIONS_CHANGED = 'findOptionsChanged' as const;
var _MSG_SCROLL_POSITION_CHANGED = 'scrollPositionChanged' as const;
var _MSG_LOAD_MORE_LINES = 'loadMoreLines' as const;
var _MSG_RESOLVE_REFERENCES = 'resolveReferences' as const;

/// JS → Swift のメッセージ名。上のリテラルから導出しているので、
/// 名前を足す・変えるときに書き換える場所は値の 1 箇所だけ。
type ViewerMessageName =
  | typeof _MSG_ZOOM_CHANGED
  | typeof _MSG_REFERENCE_ACTIVATED
  | typeof _MSG_REFERENCE_CONTEXT_MENU
  | typeof _MSG_FIND_OPTIONS_CHANGED
  | typeof _MSG_SCROLL_POSITION_CHANGED
  | typeof _MSG_LOAD_MORE_LINES
  | typeof _MSG_RESOLVE_REFERENCES;

// postMessage を一箇所に集約するヘルパー。ハンドラ未登録の WebView
// （例: 機能限定ホスト)でも安全に呼べるよう存在チェックを内包する。
// 実際に送れたかどうかを返す(応答を前提に状態を進める呼び出し側が、
// 送れなかった場合にその状態変更を取り消せるようにするため)。
function _mmdPostMessage(name: ViewerMessageName, payload: object): boolean {
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name]) {
    // WKWebView のスクリプトメッセージ経路であって window.postMessage ではない。
    // targetOrigin という引数がそもそも無い。
    // oxlint-disable-next-line unicorn/require-post-message-target-origin
    window.webkit.messageHandlers[name].postMessage(payload);
    return true;
  }
  return false;
}

// ホスト機能フラグ(Swift 側が window._mmdHostFeatures として注入)を読む。
// 未注入、またはキー未指定の場合はその機能が有効であるとみなす
// (フラグを送らないホストは全機能サポートとして扱う後方互換のため)。
function isHostFeatureEnabled(
  hostFeatures: ViewerHostFeatures | undefined,
  key: keyof ViewerHostFeatures,
): boolean {
  if (!hostFeatures) {
    return true;
  }
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
