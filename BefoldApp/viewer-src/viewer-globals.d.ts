// Swift（ViewerBridge）が window へ注入する値の型宣言（TASK-432.4）。
//
// ここに書くのは「JS 側から見た受け取り方」だけで、注入する側の単一情報源は
// BefoldKit/ViewerBridge.swift にある。値そのものの一致は
// befoldTests/ViewerBridgeContractTests.swift が成果物 viewer-bundle.js を読んで
// 照合しており、この宣言と Swift がずれた場合はそちらが落ちる。
//
// すべて省略可能（? 付き）にしてあるのは、注入しないホストが実在するため。
// QuickLook 拡張のような機能限定ホストは一部のスクリプトを流さない。
// 「注入されていない」を型の上で消すと、実行時に undefined を掴む経路が
// 型検査を素通りする。

/// ViewerBridge.hostFeaturesScript(loadMore:spaceScroll:referenceActivation:) が注入する
/// ホスト機能フラグ。キー名の一致は ViewerBridgeContractTests が
/// `_mmdHostFeatures, "<key>"` の形で成果物を照合して担保している。
interface ViewerHostFeatures {
  loadMore?: boolean;
  spaceScroll?: boolean;
  referenceActivation?: boolean;
}

/// ViewerBridge.bannerStringsScript(bundle:) が注入する段階読み込みバナーの文言。
interface ViewerBannerStrings {
  showing?: string;
  loadMore?: string;
  loadError?: string;
}

/// ViewerBridge.findStringsScript(bundle:) が注入する検索バーの文言（8 キー）。
interface ViewerFindStrings {
  placeholder?: string;
  previous?: string;
  next?: string;
  matchCase?: string;
  matchWholeWord?: string;
  useRegularExpression?: string;
  close?: string;
  withinDisplayedRange?: string;
}

/// ViewerBridge.jumpStringsScript(bundle:) が注入する文書内ジャンプバーの文言。
interface ViewerJumpStrings {
  previous?: string;
  next?: string;
  close?: string;
  withinDisplayedRange?: string;
  /// 見出しレベルのトグルの説明。`{level}` を 1 / 2 / 3 で置換して使う。
  headingLevel?: string;
}

/// ViewerBridge.FindOptions（検索の 3 トグル）。
interface ViewerFindOptions {
  caseSensitive?: boolean;
  wholeWord?: boolean;
  useRegex?: boolean;
}

/// WKWebView が挿す message handler の口。ハンドラは Swift 側で
/// BridgeMessage.requiresInteractiveBridging によって選択的に登録されるため、
/// 名前で引いた結果が存在しないことがある。
interface WebKitMessageHandlers {
  [name: string]: { postMessage(payload: unknown): void } | undefined;
}

interface Window {
  webkit?: { messageHandlers?: WebKitMessageHandlers };

  // ViewerBridge.initialZoomScript(_:)
  _mmdInitialZoom?: number;
  // ViewerBridge.systemFontSizeScript(_:)
  _mmdSystemFontSize?: number;
  // ViewerBridge.monoFontFamilyScript(_:) — 未設定は空文字で注入される
  _mmdMonoFontFamily?: string;
  // ViewerBridge.codeFontSizeScript(_:) — 未カスタマイズは null が注入される
  _mmdCodeFontSize?: number | null;
  // ViewerBridge.hostFeaturesScript(loadMore:spaceScroll:referenceActivation:)
  _mmdHostFeatures?: ViewerHostFeatures;
  // ViewerBridge.bannerStringsScript(bundle:)
  _mmdBannerStrings?: ViewerBannerStrings;
  // ViewerBridge.initialFindOptionsScript(_:)
  _mmdInitialFindOptions?: ViewerFindOptions;
  // ViewerBridge.findStringsScript(bundle:)
  _mmdFindStrings?: ViewerFindStrings;
  // ViewerBridge.jumpStringsScript(bundle:)
  _mmdJumpStrings?: ViewerJumpStrings;
  // ViewerBridge.initialJumpLevelsScript(_:) が注入する保存済みの見出しレベル
  // （["h1","h2","h3"] 形式。空配列は「3 つとも OFF」で、未注入とは別）
  _mmdInitialJumpLevels?: string[];
}
