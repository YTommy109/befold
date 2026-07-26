---
id: TASK-72.1
title: WKWebView描画完了検知とappexバンドルリソース解決をプロトタイプ検証する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-19 06:44'
updated_date: '2026-07-26 05:10'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 211000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loadOneShot は WKWebView への描画予約までしか行わず、mermaid.js 等の非同期描画完了を通知するコールバックが現状ない。QuickLook のプレビュー表示タイミングを決めるために、ViewerRenderer に描画完了通知(onRenderComplete相当)を追加できるか検証する。また、appex バンドル内で BefoldKit の Bundle.befoldKitResources が正しく解決できるかを実機で確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WKWebView の描画完了(mermaid等の非同期処理完了含む)を検知する仕組みの設計案が明確になっている
- [x] #2 appex バンドル内で BefoldKit のリソース(viewer.html等)が解決できることを実機で確認している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## AC#1 描画完了検知の設計案

### 調査結果(現状)
- viewer-main.js:1418 `async function render(content, type, lang)` は既に async で、内部で
  `await _mmdRunMermaid(diagramWrap)` を待つ(mermaid の非同期描画完了を含む)。
  viewer-main.js は IIFE で包まれておらず classic script なので `render` はグローバル関数。
- Swift 側は ViewerRenderer+RenderHelpers.swift:89 で `webView.evaluateJavaScript(script)` の
  fire-and-forget。render が async のため、evaluateJavaScript は最初の await で即座に返る。
- 現状 JS→Swift の描画完了通知は存在しない(ViewerRenderer+MessageHandling.swift の
  受信メッセージは zoomChanged / referenceActivated / scrollPositionChanged /
  findOptionsChanged / loadMoreLines / resolveReferences のみ)。

### 単純化検討 → 採用案: postMessage ではなく callAsyncJavaScript で await する
当初案の「onRenderComplete 相当の postMessage コールバックを追加」は採らない。理由:
1. QuickLook プリセットは RendererFeatures.allowsInteractiveBridging=false で
   WKScriptMessageHandler を登録しない方針(RendererFeatures.swift:15-21)。
   postMessage 方式は「ブリッジ無効」と正面から矛盾し、完了通知のためだけに
   ハンドラを1つ復活させることになる。
2. `WKWebView.callAsyncJavaScript` は評価した JS が返す Promise の解決を待って
   completion を呼ぶ。`await render(...)` を投げるだけで、JS 側は無改造・
   新規メッセージ名ゼロ・状態フラグゼロで完了を検知できる。

採用スクリプト形:
    await render(<json>, '<type>'[, '<lang>']);
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
末尾の 2 段 rAF で DOM 更新後のレイアウト/ペイント完了まで含める。
contentWorld は `.page` を指定し、既存 evaluateJavaScript と同じグローバルを見る。

### 実装形(TASK-72.5 で入れる)
- 既存の updateContent / applyRender(通常ホストのライブ更新経路)は
  fire-and-forget のまま変更しない。one-shot 経路だけ「await 付き render」パスを持つ。
- ViewerBridge に renderScript を await 可能な形へ包む関数を追加する
  (renderScript の文字列生成は再利用する)。
- loadOneShot は現状 makeWebView → updateContent(pendingUpdate へ積む) で即 return する。
  これを (a) viewer.html の didFinish(isReady) を CheckedContinuation で待つ
  → (b) await 付き render を callAsyncJavaScript で評価、まで待つよう拡張する。
- QuickLook をハングさせないため全体にタイムアウト(目安 3s)を設け、
  超過時はその時点の DOM のまま完了扱いにする。

### 補足(リスク)
- render() の early return 経路(source mode / markdown-it 未ロード)でも Promise は
  解決するため待ちが残らない。_mmdRunMermaid は例外を握り潰すので reject もしない。

## AC#2 appex バンドルリソース解決
- BundleAccessor.swift:15 の非 SWIFT_PACKAGE 経路は `Bundle(for: BundleFinder.self)` で
  BefoldKit.framework 自身を返すため、ホストが app でも appex でも同じ解決になるはず。
- これを実機で確認するため、最小の appex ターゲット(スタブ QLPreviewingController)を
  project.yml に追加してビルドし、Bundle.befoldKitResources から viewer.html が
  取得できることを確認する。成果物は TASK-72.4 でそのまま育てる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 検証結果

### AC#1 描画完了検知(設計)
当初案の postMessage 型 onRenderComplete は採らず、callAsyncJavaScript で
`await render(...)` する案を採用。根拠は Implementation Plan に記載。
決め手は「QuickLook プリセットは allowsInteractiveBridging=false でメッセージ
ハンドラを登録しない方針であり、完了通知だけのためにブリッジを復活させるのは
設計が後退する」点と「render() が既に async で mermaid 描画完了まで await 済み」
であるため JS 側の改造が一切不要な点。

### AC#2 appex バンドルリソース解決(実機確認)
最小の app-extension ターゲット BefoldQuickLook を project.yml に追加し、
befold.app の Contents/PlugIns へ同梱してビルド → qlmanage -p で実行し、
appex プロセス内から os_log で解決結果を出力して確認した。

確認コマンド/結果:
- xcodebuild build -scheme befold → BUILD SUCCEEDED
- pluginkit -m -p com.apple.quicklook.preview -v → com.degino.befold.quicklook(1.7.2) が登録される
- qlmanage -p probe.mermaid で appex プロセス(BefoldQuickLook)が実際に起動する
  = dyld が LD_RUNPATH_SEARCH_PATHS(@executable_path/../../../../Frameworks)経由で
    BefoldKit.framework / BefoldRenderKit.framework の解決に成功している
- log show の出力:
    befoldKitResources: .../befold.app/Contents/Frameworks/BefoldKit.framework
    viewer.html:        .../befold.app/Contents/Frameworks/BefoldKit.framework/Resources/viewer.html
  → サンドボックス有効(com.apple.security.app-sandbox=true)の appex 内でも
    Bundle(for: BundleFinder.self) は正しくフレームワークバンドルを返す。

### 付随して判明したこと
- .mmd はシステム上 net.ia.markdown が先に取っており、befold の
  exported UTI com.degino.befold.mermaid-diagram には解決されなかった
  (.mermaid は解決される)。TASK-72.4 の QLSupportedContentTypes 設計で
  拡張子ベースの UTI 競合を考慮する必要がある。
- appex の CFBundleVersion / CFBundleShortVersionString は親アプリと一致必須
  (不一致だと ValidateEmbeddedBinary が警告する)。MARKETING_VERSION と
  CURRENT_PROJECT_VERSION を befold ターゲットと同値で設定した。

### 成果物の扱い
BefoldQuickLook ターゲット一式は検証用に作ったが破棄せず残す。
PreviewViewController は解決結果を表示するだけのスタブで、
Info.plist の QLSupportedContentTypes も mermaid-diagram 1 件のみ。
TASK-72.4(対象 UTI/entitlements の確定)と TASK-72.5(loadOneShot 呼び出し)で
このターゲットをそのまま育てる。

### 自動テスト
swift test → 697 tests / 99 suites すべてパス(回帰なし)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
描画完了検知は postMessage コールバックではなく callAsyncJavaScript で `await render(...)` する方式を採用する設計に決めた(render() は既に async で mermaid 描画完了まで await 済みのため JS 改造不要、かつ QuickLook プリセットのブリッジ無効方針と矛盾しない)。appex のリソース解決は、最小の app-extension ターゲット BefoldQuickLook を追加して実機ビルド・qlmanage -p で起動し、appex プロセスの os_log から Bundle.befoldKitResources が BefoldKit.framework を返し viewer.html を解決できることを確認した。swift test 697 件パス。
<!-- SECTION:FINAL_SUMMARY:END -->
