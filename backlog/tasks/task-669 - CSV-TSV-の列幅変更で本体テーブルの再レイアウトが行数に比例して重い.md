---
id: TASK-669
title: CSV/TSV の列幅変更で本体テーブルの再レイアウトが行数に比例して重い
status: To Do
assignee: []
created_date: '2026-10-05 23:38'
labels: []
dependencies:
  - TASK-668
references:
  - 'https://github.com/YTommy109/befold/pull/708'
documentation:
  - docs/dev/file-type-display.md
priority: low
ordinal: 854000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-668 で fitColumn の測定対象を上位 200 セルに絞り、測定表の分は約 2.5 倍速くなったが、列幅を変えるたびに本体テーブル全体が再レイアウトされる分は残っている（行数に比例）。実アプリの resources を実 WKWebView で測った値（強制レイアウトを含む、ms）: フィット直後の追加コストは 10,000 行で 148〜616（初回の `csv-sized`＝`table-layout: fixed` への切替が約 606）、50,000 行で 788〜4,050（初回約 4 秒）。ドラッグ 1 move は 10,000 行で中央値 83・最大約 560、独立ハーネスでは 50,000 行で約 720。同期時間だけを測ると画面に出るまでの待ちが隠れる。原因の推測（`<col>` の幅変更で fixed レイアウトが全行を再計算する）は未検証。測定表を `#diagram-wrap` の外（body 直下）に置くと 2〜3ms だが、本番 CSS が効かず幅が +128px ずれるため使えなかった。利用者は現状ほぼ作者のみで、1 万行超の CSV での操作が対象。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 原因（どの操作が全行の再レイアウトを起こしているか）が実測で特定され、Notes に残っている
- [ ] #2 10,000 行でのドラッグ 1 move とフィット直後の強制レイアウト込みの時間が、対策前後で同じハーネス・同じ条件で実測され、数値が Notes に残っている
- [ ] #3 対策を入れる場合、選ばれる列幅・表示が現状と一致することがテストまたは実測で確認されている。入れない（許容範囲）と判断する場合は、その理由と閾値が Notes に残っている
- [ ] #4 方針に合わせて docs/dev/file-type-display.md の「フィット」の性能の記述が更新されている
<!-- AC:END -->
