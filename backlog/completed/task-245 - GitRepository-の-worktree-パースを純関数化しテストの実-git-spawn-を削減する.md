---
id: TASK-245
title: GitRepository の worktree パースを純関数化しテストの実 git spawn を削減する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 10:45'
updated_date: '2026-08-01 15:00'
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
- [x] #1 worktree porcelain パースが純関数として抽出されインメモリのパラメタライズテストで検証される
- [x] #2 実 git 経由の worktree テストはスモーク 1 本に縮み、ファイル全体の git spawn 回数が大幅に減る(目安 90 超→20 未満)
- [x] #3 実 git spawn テストが Integration 命名に分離される
- [x] #4 リポジトリ構築ヘルパーが BefoldTestSupport へ単一情報源化される
- [x] #5 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitRepository.swift: worktree porcelain パースを static func parseWorktreeList(_:) -> [GitWorktree] として抽出(既存 /// を分割して引き継ぐ)。worktrees(forRoot:) は git 実行 + パース呼び出しのみに縮小。
2. BefoldTestSupport に GitTestRepo.swift を追加(Foundation のみ依存)。GitRepositoryTests.git()/makeRepo() と GitCommandRunnerTests.rawGit()/makeRepoWithFsmonitor() の重複実装を、init/config/commitFile/run の共通ヘルパーへ一本化。
3. GitRepositoryTests.swift をパース純関数のインメモリ @Test(arguments:) 主体に作り替え、実 git 不要なテスト(resolvesRelativeGitdirFile, resolvesWorktreeGitFile)のみ残す。
4. 実 git を要する既存テストは GitRepositoryIntegrationTests.swift へ分離。worktree 系 6 テスト(main only/追加/ブランチ短縮/detached/worktree側列挙/git不可フォールバック)は、パースの網羅は 3. のパラメタライズへ委ねた上で「実 git の出力を実際にパースできる」スモーク 1 本 + git 不可フォールバック 1 本に統合し spawn 回数を大幅削減する。
5. GitCommandRunnerTests.swift: rawGit/makeRepoWithFsmonitor を GitTestRepo 経由に置き換え、実リポジトリに依存する doesNotExecuteRepositoryFsmonitorCommand のみ GitCommandRunnerIntegrationTests.swift へ移す。タイムアウト/資源残留系テストは GitCommandRunner 自身のプロセス管理挙動が検証対象そのもの(DefaultFileReader 同様の例外)であり、かつ直前の TASK-244 でスイート分割済みのため対象外とする(判断根拠を報告に明記)。
6. TASK-226(GitCommandRunner の async 化)には手を出さない。
7. swiftformat / swift build(警告なし) / swift test 実行、git spawn 回数の before/after を計測して記録。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
GitRepository.worktrees(forRoot:) の porcelain パースを static parseWorktreeList(_:) として抽出し、GitRepositoryTests を純関数のインメモリ @Test(arguments:) 主体(5 ケース)へ作り替え。実 git 依存テストは GitRepositoryIntegrationTests.swift へ分離(worktree 系 6 テスト→スモーク1本+フォールバック1本に統合)。リポジトリ構築ヘルパーは BefoldTestSupport/GitTestRepo.swift へ一本化し、GitRepositoryIntegrationTests・GitCommandRunnerTests の両方から使用(rawGit/makeRepoWithFsmonitor の重複実装を解消)。spawn 回数目安: GitRepositoryTests.swift(unit)は 0、worktree 系の実 git テストは 14 spawn(旧 42 相当→大幅減)。GitCommandRunnerTests.swift の doesNotExecuteRepositoryFsmonitorCommand は GitCommandRunnerResourceLeakTests(TASK-244 で直列化済み)に残し Integration 分離は見送り:資源残留系テストの基準線サンプリング直列化という別の設計制約と結合しており、ファイル分割すると TASK-244 の意図(GitCommandRunner を実行する全テストを直列スイートへ寄せる)と衝突するため。作業中に他エージェントが同ファイルを並行編集していたため一時待機し、コミット確認後に再開した。swift build 警告なし、swift test 936件グリーン、swiftformat/swiftlint 新規違反なし。

見送り事項の明記: GitCommandRunnerTests.swift の rawGit/makeRepoWithFsmonitor を GitTestRepo へ寄せる作業、および doesNotExecuteRepositoryFsmonitorCommand の Integration 分離は、TASK-244 の並行作業(GitCommandRunner を実行する全テストを直列スイートへ寄せる改修)と競合するため今回は見送った。GitCommandRunnerTests 側の作業完了後、team-lead から追加ラウンドとして依頼される想定。AC#4(リポジトリ構築ヘルパーの BefoldTestSupport 単一情報源化)はその追加ラウンドまで未達扱いとし、今回はチェックしない。

team-lead 確認結果: ヘルパー共通化(AC#4)は既に 42a2053 で実施済み(GitCommandRunnerTests の rawGit/makeRepoWithFsmonitor を BefoldTestSupport/GitTestRepo へ寄せ、GitRepositoryIntegrationTests と共通化)。AC#3 のうち GitCommandRunnerTests.swift の Integration 命名分離は見送り: 直前の TASK-244 が『GitCommandRunner を実行する全テストを直列スイートへ寄せる』基準で整理した直後であり、unit/integration 軸での再分割がその基準と衝突しうるため。GitRepository 側(GitRepositoryTests.swift → GitRepositoryIntegrationTests.swift)の分離は実施済み。AC のチェックは team-lead 側で行うため、このタスクではチェックしない。

AC#3(GitCommandRunnerTests の Integration 命名分離)は設計上やらない(won-t do)として確定クローズする。フォローアップ課題としても残さない。
理由: .serialized はスイート内しか直列化しないため、doesNotExecuteRepositoryFsmonitorCommand を Integration ファイルへ移すと必然的に別スイートとなり GitCommandRunnerResourceLeakTests と並列実行される。このテストは GitCommandRunner を実行して pipe と read スレッドを生成するため、TASK-244 で修正した「資源残留テストの基準線が並列側のノイズで水増しされ、リーク退行を静かに見逃す」問題をそのまま再導入する。命名規約より GitCommandRunnerResourceLeakTests の型コメントが定める制約(GitCommandRunner を実行するテストは全てそこへ置く)が優先される。GitRepository 側の Integration 分離は実施済み。
AC#2 の実数(レビュー指摘により訂正): 実 git テスト 11 本は削除ではなく新ファイルへ移動しただけで、GitRepositoryIntegrationTests は makeRepo(6 spawn)を 9 テストで呼ぶため依然 70〜80 spawn 規模。実際に減ったのは統合で消えた worktree 系 4 テスト分(約 28 spawn)で、2 ファイル合計では 90 超→60 台が正確。
実測: このファイル群は元々クリティカルパスから遠い(unit 0.107s / integration 0.216s、全体の律速は GitCommandRunnerResourceLeakTests の約 13s)。並列実行のため spawn 数はウォールクロックにほぼ現れない。本タスクの価値は実行時間短縮ではなく、パースを実 git 抜きで網羅検証できる構造とヘルパーの単一情報源化にある。
修正ラウンド1(edee648、実装エージェントのセッション上限によりメインが引き継ぎ): GitTestRepo.run の起動失敗時クラッシュ経路を塞ぐ / displayName のブランチ無し経路をインメモリ 5 ケースで検証 / スモークに --detach worktree を追加し detached の出力形を実 git に結びつけ / bare・空パス等のケース追加 / doc の是正。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitRepository.worktrees の porcelain パースを static parseWorktreeList へ純関数抽出し、branch あり/detached/bare/空パス/並び順を 8 ケースのインメモリ @Test(arguments:) で検証できるようにした。実 git 依存テストは GitRepositoryIntegrationTests へ分離し、worktree 系は実出力との結合を担保するスモーク 1 本(ブランチ有り + detached)へ統合。リポジトリ構築ヘルパーを BefoldTestSupport/GitTestRepo へ単一情報源化した。
git spawn は 2 ファイル合計で 90 超→60 台(worktree 系の統合で約 28 減)。ただし実測ではこのファイル群は元々クリティカルパスから遠く(unit 0.107s / integration 0.216s)、実行時間短縮の効果はほぼ無い。価値は構造改善(実 git 抜きで網羅検証できるパース、ヘルパーの単一情報源化)にある。
AC#3 は GitCommandRunnerTests について won-t do として確定クローズ(TASK-244 の直列化制約と衝突し、リーク検証の偽陰性を再導入するため)。
検証: swift test 1006 tests / 138 suites グリーン、swiftformat 差分なし、swift build 警告なし。レビュー指摘 Important 3 件 + Minor 5 件を反映済み。
<!-- SECTION:FINAL_SUMMARY:END -->
