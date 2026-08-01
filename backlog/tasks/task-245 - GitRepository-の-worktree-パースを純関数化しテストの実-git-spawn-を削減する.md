---
id: TASK-245
title: GitRepository の worktree パースを純関数化しテストの実 git spawn を削減する
status: To Do
assignee: []
created_date: '2026-08-01 10:45'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 447000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitRepositoryTests.swift:119-256 の worktree 系 6 テストが毎回リポジトリ構築(git 6 回)+ worktree add + クエリを払い、ファイル全体で git spawn 90 回超(1 回 30〜80ms、TSan 込みで数秒規模)。
改善の本命は GitRepository.swift:134-159 の worktree list porcelain パース部を static 純関数(parseWorktreeList)へ抽出し、branch あり / detached / 並び順のケースを @Test(arguments:) のインメモリフィクスチャで検証すること。実 git を通すのは「実出力がパースできる」スモーク 1 本へ縮める。
あわせて:
- 実 git を spawn するテストは規約の判定基準(実プロセスの実挙動が結果を左右)に照らし 〜IntegrationTests.swift 命名へ分離する(GitCommandRunnerTests も同様)
- git リポジトリ構築ヘルパーが GitRepositoryTests.swift:15-32 と GitCommandRunnerTests.swift:381-429 で別実装されており、BefoldTestSupport(Foundation+Testing のみ依存の方針に Process は適合)へ GitTestRepo として共通化する
関連: TASK-226 と着手時に整合を確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 worktree porcelain パースが純関数として抽出されインメモリのパラメタライズテストで検証される
- [ ] #2 実 git 経由の worktree テストはスモーク 1 本に縮み、ファイル全体の git spawn 回数が大幅に減る(目安 90 超→20 未満)
- [ ] #3 実 git spawn テストが Integration 命名に分離される
- [ ] #4 リポジトリ構築ヘルパーが BefoldTestSupport へ単一情報源化される
- [ ] #5 swift test が全てグリーン
<!-- AC:END -->
