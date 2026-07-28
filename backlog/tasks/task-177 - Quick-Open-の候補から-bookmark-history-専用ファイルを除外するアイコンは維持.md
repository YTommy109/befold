---
id: TASK-177
title: Quick Open の候補から bookmark/history 専用ファイルを除外する(アイコンは維持)
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 00:52'
updated_date: '2026-07-28 02:15'
labels:
  - ui
  - quick-open
dependencies: []
priority: medium
type: enhancement
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Quick Open のファイル一覧に bookmark と history(recent)のファイルが混ざり、ノイズに感じられる。候補集合の対象は index(git 追跡ファイル索引)/ディレクトリ走査のファイルのみとし、index/tree に存在しない bookmark・history 専用のエントリは一覧から除外する。

ただしアイコンは残す: index に載っているファイルが同時に bookmark/recent でもある場合は、時計(recent)・ブックマーク(bookmark)のアイコン表示を維持する(origin の付与は残し、候補ソースとしての注入だけをやめる)。

実装上の起点:
- BefoldKit/QuickOpenCandidates.collect(): 現在 recent → bookmark → indexed の順で候補を集約し先勝ちで origin を決めている。indexed のみを候補にしつつ、recentURLs/bookmarkedURLs に含まれる indexed ファイルへ origin(.recent/.bookmark)を付与する形へ変更する。
- QuickOpenCandidateSet.initialCandidates(): 現在 origin != .indexed(= recent+bookmark)を空入力時に出しているため、除外方針に合わせて空入力時の表示内容を再設計する(空入力時に何を出すかは要検討: 索引先頭 N 件か、何も出さないか)。

空入力時の表示方針はユーザー確認が必要な設計判断を含むため、着手時に方針を確定する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 index/tree に存在しない bookmark・history 専用のファイルが Quick Open の候補に出ない
- [x] #2 index に載っているファイルが bookmark/recent でもある場合、対応するアイコン(bookmark/clock)が維持される
- [x] #3 空入力時の表示内容が再設計され、bookmark/history の羅列でなくなる
- [x] #4 QuickOpenCandidates / QuickOpenCandidateSet のテストが新方針(除外とアイコン維持)を検証する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
空入力時の表示方針をユーザー確認 → 「index に実在する recent のみ(時計アイコン・recency 順)」に決定。
実装(BefoldKit/QuickOpenCandidates.swift): collect() を『索引/走査由来のみを候補ソースにし、索引に載っているファイルへ recent>bookmark>indexed の優先で origin を付与』へ変更。recent/bookmark 専用(索引外)エントリは候補にしない。候補配列は『索引内 recent(recency 順) → 残り索引(bookmark 印つき)』の順。initialCandidates(limit:) は origin==.recent のみを返すよう変更。
検証: swift test 全 814 テスト緑。
- tagsIndexedFilesAndDropsStandaloneRecentBookmark: 索引外 gone.md/faves.md が候補に出ず、索引内 recent.md=.recent・marked.md=.bookmark・tracked.md=.indexed(AC#1/#2)。
- recentTakesPriorityOverBookmarkForIcon: recent かつ bookmark は .recent 優先(AC#2)。
- initialCandidatesOrdering / emptyQueryShowsRecentsOnly: 空入力は索引内 recent のみ(bookmark・indexed・索引外 recent は出ない)(AC#3/#4)。
アイコン描画(QuickOpenView.iconName)は origin 依存で不変のため、origin 付与維持でアイコンは保たれる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open の候補ソースを index/tree 由来のファイルのみに限定し、index に載っているファイルへ recent/bookmark の origin を付与する方式へ変更。index 外の bookmark/history 専用エントリは候補から除外しつつ、origin 由来のアイコン(時計/ブックマーク)は維持。空入力時の表示は『index に実在する recent のみ(recency 順)』へ再設計(ユーザー確認済み)。QuickOpenCandidates/CandidateSet/Model のテストを新方針へ更新・追加。swift test 814 件緑。
<!-- SECTION:FINAL_SUMMARY:END -->
