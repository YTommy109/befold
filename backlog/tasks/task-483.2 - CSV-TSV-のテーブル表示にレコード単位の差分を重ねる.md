---
id: TASK-483.2
title: CSV/TSV のテーブル表示にレコード単位の差分を重ねる
status: To Do
assignee: []
created_date: '2026-08-14 12:46'
labels: []
dependencies:
  - TASK-483.1
parent_task_id: TASK-483
priority: medium
type: feature
ordinal: 702000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV/TSV をテーブル表示したまま、追加・削除されたレコードを色分けして表示する。

`viewer-src/csv-html.js` の `buildTableHtml` が組み立てる `<tr>` に、既存の `diff-add` / `diff-del` クラス（`BefoldKit/Resources/style.css` に定義済み）を当てる。削除されたレコードは新しい内容には存在しないため、削除行として表に挿入する。

差分の入口を開けるため、`BefoldKit/FileType.swift` の `supportsDiffDisplay` から `.csv` の除外を外し、`viewer-src/renderers.js` の `type === "csv"` による早期 return も見直す。`render.js` の `renderShape` で `csv-table` の分岐が差分を通るようにする必要がある。

セル単位の色分け（追加行と削除行をペアリングして値の違う `<td>` だけ光らせる）は、`diff-html.js` の `pairDiffLines` が再利用できるが、まずレコード単位で成立させることを優先し、セル単位は必要と判断した場合のみ同タスク内で追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV/TSV でテーブル表示のまま差分表示モードを選べる
- [ ] #2 追加されたレコードが追加色、削除されたレコードが削除色で表示される
- [ ] #3 引用符内に改行を含む CSV でも、色が正しいレコードに当たる
- [ ] #4 差分が取得できない場合（未追跡・バイナリ・変更なし・サイズ超過）は通常のテーブル表示に落ちる
- [ ] #5 差分表示中のチャンク追記が表を壊さない
<!-- AC:END -->
