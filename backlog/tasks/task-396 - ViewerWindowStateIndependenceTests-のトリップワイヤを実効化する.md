---
id: TASK-396
title: ViewerWindowStateIndependenceTests のトリップワイヤを実効化する
status: To Do
assignee: []
created_date: '2026-08-09 13:34'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 650000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の CONFIRMED 指摘 2 件。BefoldApp/befoldTests/ViewerWindowStateIndependenceTests.swift のテストが、コメント・表示名で謳っている回帰を実際には検知しない。

1. **restoresStoredStateWhenReopening（131 行付近）**: 表示名と doc コメントは「ライブ値は窓と共に死ぬ」「提示開始は保存値を読む」の両方を検証すると謳うが、実際には窓を 1 回開くだけで close→reopen を行わない。閉じた窓のライブ zoom/scroll が次の窓へ漏れる回帰（controller や store のキャッシュ再利用など）が起きてもこのスイートは通る。

2. **keepsLiveZoomWhenStoredZoomChanges（87 行付近）**: トリップワイヤコメントは「ViewerContentView へ ZoomStore を渡す形に戻すと、ここが落ちる」と主張するが、アサーションは `store.zoom == 1.25` のみ。ZoomStore を body で読む形へ戻しても（まさに TASK-388 の回帰経路）store.zoom は 1.25 のままでテストは通る。keepsLiveScrollPositionWhenStoredPositionChanges（111 行付近）にも同じ穴がある。

ADR 0002 と CLAUDE.md の「決めたことには、破れたら落ちるものを付ける」の担保がこのテストの存在意義なので、実際に落ちる形へ直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 close→reopen を実際に実行し、閉じた窓のライブ値が再オープン後の窓へ漏れると落ちるテストがある
- [ ] #2 ViewerContentView が ZoomStore/ScrollPositionStore を body で読む形へ戻ると落ちるテストがある（store のプロパティだけでなく描画へ渡る値を検証する）
- [ ] #3 トリップワイヤコメントの主張とテストが実際に検知する範囲が一致している
<!-- AC:END -->
