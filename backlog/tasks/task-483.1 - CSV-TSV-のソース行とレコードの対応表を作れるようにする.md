---
id: TASK-483.1
title: CSV/TSV のソース行とレコードの対応表を作れるようにする
status: To Do
assignee: []
created_date: '2026-08-14 12:46'
updated_date: '2026-08-14 13:29'
labels: []
milestone: m-4
dependencies: []
parent_task_id: TASK-483
priority: medium
type: task
ordinal: 701000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV/TSV のテーブル表示に差分を重ねるための土台。

git diff は行単位だが、CSV/TSV は 1 レコードが複数行にまたがりうる。`viewer-src/csv-html.js` の `tokenizeCsvRows` は RFC 4180 準拠でクォート内の改行を許容するため、引用符付きセルを含むファイルでは「ソースの N 行目」と「テーブルの N 行目」が一致しない。この対応を取らずに行番号をそのままテーブル行に当てると、色が別のレコードにずれる。

`tokenizeCsvRows` は value と raw の両方を返しているので、レコードごとの消費行数を数えれば対応表を作れる。ここではその対応付けだけを作り、差分の描画は次のサブタスクで行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 レコードごとに、そのレコードが占めるソース行の範囲が取得できる
- [ ] #2 引用符内に改行を含む CSV で、レコードとソース行の対応が正しいことがテストで確認できる
- [ ] #3 改行を含まない通常の CSV/TSV で、レコード番号とソース行番号が一致することがテストで確認できる
- [ ] #4 既存の CSV テーブル表示・CSV ソース表示の出力が変わっていない
<!-- AC:END -->
