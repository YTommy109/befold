---
id: TASK-286
title: 絞り込み ON でも表示中の文書をサイドバーに残す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 07:28'
updated_date: '2026-08-04 08:25'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 489000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。SidebarNavigator.ensureCurrentFile(in:) は『開いている文書がサイドバーから消える回帰』を防ぐために entries へ必ず含める不変条件だが、TASK-264 の絞り込みは visibleEntries 側で効くためこの不変条件を迂回する。

再現: 他に変更ファイルがあるリポジトリで、コミット済み・未変更の文書（例 README.md）を開いた状態で ⌘⌃G を押すと、その行が一覧から消え選択ハイライトも失われる。コンテンツ側は表示し続けるため、矢印キーの移動が一覧に無いエントリ基準になる。

検討事項: filterText 側は『ユーザーが自分で打った絞り込み』なので消えても納得できるが、git 絞り込みは状態由来で消えるため同じ扱いでよいかは判断が要る。visibleEntries に例外を足すのか、ensureCurrentFile 相当を絞り込み後にも通すのかで置き場所が変わる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 絞り込み ON で未変更の文書を開いていても、その行がサイドバーに残る
- [x] #2 残した行の選択ハイライトと矢印キー移動が一覧と整合する
- [x] #3 filterText による絞り込みとの扱いの違い（残す/残さない）が決められ、理由が記録される
- [x] #4 回帰テストがあり、修正を戻すと落ちることを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 判断: git 絞り込みは『ユーザーが打った条件』ではなく状態由来で消えるため、表示中の対象は必ず残す。filterText は自分で打った条件なので従来どおり消えてよい（この違いをコメントに残す）。
2. 実装は FileListModel.visibleEntries の中で、選択中の行（storedSelectionPathKey と一致する行）を git 絞り込みの例外にする。ensureCurrentFile 相当を SidebarNavigator 側へ足すと entries に無いものを作る話になり、visibleEntries は entries の部分集合という性質が崩れるため採らない。
3. 選択がフォルダーの場合も同様に残す（提示中の対象という点で同じ）。
4. テスト: 絞り込み ON で未変更の選択行が残ること、選択が無いときは残らないことを単体テストで固定する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: FileListModel.visibleEntries で、選択中（= 提示中）の行を git 絞り込みの例外にした。ensureCurrentFile 相当を SidebarNavigator へ足す案は、entries に無い行を作る話になり『visibleEntries は entries の部分集合』という性質が崩れるため採らなかった。

filterText との違い（受け入れ条件 #3）: filterText はユーザーが自分で打った条件なので選択中でも消える。git 絞り込みは状態由来で消えるため残す。この違いはコメントに書き、両方向をテストで固定した（filterTextDropsPresentedEntry / changedFilesOnlyKeepsPresentedEntry）。

検証: swift test 1067 passed。例外を外す変異で changedFilesOnlyKeepsPresentedEntry が落ちることを確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git 絞り込みでは選択中（提示中）の行を必ず残すようにし、開いている未変更の文書がサイドバーから消える問題を解消した。filterText との扱いの違い（打った条件は消えてよい／状態由来は残す）を理由付きでコメントとテストに固定し、変異確認込みで検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
