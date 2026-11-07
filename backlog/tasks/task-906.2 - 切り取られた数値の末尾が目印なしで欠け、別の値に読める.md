---
id: TASK-906.2
title: 切り取られた数値の末尾が目印なしで欠け、別の値に読める
status: To Do
assignee: []
created_date: '2026-11-07T02:56:00Z'
labels: []
dependencies:
  - TASK-906.1
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: high
type: bug
ordinal: 868000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
初期幅は 90 パーセンタイルなので、幅の広い最大 1 割の値は最初から切り取られる。201 行目以降の値は標本に入らず、同様に切り取られることがある。text-overflow: clip なので目印が無い。

実測（WKWebView、自作の最小 HTML）: 幅 90px の右寄せセルに 1,234,567,890,123 を入れると、右寄せにならず左端から始まって右が切れ（textLeft=8、textRight=150.8、セル右端 98）、1,234,567, 付近までしか見えない。金額の列では最大の値ほど桁が欠け、小さい値に読める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 切り取られたセルは、切り取られていることが見た目で分かる
- [ ] #2 `csv-num` の列では、初期幅の標本に含まれる値が切り取られない
- [ ] #3 上記をテストが検証している
- [ ] #4 `docs/dev/file-type-display.md` の「初期幅」「長い内容」が実装と一致している
<!-- AC:END -->
