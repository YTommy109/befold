---
id: TASK-662.6
title: git を使う統合テストの fixture 生成を軽くする
status: To Do
assignee: []
created_date: '2026-09-29 04:30'
updated_date: '2026-09-29 04:31'
labels: []
dependencies:
  - TASK-663
parent_task_id: TASK-662
priority: medium
ordinal: 862000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`GitTestRepo` の呼び出しは befoldTests で 166 箇所、`initRepository` 43 回。`GitStatusReaderIntegrationTests` は直列で 2.6 秒、`SidebarChangedFilesOnlyIntegrationTests` は 1.6 秒。`GitTestRepo.run` は `waitUntilExit()` で同期にスレッドを塞ぎ、@MainActor テストから呼ばれるとメインスレッドを塞ぐ。

## 該当
- `BefoldTestSupport/GitTestRepo.swift` の `initRepository` が `init` + `config user.email` + `config user.name` で git を 3 回起動する。既定値以外を渡す呼び出し元は 0 件。`run` で環境変数（`GIT_AUTHOR_*` / `GIT_COMMITTER_*`）を渡せば 1 回で済み、86 起動減る（手元実測で git 1 起動 9〜25ms）。あわせて `GIT_CONFIG_GLOBAL=/dev/null` / `GIT_CONFIG_NOSYSTEM=1` で利用者のグローバル設定（`commit.gpgsign` 等）から切り離せる
- `GitDiffReaderIntegrationTests`: 18 件中 17 件が個別に fixture を作る。読むだけの 7 件（`returnsUnifiedDiffForUnstagedChange` ほか `:18-143`）は 1 つの共有 fixture + `@Test(arguments:)` にまとめられる。index の mtime を触る `diffDoesNotDisturbIndexFingerprint` は分けたまま
- `GitDiffReaderIntegrationTests.reportsTooLargeDiff`: `maxDiffBytes = 1 << 20` を超えさせるために約 2MB・131k 行を書いて libgit2 に diff させている。上限を注入できれば KB 単位で済む
- `GitStatusBranchDiffIntegrationTests`: 1〜3 番目のテストは 1 リポジトリに同居できる
- `GitRepositoryRemoteLinkTests`: 8 件すべてが init・commit・remote add。URL 組み立て規則は純粋テスト `RemoteForgeTests` が押さえており、実 git は 1〜2 件で足りる
- `SidebarChangedFilesOnlyIntegrationTests`: @MainActor 上で git を約 30 起動する。ファイルを全部書いてから add・commit を 1 回にする／リポジトリ構築を nonisolated のヘルパーへ出す
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 initRepository の git 起動が 1 回になり、テストがユーザーのグローバル git 設定に依存しない
- [ ] #2 共有 fixture にまとめたテストが互いに干渉しない（並列実行で 3 回連続緑）
- [ ] #3 @MainActor テストの中で git プロセスを同期起動する箇所が減っている（前後の件数を Notes に）
- [ ] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->
