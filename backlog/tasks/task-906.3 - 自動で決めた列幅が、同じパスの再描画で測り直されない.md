---
id: TASK-906.3
title: 自動で決めた列幅が、同じパスの再描画で測り直されない
status: To Do
assignee: []
created_date: '2026-11-07T02:56:00Z'
labels: []
dependencies:
  - TASK-906.2
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: high
type: bug
ordinal: 869000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
自動で決めた幅と手動で変えた幅が同じ widths に入っている。prepareCsvResize は同じパスでは widths を捨てないので、initialWidths の対象が空になり測り直されない。

影響（コードからの判断、未実測）: ヘッダーだけの CSV に行が増えてもヘッダー幅のまま。保存で値が長くなっても切り取られたまま。桁区切りの設定変更は再描画するが幅は変わらず、数値の切り取りが悪化する。ファイル監視が中心機能なので、普通に起きる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同じパスの再描画で、手動で変えていない列は測り直される
- [ ] #2 手動で変えた列の幅は、同じパスの再描画でも保持される
- [ ] #3 チャンク追記では、自動の幅も手動の幅も変わらない
- [ ] #4 ヘッダーだけの CSV に行が増える場合と、桁区切りの設定変更の場合をテストが検証している
- [ ] #5 `docs/dev/file-type-display.md` の「寿命」が実装と一致している
<!-- AC:END -->
