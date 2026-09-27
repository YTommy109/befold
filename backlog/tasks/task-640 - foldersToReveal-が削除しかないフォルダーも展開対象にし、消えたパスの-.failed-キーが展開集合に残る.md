---
id: TASK-640
title: foldersToReveal が削除しかないフォルダーも展開対象にし、消えたパスの .failed キーが展開集合に残る
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 06:23'
updated_date: '2026-09-27 06:35'
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
- [x] #1 削除のみを配下に持つフォルダーは展開対象にならない（`SidebarGitStatusRevealTests` に deleted ケースを足して検証）
- [x] #2 削除でディスクから消えたフォルダーのキーが `expandedKeys` / `expandedFolderURLs` に残らない（`SidebarNavigatorReviewExpansionTests` で、childrenLister が nil を返すパスを含む git 状態を与えて検証）
- [x] #3 `docs/dev/viewer-ui.md` の「削除ファイルは行を持たないので対象外」の記述が、実装後の振る舞い（削除は展開の契機にならない）と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitFileStatus に isDeleted（作業ツリーに実体が無い = 最新の辺 worktree > index > branch が .deleted で、未追跡でない）を足す。GitStatusReader は index D + 作業ツリー新規を isUntracked で返すので、その順序で正しい。
2. SidebarGitStatus.foldersToReveal を folders のキー起点から files 起点へ書き換える: 表示中ディレクトリ配下の clean でも deleted でもないエントリについて、祖先（表示中ディレクトリは含まない）を足し、未追跡かつ実ディレクトリなら自身も足す。indeterminate の除外は従来どおり。新しい状態は増やさない（GitFolderStatus に旗を足す案は不採用）。
3. テスト: SidebarGitStatusRevealTests に削除のみのフォルダー（index D / worktree D / branch D）と、削除と変更が混在するフォルダーのケース。SidebarNavigatorReviewExpansionTests に、childrenLister が nil を返す消えたパス配下の削除だけを与えて展開集合に入らないケース。
4. docs/dev/viewer-ui.md の「削除ファイルは行を持たないので対象外」を「削除は展開の契機にならない」へ直す。
review-design: 項目 1（判定は git の種別という事実で、ディスクの形ではない）、3（呼び出し元は revealChangedFolders の 2 箇所のみ。バッジ側 folderStatus は削除フォルダーにも出るが行の有無とは別の関心で触らない）、6（走査は files × 深さで従来の folders 走査と同程度。stat は未追跡エントリのみで変わらず）、10（SidebarGitStatus 168 行 → ほぼ同数、GitFileStatus 63 → 約 70 行）。他は該当なし。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装
- 候補の起点を `folders` のキーから `files` へ変えた。表示中ディレクトリ配下の clean でも削除でもないエントリについて祖先（表示中ディレクトリは含まない）を足し、未追跡かつ実ディレクトリなら自身も足す。`GitFolderStatus` に旗を足す案（新しい状態）は不採用。走査量は files × 深さで従来の folders 走査と同程度、stat は未追跡エントリのみで変わらない。
- 「作業ツリーに実体が無い」は `GitFileStatus.isDeleted` として置いた。3 辺のうち最も新しい辺（worktree > index > branch）が `.deleted` で、かつ未追跡でないこと。`git rm --cached` の形は `GitStatusReader.fileStatus` が index_to_workdir の UNTRACKED を見て未追跡として返すため、`isUntracked` で先に除く順序が正しい（コード参照で確認）。
- review-design は Plan に記載のとおり指摘なし。責務レビューは、追加したのが computed な述語 1 つで型・stored property・プロトコル準拠・注入クロージャのいずれも増えていないため回していない。

## 検証
- 新テスト 2 件（`SidebarGitStatusRevealTests.excludesDeletionOnlyFolders`、`SidebarNavigatorReviewExpansionTests.deletionOnlyFolderIsNotRevealed`）は、`!file.isDeleted` の条件を外すとどちらも落ちる（Expectation failed: result == ["/repo/kept", "/repo/recreated"] / expandedFolderKeys == [key("a")] / expandedFolderURLs[key("gone")] == nil）。
- `swift test --skip Integration --skip FileWatcherTests`: 1885 + 66 件 pass。`xcodebuild build` 成功。swiftlint は origin/main と差分ゼロ（46 → 46、真の新規 0・解消 0）。swiftformat lint 0 件。`check-type-group-size.sh --check` 通過。markdownlint 0 件。
- native-app-design.md への反映は不要（型の追加・依存の向きの変更なし）。表示仕様は viewer-ui.md の「範囲」を更新した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
レビュー表示の展開候補を、削除（作業ツリーに実体が無い）を除いた変更ファイルから祖先を求める形へ変え、削除しか無いフォルダーを開かないようにした。`GitFileStatus.isDeleted` を足し、`SidebarGitStatus.foldersToReveal` を files 起点に書き換えた（新しい状態は増やしていない）。新テスト 2 件は修正を戻すと落ちることを実測。全件テスト 1885 + 66 pass、xcodebuild 成功、swiftlint 差分ゼロ。viewer-ui.md の記述を実装に合わせた。
<!-- SECTION:FINAL_SUMMARY:END -->
