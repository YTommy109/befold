---
id: TASK-906.6
title: 'PR #748 の軽微な指摘（後から増えた列・重複・古い記述）を片付ける'
status: To Do
assignee: []
created_date: '2026-11-07T02:56:00Z'
labels: []
dependencies:
  - TASK-906.3
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: low
type: task
ordinal: 872000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
レビューの軽微な指摘をまとめたもの。201 行目以降で初めて値が出る列は 40px から始まる（仕様書に明記された制限）。測定表を作る処理が fitColumn と initialWidths で重複し、360 と 0.9 が名前の無い数値のまま。テスト名「増えた列は自然幅にする」とそのコメント、style.css の「table は自然幅または明示的な列幅で描き」が実装と合っていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 追記で増えた列は、追記された行も幅の測定対象になる
- [ ] #2 測定表を作る処理が 1 か所にある
- [ ] #3 初期幅の上限と分位点が名前付き定数になっている
- [ ] #4 テスト名・コメント・`style.css` のコメントが実装と一致している
<!-- AC:END -->
