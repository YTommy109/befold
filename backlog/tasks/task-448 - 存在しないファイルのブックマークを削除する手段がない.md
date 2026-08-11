---
id: TASK-448
title: 存在しないファイルのブックマークを削除する手段がない
status: To Do
assignee: []
created_date: '2026-08-11 13:13'
updated_date: '2026-08-11 13:14'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 676000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

ブックマークの削除は「該当ファイルを開いてトグルオフする」運用のみで、専用の削除 UI が無い（`BefoldApp/befold/App/BookmarksMenuController.swift:5` の doc コメントに明記）。そのため、ブックマーク先のファイルが消えると削除する手段が実質的に無くなり、Bookmarks メニューに開けない項目が残り続ける。worktree を多用していると（worktree の削除で配下のファイルごと消えるため）頻繁に発生する。

## 現状（コード参照）

- 永続化: `BefoldApp/BefoldKit/BookmarkStore.swift:8`（UserDefaults キー `BookmarkedPaths` にパス文字列の配列）。Recent と異なり上限プルーニングも存在チェックも無い（同ファイル:6 のコメント）
- メニュー構築: `BefoldApp/befold/App/BookmarksMenuController.swift:16` の `menuNeedsUpdate` が `bookmarkedURLs()` をそのまま項目化しており、存在チェックをしていない
- 削除 API: `BookmarkStore` には `toggle(_:)` はあるが、URL を指定して確実に取り除く経路はメニューからは辿れない
- CLI: `BefoldApp/BefoldCLI/CLIBookmarkCommand.swift` は add のみ（remove サブコマンドなし）

## 対応方針（実装時に決める）

いずれか、または組み合わせ。

1. メニュー表示時（`menuNeedsUpdate`）に存在チェックし、欠落項目を無効表示にする／隠す
2. 欠落したブックマークを開こうとしたときに、その場で削除を提案（またはストアから除去）する
3. Bookmarks メニューに個別削除（またはコンテキストメニュー）を用意する

存在チェックを毎回の表示で行うコスト（ネットワークボリューム上のパスでの遅延）と、一時的に unmount されたボリュームのブックマークを勝手に消さないことの両立に注意する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマーク先のファイルが存在しない場合、ユーザーがその項目をブックマークから取り除ける手段がある
- [ ] #2 ファイルが存在しないブックマークは Bookmarks メニュー上でそれと分かる（無効表示・非表示など、選んだ方針で一貫している）
- [ ] #3 一時的にアクセスできないだけのパス（unmount 中の外部ボリューム等）を、ユーザーの明示操作なしに削除しない
- [ ] #4 BookmarkStore の欠落判定・除去ロジックにユニットテストがある（存在する／しない／削除後に永続化から消えることの 3 ケース）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査で確認した補足（起票時点、コミット 85ad7d3）:

- 開こうとした時は無反応ではなく「File Not Found」アラートが出る（`BefoldApp/befold/App/ViewerWindowManager.swift:252` の `fileExists` ガード → `BefoldApp/befold/App/FileNotFoundUI.swift:15`）。ただし表示のみで BookmarkStore からは何も消さない。
- 解除手段は「開いてトグルオフ」だけで、開けないファイルはこの経路を通れない（`MainBuilder` 側のトグルは `ViewerWindowController+MenuActions.swift:97`）。CLI も add のみで remove が無い。
- 存在チェックの先例: `BefoldApp/befold/App/RecentRepositoriesStore.swift:112` `pruneMissingAsync()` — 起動時 1 回だけ `Task.detached(priority: .utility)` で stat し、差分があるときだけ保存する。同ファイル :105-111 に「stat はネットワークマウントで待たされうるため MainActor 外」「menuNeedsUpdate からは呼ばない」という方針コメントがある。ブックマークの欠落判定はこの形を踏襲するのが素直（＝対応方針 1 の「メニュー表示時に毎回チェック」は上記コメントと衝突するため、採用するなら理由を残す）。
- `BookmarkStore` には remove/clear API 自体が無い（`toggle` のみ）ため、削除経路を作るなら API 追加から。
<!-- SECTION:NOTES:END -->
