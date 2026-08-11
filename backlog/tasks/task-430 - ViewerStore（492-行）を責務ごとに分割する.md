---
id: TASK-430
title: ViewerStore（492 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-10 12:35'
updated_date: '2026-08-11 05:26'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/Viewer/ViewerStore.swift` は 492 行（`wc -l` 実測、2026-08-10 時点）で `BefoldApp/.swiftlint.yml:13-15` の `file_length` warning 400 を超えている。TASK-428 のラチェットを最終的に撤去して単純な閾値強制へ畳むには、この負債の返済が必要。

`ViewerStore` は `@MainActor @Observable` の中核状態で、`FileWatcher` からの変更を受けて `ViewerRenderer` の `evaluateJavaScript` へ伝搬する経路の中心にいる（`.claude/CLAUDE.md` のデータフロー記述）。分割時は状態の単一情報源が割れないことに注意する。

着手時に確認すべき制約: 既存テストが触る internal 面（`ViewerStoreTests.swift` 540 行 / `ViewerStoreChunkTests.swift` 392 行 / `ViewerStoreFileGoneTests.swift` 353 行が参照）は同名で到達できること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerStore.swift が file_length warning の 400 行以下になる
- [ ] #2 分割が行数回避ではなく責務単位になっている（各分割先が何を担うかを 1 行で言える）
- [ ] #3 状態の単一情報源が分割によって二重化していない
- [ ] #4 main との swiftlint 差分に真の新規が無い（/swiftlint-baseline の手順で確認）
- [ ] #5 swift test が既存どおり通る
<!-- AC:END -->
