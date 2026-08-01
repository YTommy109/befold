---
id: TASK-252
title: テスト規約に CI 時間・並列性のルールを追記する（レビュー知見 6 件）
status: To Do
assignee: []
created_date: '2026-08-01 11:09'
updated_date: '2026-08-01 11:10'
labels: []
dependencies: []
priority: medium
type: docs
ordinal: 450100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-08-01 のテストコード全体レビュー(TASK-242〜251 の起票元)で、既存のテスト規約(docs/dev/coding_rule.md L512-771)に明文化されていなかったルールが 6 件顕在化した。同種の問題の再発を規約側で防ぐ。
追記する 6 件:
1. @Suite(.serialized) は根拠コメント必須とし、直列化が必要な最小スイートに限定する(資源基準線を読むテストだけ別スイートへ分割する。実例: GitCommandRunnerTests / FileWatcherIntegrationTests)
2. 待機ループは必ず上限つきにする(while + Task.yield の自作 busy-yield は上限なしだと回帰時に CI をタイムアウト上限まで占有する。waitUntil 系の Issue.record 付きヘルパーを使う)
3. テストフィクスチャは検証に必要な最小サイズにし、サイズの根拠(どの閾値に対する余裕か)をコメントで書く。繰り返し使う大きなフィクスチャは static let で 1 回生成に共有する(TSan 計装下では生成コストが数倍になる)
4. モデル状態のみを検証するテストで実 UI(NSWindow + WKWebView)をフル構築しない(TASK-242 のシーム導入後に、確定したシーム名で記述する。242 完了前に着手する場合はこの項目のみ保留し notes に残す)
5. @MainActor スイートは隔離が必要なテストに限定する。static 純関数のテストは非 MainActor スイートへ置き、並列レーンで走らせる
6. 否定検証(観測しない・発火しない)は固定タイムアウト待ちではなく、番兵(sentinel)で肯定的に配送完了を確認してから未観測を検証する(実例: DistributedAckWaiterIntegrationTests の改善方式)
既存の「発火しない検証は時限+0.3s」ルールとの関係(番兵が使える経路では番兵を優先、使えない時限系は +0.3s)も整理して書く。
注意: TASK-253(coding_rule.md の消費者別分割)が先に完了している場合は分割後の testing.md へ追記する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 6 件のルールがテスト規約に追記され、それぞれ根拠(なぜ CI 時間・安定性に効くか)と実例への言及を持つ
- [ ] #2 既存ルール(waitUntil 必須・時限+0.3s)との関係が矛盾なく整理されている
- [ ] #3 markdownlint-cli2 がパスする
<!-- AC:END -->
