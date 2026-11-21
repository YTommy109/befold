---
id: TASK-483.1
title: CSV/TSV のソース行とレコードの対応表を作れるようにする
status: Done
assignee:
  - '@claude'
created_date: 2026-08-14 12:46
updated_date: '2026-11-21T00:09:00Z'
labels:
  - diff
  - csv
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

git diff は行単位だが、CSV/TSV は 1 レコードが複数行にまたがりうる。`viewer-src/csv-html.ts` の `tokenizeCsvRows` は RFC 4180 準拠でクォート内の改行を許容するため、引用符付きセルを含むファイルでは「ソースの N 行目」と「テーブルの N 行目」が一致しない。この対応を取らずに行番号をそのままテーブル行に当てると、色が別のレコードにずれる。

`tokenizeCsvRows` は value と raw の両方を返しているので、レコードごとの消費行数を数えれば対応表を作れる。ここではその対応付けだけを作り、差分の描画は次のサブタスクで行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 レコードごとに、そのレコードが占めるソース行の範囲が取得できる
- [x] #2 引用符内に改行を含む CSV で、レコードとソース行の対応が正しいことがテストで確認できる
- [x] #3 改行を含まない通常の CSV/TSV で、レコード番号とソース行番号が一致することがテストで確認できる
- [x] #4 既存の CSV テーブル表示・CSV ソース表示の出力が変わっていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. csv-html.ts に csvRecordLineRanges(content, delimiter) を足す（tokenizeCsvRows の raw に残る引用符内の \n を数えてレコードごとの [start, end) を返す純関数）
2. 新旧どちら側の全文にも使えるよう引数は任意のテキストにする（483.2 で削除レコードを旧側から引くため）
3. 単体テスト（通常 CSV/TSV・引用符内改行・CRLF・空行・空文字列）
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-src/csv-html.ts に csvRecordLineRanges を追加した。テーブル表示と同じ tokenizeCsvRows を使い、セルの raw に残る引用符内の改行を数えてレコードごとのソース行範囲（0 始まり半開区間）を返す。既存関数は変更しておらず、テーブル表示・ソース表示の出力は不変（jest 全 775 件通過）。テスト: viewer-test/viewer-csv-record-lines.test.ts。描画への組み込みは TASK-483.2。
<!-- SECTION:FINAL_SUMMARY:END -->
