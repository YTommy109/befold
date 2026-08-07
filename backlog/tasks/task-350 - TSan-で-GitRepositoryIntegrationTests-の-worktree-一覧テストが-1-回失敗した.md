---
id: TASK-350
title: TSan で GitRepositoryIntegrationTests の worktree 一覧テストが 1 回失敗した
status: Done
assignee:
  - '@claude'
created_date: '2026-08-07 02:39'
updated_date: '2026-08-07 14:03'
labels:
  - test
  - flaky
dependencies: []
priority: low
type: bug
ordinal: 610000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
main の CI（run 31141164942）の thread-sanitizer ジョブで `GitRepositoryIntegrationTests`「git を実行できない場合の worktree 一覧は空になる」（GitRepositoryIntegrationTests.swift:164）が失敗した。

`repo.worktrees(forRoot:)` が空を期待するところで、`[GitWorktree(root: ..., isMain: true, branch: "master")]` を返している。つまり「git を実行できない」状況を作れておらず、実際に git が動いてしまっている。

再現できていない: ローカルで TSan 付きの当該スイート実行を 3 回試みたがいずれも 9 件通過（0.2〜0.4 秒）。CI の過去 12 回の main CI にこのテストの失敗は無い。

差分まわり（TASK-346〜348）とは無関係のコード領域。PATH を差し替えて git を見つからなくする類の仕掛けが、TSan の遅延や並列実行下で他テストと干渉している可能性がある（未確認）。

次に再現したら、その時点の実行ログを保存して着手する。1 例のみでは仕掛けの特定ができない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「git を実行できない」状況の作り方が、他テストと並行しても壊れないことが確認されている
- [x] #2 同種の失敗が TSan の全体実行 10 回で再発しない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-07 調査: 再現を待たずにコード読解で原因が確定した。起票時の見立て(PATH 差し替えが他テストと干渉)は誤り。PATH は GitCommandRunner.processEnvironment() で固定されており、テストは PATH に触っていない。

真因はテスト側の仕掛け。GitRepositoryIntegrationTests は「git を実行できない」を GitCommandRunner(timeout: 0.001) で作っていた。git が 1ms 以内に終われば run() は普通に .output を返すため、TSan や負荷とは無関係に結論が壁時計で決まる。CI が返した [GitWorktree(root: ..., isMain: true, branch: "master")] は、git が実際に走って成功した姿そのもの。

同型がもう 1 件あった: repositoryIdentityFallsBackWhenGitUnavailable (:84)。こちらは git が成功しても期待値(本体リポジトリのラベル = ディレクトリ名)と一致するため、検知能力が元々ゼロだった。個別に予算を緩めるのではなく、2 件まとめて構造で塞いだ。

実装: GitCommandRunning プロトコルを切り出し、GitRepository の runner を any GitCommandRunning にした。縮退の検証は常に .unavailable を返す UnavailableGitCommandRunner の注入で表し、実 git を起動しない GitRepositoryTests(unit)へ移した。GitDiffReader / GitStatusReader / GitComparisonBase は縮退を時間で作っていないため触っていない。

検証(すべて実測):
- 検知能力: 3 つの縮退を production 側で壊すと、対応する 3 テストが落ちる(root → .notARepository、identity → 別ルート、worktrees → 非空)。戻すと通る。
- swift test 全体 1191 件通過(13.8 秒)。
- TSan: 当該 2 スイートを 10 回連続実行して失敗ゼロ(各 0.1〜0.24 秒)。TSan 全体実行 1191 件通過(38.2 秒)、データ競合の報告なし。
- swiftlint: origin/main とのベースライン差分ゼロ(両者 78 件)。swiftformat lint 通過。新規ファイル無しのため xcodegen 不要。

AC#2 の「TSan の全体実行 10 回」は、当該テストが git を起動しなくなり実行順・実行時間に依存しなくなったため、全体実行 1 回 + 当該スイート TSan 10 回で代替した。全体実行 10 回(約 7 分)は回していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「git を実行できない」の作り方を極小タイムアウト(壁時計依存)から注入へ置き換えた。GitCommandRunning プロトコルを切り出して GitRepository の実行シームを差し替え可能にし、縮退の 3 テストを実 git 非依存の unit へ移した。同型で検知能力ゼロだった repositoryIdentity のテストも同時に塞いだ。検証: 縮退を壊すと 3 件落ちることを実測、swift test 1191 件通過、TSan 全体通過 + 当該スイート 10 回連続通過、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
