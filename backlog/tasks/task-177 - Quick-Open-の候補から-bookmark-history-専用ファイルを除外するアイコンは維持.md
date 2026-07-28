---
id: TASK-177
title: Quick Open の候補から bookmark/history 専用ファイルを除外する(アイコンは維持)
status: To Do
assignee: []
created_date: '2026-07-28 00:52'
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
- [ ] #1 index/tree に存在しない bookmark・history 専用のファイルが Quick Open の候補に出ない
- [ ] #2 index に載っているファイルが bookmark/recent でもある場合、対応するアイコン(bookmark/clock)が維持される
- [ ] #3 空入力時の表示内容が再設計され、bookmark/history の羅列でなくなる
- [ ] #4 QuickOpenCandidates / QuickOpenCandidateSet のテストが新方針(除外とアイコン維持)を検証する
<!-- AC:END -->
