---
id: TASK-483.2
title: CSV/TSV のテーブル表示にレコード単位の差分を重ねる
status: To Do
assignee: []
created_date: 2026-08-14 12:46
updated_date: '2026-11-20T14:33:00Z'
labels:
  - diff
  - csv
milestone: m-4
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

`viewer-src/csv-html.ts` の `buildTableHtml` が組み立てる `<tr>` に、既存の `diff-add` / `diff-del` クラス（`BefoldKit/Resources/style.css` に定義済み）を当てる。削除されたレコードは新しい内容には存在しないため、削除行として表に挿入する。差分ジャンプが効くよう、変更のある行には `data-diff-block` を付ける（`viewer-src/jump-providers.ts` はこの属性で変更箇所を数える）。

差分の入口を開けるため、`BefoldKit/FileType.swift` の `supportsDiffDisplay` から `.csv` の除外を外し、`viewer-src/renderers.ts` の `_renderDiffHtmlIfAvailable` にある `type === 'csv'` による早期 return も見直す。`render.ts` の `renderShape` で `csv-table` の分岐が差分を通るようにする必要がある。CSV で `diff` モードが何を意味するかは親タスク TASK-483 の「差分モードの意味」の結論に従う。

起票後に CSV テーブルへ入った機能（列幅の自動測定・切り取りと検索ヒットの表示・数値書式・列幅変更・スクロールバー。TASK-906 ほか）と、挿入した削除行がどう噛み合うかを決める。

- 削除行を列幅の自動測定に含めるか
- 削除行を検索の対象にするか
- ヘッダ行が変わったときの見せ方
- 左右分割レイアウト（`ViewerDiffBridge.Layout.sideBySide`）でテーブル差分をどう扱うか

セル単位の色分け（追加行と削除行をペアリングして値の違う `<td>` だけ光らせる）は、`pairDiffLines`（`viewer-src/diff-parse.ts`）と単語差分の `diff-words.ts` が再利用できるが、まずレコード単位で成立させることを優先し、セル単位は必要と判断した場合のみ同タスク内で追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CSV/TSV でテーブル表示のまま差分表示モードを選べる
- [ ] #2 追加されたレコードが追加色、削除されたレコードが削除色で表示される
- [ ] #3 引用符内に改行を含む CSV でも、色が正しいレコードに当たる
- [ ] #4 差分が取得できない場合（未追跡・バイナリ・変更なし・サイズ超過）は通常のテーブル表示に落ちる
- [ ] #5 差分表示中のチャンク追記が表を壊さない
- [ ] #6 変更のあった行に data-diff-block が付き、差分ジャンプ（次の変更へ）がテーブル表示でも効く
- [ ] #7 削除行の列幅測定・検索対象・ヘッダ行の変更・左右分割レイアウトでの扱いが決まり、その通りに動く
<!-- AC:END -->
