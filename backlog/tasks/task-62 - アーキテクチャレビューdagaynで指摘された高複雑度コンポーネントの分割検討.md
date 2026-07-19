---
id: TASK-62
title: アーキテクチャレビュー(dagayn)で指摘された高複雑度コンポーネントの分割検討
status: Done
assignee:
  - '@claude'
created_date: '2026-07-18 23:56'
updated_date: '2026-07-19 01:41'
labels: []
dependencies: []
references:
  - dagayn architecture_analysis_tool(mode=overview/hubs)
  - refactor_tool(mode=suggest)による2026-07-19レビュー
priority: low
ordinal: 900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
dagayn の architecture_analysis_tool / refactor_tool(mode=suggest) が、行数・分岐数の観点で分割候補として ViewerStore.swift・ViewerWebView.Coordinator・FileListView.swift・BefoldKit/FileType.swift の4つを split_pressure 上位としてリードした。ViewerStore は TASK-1.4/TASK-29.4 で既に大きくリファクタ済みだが、現時点でも分岐数が高い。各ファイルについて単一責任の観点で分割の要否を評価し、価値がある場合のみ分割する（見送りも可）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerStore.swift(現344行/分岐52) の責務が単一責任原則に照らして評価され、分割するかしないかの判断が記録されている
- [x] #2 ViewerWebView.swift 内 Coordinator クラス(現674行中約236行/分岐65) について同様に評価・判断されている
- [x] #3 FileListView.swift(現325行/分岐37) について同様に評価・判断されている
- [x] #4 BefoldKit/FileType.swift(現178行/分岐48) について同様に評価・判断されている
- [x] #5 分割を見送った項目には理由(偽の抽象化になる/密結合で効果が薄い等)が記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. dagayn の指摘は commit 12e18b7 時点のグラフで、直近2コミット(ViewerWindowController減量・WKWebViewドライバのBefoldRenderKit抽出)が未反映。4対象を現状のソースで直接読み直して評価する。
2. ViewerStore.swift: TASK-1.4/29.4で既にI/O(ContentLoader/ViewerLoadPipeline)を分離済み。残る責務は「読み込み世代管理+状態一括適用」という単一の状態機械で、分岐はその整合性維持のため。分割は見送り。
3. ViewerWebView.Coordinator: 直近commit e5288feで既にBefoldRenderKit.ViewerRendererへ抽出済み(ViewerWebView.swiftは97行の薄いブリッジに縮小)。ただし抽出後のViewerRenderer.swift本体が383行でtype_body_length(warning 250/error 350)に接近しており、複雑度指摘は実質的に未解消と判断。DirectHTMLLinkPolicy/RenderHelpersに続く同一パターンで、WKScriptMessageHandler実装とupdateContent状態機械をそれぞれ ViewerRenderer+MessageHandling.swift / ViewerRenderer+ContentUpdate.swift に分離する。
4. FileListView.swift: 描画+コンテキストメニュー+クリップボード/Finder連携+キーボード操作が同居するが、いずれもmodel/コールバックへの依存が同一でMARKコメントによる境界も明示済み。分離しても密結合が解消せず効果が薄いため見送り。
5. BefoldKit/FileType.swift: 拡張子→FileTypeの単一情報源(typeByExtension)を中心にした値型で、分岐の大半はenumのswitch網羅性チェック(idiomatic Swift)。分割すると対応表が分散し二重管理になる偽の抽象化リスクが高いため見送り。
6. 各判断をACとしてチェックし、変更箇所はswift build/test + webview-smokeで検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 評価結果

**まず単純化の余地を検討**: dagaynの指摘はcommit 12e18b7時点のグラフで、直近のViewerWindowController減量(cade9a0)・WKWebViewドライバのBefoldRenderKit抽出(e5288fe)が未反映。新規の分割構造を導入する前に、まず現状のソースを読み直して「既存のリファクタで解消済みか」を確認した。結果、AC#2(旧Coordinator)は構造的にはBefoldRenderKitへの抽出で既に対応済みだったが、抽出後のViewerRenderer.swift本体(383行)がtype_body_length警告閾値(250)に接近しており、複雑度の指摘は実質未解消と判明。新しい抽象を増やすのではなく、既存の分割パターン(ViewerRenderer+DirectHTMLLinkPolicy.swift / +RenderHelpers.swift、コメントに「type_body_length対策」と明記済み)を踏襲する形で対応した。

### AC#1 ViewerStore.swift(344→331行) — 分割見送り
TASK-1.4/29.4で既にI/O(ContentLoader/ViewerLoadPipeline/FileReading)を分離済み。残る責務は「読み込み世代管理(loadGeneration) + 結果の状態一括適用(apply)」という単一の状態機械で、分岐の大半はレース(古い読み込みの追い越し・rename競合)を防ぐガード節。これ以上分割すると状態機械の整合性(filePath/fileType/contentを同時に確定させる制約、コメント参照)が複数箇所に分散し、かえって不整合のリスクが増す。見送り。

### AC#2 ViewerWebView.Coordinator → BefoldRenderKit.ViewerRenderer — 分割実施
直近commit e5288feで既にBefoldRenderKit.ViewerRendererへ抽出済み(ViewerWebView.swiftは97行の薄いNSViewRepresentableブリッジに縮小)。ただし抽出後のViewerRenderer.swift本体が383行でtype_body_length警告閾値(250)に接近していたため、既存パターン(DirectHTMLLinkPolicy分離時のコメント「type_body_length対策で本体の外のextensionに分離」)を踏襲し追加分割を実施:
- ViewerRenderer+MessageHandling.swift(60行): WKScriptMessageHandler実装 + WeakScriptMessageHandlerプロキシ
- ViewerRenderer+ContentUpdate.swift(118行): updateContent状態機械 + TruncationState
- 結果、ViewerRenderer.swift本体は383行→215行に縮小(閾値250を下回る)。
- swift build / swift test(386 tests)/ webview-smoke.swift(CSP・mmd/md描画・外部画像ブロック)で回帰なしを確認。

### AC#3 FileListView.swift(325行) — 分割見送り
描画(header/entryList/entryRow)・コンテキストメニュー(コピー/Finder表示)・キーボード操作(selectNext/Previous/handleKey)が同居する。ただしキーボード操作系はmodel.selectionとonSelect/onNavigateコールバックの両方に依存し、抽出しても同じ依存を新しい型に持ち込むだけで疎結合化の効果が薄い。既にMARKコメント(Context Menu/Click/Keyboard Navigation)で責務境界が明示され、テスト用にinternalメソッド化(コメントに理由明記)済みで実用上のテスト容易性は確保されている。抽出は密結合で効果が薄い偽の抽象化リスクが高いため見送り。

### AC#4 BefoldKit/FileType.swift(178行) — 分割見送り
拡張子→FileTypeの単一情報源(typeByExtension、コメントに「init(url:)とallExtensionsの唯一の情報源」と明記)を中心にした値型。分岐の大半は enum の網羅的switch(jsValue/codeLanguage/isBinaryContent等)によるもので、Swiftのenumパターンとして idiomatic。分割すると対応表や判定ロジックが複数ファイルに分散し、単一情報源という設計意図に反する二重管理(偽の抽象化)を招くため見送り。

### AC#5 見送り理由の記録
上記AC#1/3/4の各項に見送り理由(密結合で効果が薄い/偽の抽象化になる)を記載済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
dagaynの指摘(commit 12e18b7時点)は直近2コミットの既存リファクタ(ViewerWindowController減量・WKWebViewドライバのBefoldRenderKit抽出)を未反映だったため、まず現状ソースを直接読み直して4対象を再評価した。

- ViewerStore.swift: 既にI/O分離済みの単一状態機械。分割見送り(整合性分散リスク)。
- ViewerWebView.Coordinator→BefoldRenderKit.ViewerRenderer: 構造抽出は既に完了していたが、抽出後の本体(383行)がtype_body_length警告閾値(250)に接近していたため、既存の分割パターン(+DirectHTMLLinkPolicy/+RenderHelpers)を踏襲してViewerRenderer+MessageHandling.swift(60行)/+ContentUpdate.swift(118行)へ追加分割。本体は383→215行に縮小。
- FileListView.swift: 描画とキーボード操作は同一の依存(model/コールバック)を共有し分離しても疎結合化しないため見送り。
- BefoldKit/FileType.swift: 拡張子→型の単一情報源を持つ値型で、分岐はenum網羅switchのidiomなパターン。分割は対応表の二重管理(偽の抽象化)を招くため見送り。

検証: swift build 成功、swift test(386件)全通過、scripts/webview-smoke.swift(CSP・mmd/md描画・外部画像ブロック)PASS。
<!-- SECTION:FINAL_SUMMARY:END -->
