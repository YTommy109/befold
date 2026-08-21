---
id: TASK-485.19.5
title: 'Swift側: 既定モード選択とEditメニューの実体差し替え'
status: Done
assignee:
  - '@claude'
created_date: '2026-08-21 09:12'
updated_date: '2026-08-21 12:12'
labels: []
dependencies:
  - TASK-485.19.3
  - TASK-485.19.4
parent_task_id: TASK-485.19
priority: high
ordinal: 779000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WebViewCommandController に openBar(kind: DocumentJumpKind?) 相当の単一入口を作る。

- kind が nil（⌘F 相当の非明示オープン）のときだけ showsDiff を見て
  既定を search / changeBlock に分岐する
- kind 明示時（Edit > 見出しへジャンプ / 変更箇所へジャンプ）は常にそのモードを強制する
  （ユーザー承認済み方針: 現行の2メニュー項目は残し、実体だけ統合バーの該当モードへの
  切替えに差し替える）
- documentJump(_:)（ViewerWindowController+MenuActions.swift:60-63）と
  openFind()（WebViewCommandController.swift:96-98）をこの入口へ収斂させる
- ViewerWindowController / MainMenuBuilder 型グループの行数増分を確認する
  （実測: ViewerWindowController群896行/閾値1000、MainMenuBuilder群377行。
  scripts/check-type-group-size.sh で増分後も確認する）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ⌘Fで開いたとき、差分表示モードでは変更箇所モードが既定で選ばれる
- [x] #2 Edit > 見出しへジャンプ / 変更箇所へジャンプ は常に明示したモードで開く
- [x] #3 openFind() と documentJump(_:) が単一の入口関数に収斂している
- [x] #4 ViewerWindowController / MainMenuBuilder 型グループが閾値を超えていない（超える場合は受け皿を決めている）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
responsibility-reviewerサブエージェントで重大な指摘(High)を受け、修正した: 当初 openBar(kind:) は capabilities().showsDiff だけで既定モードを分岐していたが、これは ViewerCapabilities.canJumpToChangeBlock（canJump && showsDiff、既にADR 0002段2「条件は1箇所」の単一情報源として存在）を迂回する再実装だった。差分表示中でも文書内ジャンプの能力が無い（FeatureGate.isDocumentJumpEnabled閉・HTML直接ロード中）場合、showsDiffだけを見るとopenJump(kind: .changeBlock)を呼んでしまいopenJump内部のcanJump(to:)guardで無言no-opになり、⌘Fが何も開かなくなる回帰だった（未テストの組み合わせで発見）。

修正: ViewerCapabilities に showsDiff の stored property を追加する代わりに、canJumpToChangeBlock を経由する computed property `defaultBarKind: DocumentJumpKind?` を追加し、openBar はそれを使うよう変更（showsDiff の直接公開は撤回）。回帰を再現する新規テストを追加し、修正前のコードに戻すと実際に落ちることを実測してから復元した。

Medium指摘（既定モード選択ロジックの置き場所）への対応として、選択ポリシー自体を ViewerCapabilities.defaultBarKind へ委譲し、WebViewCommandController.openBar は `kind ?? capabilities().defaultBarKind` を見て呼び分けるだけの薄い委譲に留めた。Low指摘（openFind/openJumpへの直接呼び出しを防ぐ手立てが無い）には、doc commentに「本番コードからはopenBar経由」の逆参照を追記して対応（強制はできないが次に触る人への手がかりとして）。

refreshToolbarState() → refreshUIState() のリネームは、SidebarHost.swift内の既存TODOコメント（「バーを作り替えるTASK-485.19で改名する」）どおりに実施。呼び出し元9箇所を機械的に追随（GlobalDisplayBroadcaster / ViewerDisplayOptionsApplier / ViewerWindowAssembler×2 / ViewerWindowController+MenuActions×2 / ViewerWindowController.swift / ViewerWindowController+FileNavigation.swiftのコメント2箇所）。ロジック変更なし。

WebViewCommandControllerTests.swiftが419行に達しswiftlintのfile_length警告（main比較で新規）を検知したため、統合バー関連テスト5件をWebViewCommandController+OpenBarTests.swiftへ分割（358行/84行）。FakeDocumentRenderer/makeController/ZoomChangeRecorder/ScrollSaveRecorderをprivateからinternalへ変更（Swiftのprivateはファイルスコープのため分割先extensionから見えなくなる）。

検証: swift test 1578/1578通過、swiftlintベースライン差分ゼロ（main比較、54=54）、swiftformat差分なし、型グループ実測 ViewerWindowController 897行/閾値1000、MainMenuBuilder 377行/閾値1000、WebViewCommandController 187行、ViewerCapabilities 146行。docs/dev/native-app-design.mdへ統合バーの構成（#mmd-bar・bar-mode.ts・openBar(kind:)・defaultBarKind）を反映し、refreshToolbarState()の参照も修正した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
WebViewCommandController.openBar(kind:)を単一入口として追加し、openFind()/documentJump(_:)をこれへ収斂させた。既定モード選択はViewerCapabilities.defaultBarKind(canJumpToChangeBlock経由)に委譲し、responsibility-reviewerが発見した回帰(showsDiff直接参照によるフィーチャーゲート迂回、⌘Fが無反応になるケース)を修正・テストで固定した。refreshToolbarState()→refreshUIState()の既存TODOリネームも実施。swift test 1578/1578通過、swiftlintベースライン差分ゼロ、型グループ閾値内。native-app-design.mdを更新した。
<!-- SECTION:FINAL_SUMMARY:END -->
