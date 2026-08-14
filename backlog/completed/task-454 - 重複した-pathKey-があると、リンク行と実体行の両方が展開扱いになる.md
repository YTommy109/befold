---
id: TASK-454
title: 重複した pathKey があると、リンク行と実体行の両方が展開扱いになる
status: Done
assignee: []
created_date: '2026-08-11 21:45'
updated_date: '2026-08-13 04:44'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 679000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
pathKey は resolvingSymlinksInPath() で解決した実体パスのため、同一フォルダー内にシンボリックリンクと実体が並ぶと 2 行が同じキーを持つ（TASK-450 の調査で確定）。

行の組み立て SidebarRowBuilder.Flattening.append（BefoldApp/befold/Viewer/SidebarRowBuilder.swift:106-113）は expanded.contains(entry.pathKey) で開閉を決めるため、片方を展開すると**もう一方の行も展開済みの見た目になる**。子行が実際に並ぶのは visited.insert が通る最初の 1 行だけなので、後の行は「三角は開いているのに子が出ない」状態になる。

同様に SidebarExpansion の children / expandedKeys もキー単位のため、リンク行と実体行を別々に開閉できない。

TASK-450 / TASK-451 の範囲外として切り出したもの（あちらは引き当て述語と再列挙の話で、開閉状態の粒度には触れていない）。優先度が low なのは、同一フォルダー内にリンクと実体が並ぶ構成自体が稀で、症状も見た目の不整合にとどまるため。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同一キーの行が複数あるとき、展開したのはどの行かを区別できる（または区別しない方針を doc とテストで固定する）
- [x] #2 三角が開いているのに子が出ない行が生じないことをユニットテストで担保している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 開閉状態の粒度は pathKey のまま（区別しない）と決め、doc とテストで固定する
2. SidebarRowBuilder.Flattening で「同一 pathKey の最初のフォルダー行だけが開閉状態を持つ」ようにする。後続の重複行は disclosure を nil にして三角自体を出さない
3. 重複キーで「三角が開いているのに子が出ない行」が生じないことをユニットテストで担保する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定: 開閉状態の粒度は pathKey のまま（行ごとには分けない）

行ごとの開閉状態へ粒度を上げると、同じフォルダーの子リストを行の数だけ持つことになり、
`SidebarExpansion.beginExpanding` が保証している「展開 1 回につき列挙 1 回」という
コストの上限も崩れる。同一フォルダー内にリンクと実体が並ぶ構成自体が稀（起票時の
priority low の理由）なのに、状態と経路を 2 系統に増やすのは割に合わない。

代わりに **「先に現れた 1 行だけが開閉状態の持ち主」** という規則を入れ、
後続の重複行は開閉三角そのものを出さない（`disclosure` が nil）。

- 子行が並ぶのは持ち主の行の下だけなので「三角は開いているのに子が出ない行」が消える
- 三角が無い＝この行では開閉できない、がそのまま見た目になる。畳んだ三角
  (`.collapsed`) にすると押しても何も起きない三角を見せることになる
  （`beginExpanding` が展開済みとして弾く）ため、そちらは採らなかった
- どの行が展開の持ち主かも見た目で区別できるので AC #1 を満たす

## 変更

`SidebarRowBuilder.Flattening.append` で、開閉三角を決める **前に** `visited.insert` で
持ち主かどうかを確定させる（従来は `expanded` に一致した行だけを visited へ入れており、
判定が三角の決定より後だった）。フォルダー行なら展開されていなくても visited へ入れる
ため、`loading` / `failed` の重複行も同じ規則に従う。規則は型の doc の
「## 同じ pathKey を持つ行が複数あるとき」に明記した。

## 検証

- 新規テスト 2 件（`SidebarRowBuilderTests`）。実シンボリックリンクを張って
  `linkEntry.pathKey == realEntry.pathKey` を前提として明示したうえで、
  展開時・読み込み中の両方を固定。
- **修正を戻して落ちることを確認済み**: 旧挙動では
  `(rows[2].disclosure → .expanded) == nil` と
  `openRowsWithoutChildren(...).isEmpty → false` が失敗する（症状そのもの）。
- `swift test` 全件: 1470 tests / 232 suites passed。
- swiftlint: 変更 2 ファイルで警告ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
開閉状態の粒度は pathKey のままとし（行ごとに分けると子リストを行数ぶん持つことになり「展開 1 回につき列挙 1 回」の上限が崩れるため）、「同じ pathKey の行は先に現れた 1 行だけが開閉状態の持ち主」という規則を SidebarRowBuilder.Flattening へ入れた。持ち主でない重複行は開閉三角を出さないため、「三角は開いているのに子が出ない行」が生じない。規則は型の doc に明記し、実シンボリックリンクを使ったテスト 2 件で固定。修正を戻すと落ちることを確認済み。swift test 1470 件パス、swiftlint 警告ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
