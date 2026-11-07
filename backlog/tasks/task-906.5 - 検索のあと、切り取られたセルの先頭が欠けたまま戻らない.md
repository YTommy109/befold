---
id: TASK-906.5
title: 検索のあと、切り取られたセルの先頭が欠けたまま戻らない
status: To Do
assignee: []
created_date: '2026-11-07T02:56:00Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: medium
type: bug
ordinal: 871000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find-host.ts のスクロール処理は overflow: hidden の要素も対象にする（/^(auto|scroll|hidden)$/）ので、切り取られた部分にあるヒットへ移動すると td を内部でスクロールする。スクロールバーが無いのでユーザーは戻せず、再描画まで値の先頭が欠けて見える。

実測（WKWebView、自作の最小 HTML）: overflow: hidden の td で scrollTo が効き、scrollLeft=120 のまま残る。検索経由の動作そのものは未実測。

overflow: clip にするとセルは動かないが、ヒットが見えなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 切り取られた部分にあるヒットへ移動すると、ヒットが見える
- [ ] #2 別のヒットへ移動するか検索を閉じると、セルの表示位置が先頭へ戻る
- [ ] #3 上記をテストまたは実機で確認した結果が Notes にある
<!-- AC:END -->
