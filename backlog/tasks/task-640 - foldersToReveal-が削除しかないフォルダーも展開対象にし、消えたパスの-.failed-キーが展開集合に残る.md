---
id: TASK-640
title: foldersToReveal が削除しかないフォルダーも展開対象にし、消えたパスの .failed キーが展開集合に残る
status: To Do
assignee: []
created_date: '2026-09-27 06:23'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarGitStatus.swift
  - BefoldApp/befold/App/GitFolderStatus.swift
  - BefoldApp/befold/App/SidebarExpansion.swift
  - docs/dev/viewer-ui.md
priority: medium
type: bug
ordinal: 840000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637（commit c1de117a）のレビュー指摘。コードで確認済み。

## 現象

`SidebarGitStatus.foldersToReveal` の候補はプレフィックス・`indeterminateRoots`・`files[key]`（未追跡ディレクトリ）でしか絞っておらず、変更種別を見ない。`GitFolderStatus.aggregate` は clean でない全エントリ（`.deleted` 含む）を祖先へ畳み込むので、**削除しかないフォルダーも展開対象になる**。

例: `git rm -r docs/old/` → `/repo/docs/old/a.md` が deleted → `folders` に `/repo/docs/old` → reveal → `expandFolder` → `beginExpanding` が `expandedKeys` / `urls` に追加 → `childrenLister` が nil → `Children.failed`。行が無いので描画はされないが、`collapse` 以外にキーを消す経路が無く、`expandedFolderURLs` に残り続ける。`SidebarInheritance.expansion` → `adoptExpansion` に存在チェックが無いので、新しい窓を開くたびに存在しないパスを 1 回列挙する（フォーカス復帰時の `reloadExpandedChildren` は TASK-451 のガードで行の無いキーを飛ばすため、繰り返しはそこまで）。

フォルダー自体は残っていて中身の削除だけがある場合も、開いたフォルダーの中が変更のみ表示で空になる（削除ファイルは行を持たない）。

## 仕様との関係

`docs/dev/viewer-ui.md` のサイドバー節「範囲」に「削除ファイルは行を持たないので対象外」とある。削除が何も引き起こさないと読める書き方だが、コードは削除を契機に祖先を開く。コードと文書のどちらかに揃える。

## 修正の方向（決めるのは着手時）

候補を作るときに「削除以外の変更を配下に持つフォルダー」に絞るのが素直（`GitFolderStatus` の集約に削除以外の有無を持たせるか、`foldersToReveal` で除外する）。全候補に `isDirectory` を掛ける案は stat が候補数ぶん増えるので、消えたパスへの防御としてだけ使う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 削除のみを配下に持つフォルダーは展開対象にならない（`SidebarGitStatusRevealTests` に deleted ケースを足して検証）
- [ ] #2 削除でディスクから消えたフォルダーのキーが `expandedKeys` / `expandedFolderURLs` に残らない（`SidebarNavigatorReviewExpansionTests` で、childrenLister が nil を返すパスを含む git 状態を与えて検証）
- [ ] #3 `docs/dev/viewer-ui.md` の「削除ファイルは行を持たないので対象外」の記述が、実装後の振る舞い（削除は展開の契機にならない）と一致している
<!-- AC:END -->
