---
id: TASK-427
title: テスト終了後まで残る SlowFileReader の待機が run 全体を落とすのを構造的に塞ぐ
status: To Do
assignee: []
created_date: '2026-08-10 12:26'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRendererContentUpdateIntegrationTests の SlowFileReader は DispatchSemaphore を 1 回だけ signal してゲートを開ける形になっている。テスト終了後に走った再描画が readData を再び呼ぶと、その待機は誰にも signal されず、TASK-424 で入れた waitOrRecordTimeout の 15 秒上限に達して Issue.record する。この記録はどのテストにも紐づかないため `Test «unknown» recorded an issue at ViewerRendererContentUpdateIntegrationTests.swift:322` として現れ、全スイートが pass していても run 全体が exit 1 で落ちる。実測: PR #468 の CI（run 31386949217 / job 93449413264）で 1389 tests・202 suites すべて pass、ViewerRendererContentUpdateIntegrationTests スイート自体も pass しながらこの 1 件で失敗した。同じ job の再実行は pass しており、タイミング依存のフレーク。ゲートを『1 回 signal で 1 つだけ通す』形から『開いたら以後は待たない』形（LockedBox<Bool> 等のフラグを readData の先頭で見る）へ変えると、余分な readData が何回来ても待たずに通るため塞がる。DispatchSemaphore を余分に signal して数合わせをする方式は、カウントが初期値とずれた状態で解放されると libdispatch がプロセスごと落とすため採らない（同ファイル 120-122 行のコメント参照）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テスト本体がゲートを開けた後は、以降の readData が何回呼ばれても待機せずに通る
- [ ] #2 テスト終了後に残った readData が waitOrRecordTimeout の上限に達して «unknown» の Issue を記録する経路が無くなる
- [ ] #3 既存の 3 テスト（diffStateIsNotConfirmedBeforeRender / abortedRenderDoesNotLeaveOptionsInJS / staleImageEmbedDoesNotClobberNewerRender）が意図どおり中断を再現していることを、修正前に失敗する形で担保したまま保つ
- [ ] #4 フルスイートを 3 回連続実行して pass する
<!-- AC:END -->
