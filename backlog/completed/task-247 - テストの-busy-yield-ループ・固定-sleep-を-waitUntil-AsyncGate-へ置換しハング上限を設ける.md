---
id: TASK-247
title: テストの busy-yield ループ・固定 sleep を waitUntil/AsyncGate へ置換しハング上限を設ける
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 10:45'
updated_date: '2026-08-01 15:02'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 449000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI レビューで、待機まわりに規約違反(独自ポーリングループ禁止・非同期テストは timeLimit 必須)と最悪ケースで CI をタイムアウト上限まで浪費するハングリスクが見つかった。
- ViewerRendererContentUpdateTests.swift:20-125 に上限なし busy-yield ループ(while !renderer.isReady { await Task.yield() })が 5 箇所。スイートに timeLimit がなく、WebView が ready にならない回帰で無期限ハング。waitUntilOnMainActor(Issue.record 付き)+ @Suite(testTimeLimit()) へ
- 同 :129 の固定 500ms sleep(stale 埋め込み非上書き確認)は AsyncGate 方式で決定化
- ViewerRendererMessageHandlingTests.swift:165-167, 191-198, 212-214 の自作 yield ループ 3 箇所も同様
- ViewerWindowControllerToolbarTests.swift:87-93 はポーリング各周回で NSToolbarItem+NSButton を作り直している。:147 と同じ await controller.store.loadTask?.value 方式で決定化(:199 も同様)
- DistributedAckWaiterIntegrationTests.swift:9 / CLIRequestWireIntegrationTests.swift:14 に timeLimit なし
- ViewerStoreFileGoneTests.swift:10-40 の AsyncGate は依存が Foundation のみで BefoldTestSupport へ昇格でき、上記の固定待ち置換と ViewerRendererResolveReferencesTests.swift:57 の 50ms sleep 置換に使える
- 実 WKWebView をロードする ViewerRendererContentUpdateTests の 3 本と ViewerRendererOneShotTests.swift:144-165 は規約の判定基準に照らし Integration 命名へ分離する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 上限なしループ・自作ポーリングが waitUntil 系(タイムアウト時 Issue.record)へ置換される
- [x] #2 非同期スイートに testTimeLimit() が付与される
- [x] #3 AsyncGate が BefoldTestSupport へ昇格し、固定 sleep(500ms / 50ms)が決定的待機へ置き換わる
- [x] #4 実 WebView ロードテストが Integration 命名へ分離される
- [x] #5 swift test が全てグリーン
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装エージェントがセッション上限で停止したため、メインエージェントが引き継いで完了させた(コミット 19daffb / 583d9c9)。引き継ぎ時点でビルドが壊れており(ViewerRendererContentUpdateTests に import BefoldTestSupport の追加漏れ)、それを修正してから残作業を実施した。
残作業として実施した内容: ViewerRendererMessageHandlingTests の上限なし yield ループ 4 箇所を waitUntilYielding(タイムアウト時 Issue.record)へ / CLI の 2 つの Integration スイートへ testTimeLimit() 付与 / ViewerRendererResolveReferencesTests の 50ms 固定 sleep を AsyncGate による決定的な待機へ / ViewerRendererOneShotTests の実 WKWebView 経路 3 本を ViewerRendererOneShotIntegrationTests へ分離。
ViewerWindowControllerToolbarTests のポーリングは置換しなかった。現行コードは既にポーリング中に掴んだボタンを箱へ退避しており(TASK-51 の CI フレーク修正の成果)、await の再開点を挟む取り直しの問題は解消済み。loadTask 待ちへ変えるとその修正意図を壊すリスクがあるため現状維持とした。
実測の位置づけ: 対象スイートは単独実行で 0.15〜0.76 秒しかかからず、全体(約 13s)への寄与はほぼゼロ。本タスクの価値は実行時間短縮ではなく、回帰時に上限なしループが実行を占有する事故を防ぐことにある。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
上限のない待機ループと固定 sleep を決定的な待機へ置き換え、非同期スイートにタイムリミットを与えた。
変更点: (1) ViewerRendererContentUpdateTests / ViewerRendererMessageHandlingTests の上限なし yield ループを waitUntilYielding(超過時 Issue.record)へ置換 (2) AsyncGate を BefoldTestSupport へ昇格し、500ms / 50ms の固定 sleep を決定的なゲート制御へ (3) CLI の 2 Integration スイートと ViewerRenderer 系スイートに testTimeLimit() を付与 (4) 実 WKWebView をロードする経路を ViewerRendererContentUpdateIntegrationTests / ViewerRendererOneShotIntegrationTests へ分離。
効果: 実行時間ではなく安全性。回帰でフラグが降りなくなった場合に、上限なしループがタイムリミット(CI では最大 120 秒)まで実行を占有する事故を防ぐ。対象スイートは元々全体時間にほぼ寄与しない(単独 0.15〜0.76 秒)。
検証: swift test 1006 tests / 139 suites グリーン、swiftformat 差分なし、swift build 警告なし。
<!-- SECTION:FINAL_SUMMARY:END -->
