---
id: TASK-287
title: 絞り込みで一覧が空になったときの表示を実態に合わせる
status: Done
assignee: []
created_date: '2026-08-04 07:28'
updated_date: '2026-08-04 08:25'
labels: []
dependencies:
  - TASK-285
priority: medium
type: bug
ordinal: 477000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。サイドバーの空状態は sidebar.empty（「対応ファイルがありません」/ No Supported Files）を再利用しているが、git 絞り込みで空になった場合は事実と異なる。コミット済みの .md だけが入ったフォルダーで絞り込み ON にすると、開ける文書で満たされているのに『対応ファイルがありません』と出るため、フィルターではなく読み込み失敗だと解釈される。

TASK-285（綺麗なリポジトリでの縮退）の結論次第で必要な文言が変わるため、先に TASK-285 の方針を決めてから着手する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git 絞り込みで空になった場合と、対応ファイルが本当に無い場合とで表示が区別される
- [x] #2 文言から『絞り込みを解除すれば見える』ことが伝わる
- [x] #3 en/ja 両方の文字列が Localizable.xcstrings に追加される（既存の並び順を壊さない）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-285 の受け入れ条件 #2（綺麗なリポジトリで意図が伝わる表示）を満たすには文言の分岐が必須だったため、285 と同時に実施した。実装: FileListView の空状態を emptyStateView へ切り出し、model.activeGitChangeFilter != nil のときは sidebar.empty.changedFilesOnly（「変更されたファイルはありません」＋『解除するとすべて表示されます』）を出す。アイコンもヘッダーのトグルと同じ arrow.triangle.branch に合わせた。en/ja とも追加済み（既存の並び順は変更していない）。検証: swift test 1067 passed、markdownlint 0 件、xcodebuild 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの空状態を、git 絞り込みで空になった場合と対応ファイルが無い場合とで出し分けた（TASK-285 と同時に実施）。文言は解除すれば見えることが伝わる内容にし、en/ja を追加した。
<!-- SECTION:FINAL_SUMMARY:END -->
