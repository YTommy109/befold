---
id: TASK-116.4
title: BefoldCLICommandTests をコミットし、本番 UserDefaults 到達とパラメタライズ漏れを解消する
status: To Do
assignee: []
created_date: '2026-07-23 23:18'
labels:
  - test
  - cli
dependencies: []
parent_task_id: TASK-116
priority: medium
ordinal: 30400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befoldCLITests/BefoldCLICommandTests.swift`(25 テスト)は**現在 untracked のまま**で、ブランチにコミットされていない。CI で一度も実行されていないため、まずコミットして CI の対象に載せた上で、以下を解消する。

## 1. 本番の共有 UserDefaults に到達する

L89-101 `checkAndBookmarkRunInOrderAndAggregateFailure` は `run()` 経由で `BefoldCLICommand.bookmarkStore`(`BefoldApp/befold-cli/BefoldCLICommand.swift:78-81`、suiteName `com.degino.befold` = **ユーザーの実データ**)を使う。

現在書き込みを免れているのは `BefoldApp/BefoldCLI/CLIBookmarkCommand.swift:11` の `fileExists` ガードに引っかかる偶然だけで、ガードの順序が変われば `swift test` がユーザーのブックマークを破壊する。`bookmarkStore` は coding_rule.md の「単一の共有インスタンスはデフォルトなしの必須パラメータで注入」に反する static。

同ディレクトリの `CLICheckAndBookmarkDefaultsTests.swift:29` は `makeIsolatedDefaults` を正しく使っており、対比が際立つ。

## 2. テスト名が主張する内容を検証していない

同 L89-101 は「check -> bookmark の順で両方実行される」と名乗りながら、アサートは `ExitCode(1)`(L100)のみ。check だけ失敗しても同じ結果になるため、順序も両方実行も検証されていない。

## 3. ハードコードされた /tmp

L85 `/tmp/does-not-exist.md`、L99 `/tmp/does-not-exist-for-bookmark.md`。同スコープに `TempDir` があるのだから使う(実在すればテストが反転する)。

## 4. テストがコンソールを汚す

L83 / L86 / L100 の `run()` は `CLICommandResultPrinter`(`BefoldApp/BefoldCLI/CLICommandResult.swift:19-23`)経由でテストプロセスの実 stdout/stderr に印字する。

## 5. パラメタライズ漏れ(coding_rule.md のテスト規約違反)

- L120-124 / L133-137 / L139-143 / L145-149 — 4 テストとも「フラグ列 -> 期待 `CLIOpenOptions`」の同一構造。各テスト内で `#expect` を 2 本並べており、最初の失敗で残りが検証されない
- L52-55 / L70-74 / L126-131 / L151-154 / L156-159 — 5 テストとも「不正引数 -> throws」の同一構造
- L40-50 — `-h` と `--help` の 2 ブロック
- L201-212 — help 内の 7 文字列を `#expect` 直列
- L214-219 / L221-226 — discussion の部分文字列 2 件

## 6. 凝集

L228-232 `rejectReasonCliMessageIsEnglish` は `BefoldCLICommand` の parseAsRoot 検証スイート(L8-10 の `///` がそう宣言)と無関係。`RejectReason` のスイートへ移す。

## 良い点(維持すること)

L177-194 の `project.yml` 実パースによる `MARKETING_VERSION` ドリフト検知は、coding_rule.md のトートロジー禁止要件を正しく満たしている(相手側を書き換えれば落ちる)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BefoldCLICommandTests.swift がブランチにコミットされ CI で実行されている
- [ ] #2 テスト実行がユーザーの実 UserDefaults(com.degino.befold)に一切到達しない
- [ ] #3 check と bookmark の実行順序および両方が実行されることが実際に検証されている
- [ ] #4 テストが /tmp の固定パスに依存していない
- [ ] #5 テスト実行時にコマンド出力がテストコンソールへ漏れない
- [ ] #6 同一構造のテスト群が @Test(arguments:) に集約され、1 ケースの失敗が他ケースの検証を妨げない
- [ ] #7 RejectReason のテストが適切なスイートに移動している
<!-- AC:END -->
