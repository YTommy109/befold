---
id: TASK-662.6
title: git を使う統合テストの fixture 生成を軽くする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 04:30'
updated_date: '2026-09-29 07:53'
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
- [x] #1 initRepository の git 起動が 1 回になり、テストがユーザーのグローバル git 設定に依存しない
- [x] #2 共有 fixture にまとめたテストが互いに干渉しない（並列実行で 3 回連続緑）
- [x] #3 @MainActor テストの中で git プロセスを同期起動する箇所が減っている（前後の件数を Notes に）
- [x] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitTestRepo.run に環境変数（GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1, GIT_AUTHOR_*/GIT_COMMITTER_*）を渡し、initRepository を init 1 回にする。realGitDiff も同じ環境で起動する
2. GitDiffReaderIntegrationTests の読むだけ 7 件を共有 fixture + @Test(arguments:) にまとめる。reportsTooLargeDiff は GitDiffReader に byteLimit を注入して KB 単位にする
3. GitStatusBranchDiffIntegrationTests の 1〜3 件目を 1 リポジトリへ同居させる
4. GitRepositoryRemoteLinkTests を実 git 2 リポジトリへ縮める（形式の網羅は RemoteForgeTests）
5. SidebarChangedFilesOnlyIntegrationTests / GitStatusReaderIntegrationTests の @MainActor テストの fixture 構築を GitTestRepo.offMainActor で外へ出し、commitAll でコミットを 1 回にする
6. 変更前後の所要時間を測って Notes に残す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容
- GitTestRepo.run が `GIT_CONFIG_GLOBAL=/dev/null` / `GIT_CONFIG_NOSYSTEM=1` / `GIT_AUTHOR_*` / `GIT_COMMITTER_*` を渡す（`GitTestRepo.environment`）。initRepository は init 1 回だけ（既定値以外の userEmail/userName を渡す呼び出し元は 0 件だったので引数ごと削除）。GitDiffReaderIntegrationTests の realGitDiff も同じ環境で起動する（`diff.noprefix` などで比較相手の出力が変わるのを防ぐ）
- GitDiffReaderIntegrationTests: 読むだけ 7 件を `classifiesFileInSharedRepository`（`@Test(arguments: ReadOnlyCase.allCases)`）にまとめた。fixture は static の共有リポジトリで、git は init・add -A・commit・add の 4 回。一時ディレクトリはテストプロセスの間生きたままになる（static は解放されない）。diffDoesNotDisturbIndexFingerprint は分けたまま
- reportsTooLargeDiff: `GitDiffReader(byteLimit:)` を足して上限を注入し、fixture を約 2MB から約 8.7KB にした
- GitStatusBranchDiffIntegrationTests: 1〜3 件目を `classifiesChangesAgainstBaseBranch` の 1 リポジトリへまとめた
- GitRepositoryRemoteLinkTests: 実 git のリポジトリを 8 から 2 にした（組み立て 1 本・縮退 1 本はリポジトリの状態を順に変えて確かめる）。GitLab 形式は RemoteForgeTests が網羅しているので実 git 経由の 1 本は外した
- @MainActor テストの fixture 構築を `GitTestRepo.offMainActor`（nonisolated async）で外へ出した。commitAll（add -A + commit）でファイルごとのコミットもやめた

## AC#3 @MainActor 上で同期に起動する git の回数
- 変更前 34 回: SidebarChangedFilesOnlyIntegrationTests 23 回（11+5+7）、GitStatusReaderIntegrationTests の @MainActor 2 件で 11 回（5+5+add 1）
- 変更後 0 回（全部 offMainActor の中）。Sidebar の git 起動の総数も 23 → 9 回

## AC#4 計測（手元、debug、2026-09-29）
- 対象 9 スイートの `--no-parallel --filter`: 変更前（HEAD 6a81daaa を .tmp へ git archive してビルド）59 件 5.62 秒 → 変更後 46 件 3.73 秒
- 全体の直列実行でのスイート時間（変更前 3 回 / 変更後 2 回）: SidebarChangedFilesOnly 1.58 → 0.17、GitDiffReader 0.76 → 0.27、GitRepositoryRemoteLink 0.53 → 0.15、GitStatusBranchDiff 0.46 → 0.19、GitStatusReader 2.55 → 1.74
- `swift test --no-parallel` 全体: 51.3 / 52.0 / 52.3 秒（2017 件）→ 47.8 / 47.5 秒（2005 件）
- `swift test`（並列）全体: 変更前 39.5 秒（1 回、後述の無関係な 2 issue で失敗）→ 変更後 38.5 / 38.5 / 41.0 秒。並列ではほぼ変わらない。律速は MainActor のキューで、git fixture はもともと並列に吸収されていた（TASK-662 の見立てどおり）
- 変更後の並列 2 回目だけ time の real が 81 秒になった（テスト wall は 38.5 秒、user 49 秒）。テスト実行の外で止まっていた分で、原因は追っていない

## AC#2
並列の全体実行 3 回連続緑（2005 件）。直列の全体実行も 2 回緑

## 途中で見つけたもの
- 共有 fixture 化の途中で signal 5 を踏み、TASK-663 の原因（FileWatcher.deinit の queue.sync）と特定して同じブランチで直した
- 変更前ツリーの並列実行で ViewerWindowControllerDiffPendingTests がゲート待ち 15 秒の上限で落ちた（TASK-662.5 で入れたゲート）。範囲外なので TASK-665 として起票した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git fixture を軽くした。GitTestRepo はグローバル設定を切った環境変数で起動し、init を 1 回にした。読むだけの diff テストは共有リポジトリ + arguments にまとめ、tooLarge は上限の注入で 2MB → 8.7KB にした。ブランチ差分とリモートリンクのテストはリポジトリを集約し、@MainActor 上の git 同期起動を 34 → 0 回にした。対象スイートは直列で 5.62 → 3.73 秒、全体の直列は約 52 → 47.6 秒。並列 wall はほぼ変わらない（38.5〜41.0 秒）。並列 3 回・直列 2 回の全体実行が緑。
<!-- SECTION:FINAL_SUMMARY:END -->
