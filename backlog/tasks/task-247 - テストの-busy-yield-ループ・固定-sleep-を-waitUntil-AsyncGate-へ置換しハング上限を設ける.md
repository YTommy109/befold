---
id: TASK-247
title: テストの busy-yield ループ・固定 sleep を waitUntil/AsyncGate へ置換しハング上限を設ける
status: To Do
assignee: []
created_date: '2026-08-01 10:45'
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
- [ ] #1 上限なしループ・自作ポーリングが waitUntil 系(タイムアウト時 Issue.record)へ置換される
- [ ] #2 非同期スイートに testTimeLimit() が付与される
- [ ] #3 AsyncGate が BefoldTestSupport へ昇格し、固定 sleep(500ms / 50ms)が決定的待機へ置き換わる
- [ ] #4 実 WebView ロードテストが Integration 命名へ分離される
- [ ] #5 swift test が全てグリーン
<!-- AC:END -->
