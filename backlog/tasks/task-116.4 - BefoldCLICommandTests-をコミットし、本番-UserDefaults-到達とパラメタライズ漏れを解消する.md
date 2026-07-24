---
id: TASK-116.4
title: BefoldCLICommandTests をコミットし、本番 UserDefaults 到達とパラメタライズ漏れを解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:18'
updated_date: '2026-07-24 00:08'
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
- [x] #1 BefoldCLICommandTests.swift がブランチにコミットされ CI で実行されている
- [x] #2 テスト実行がユーザーの実 UserDefaults(com.degino.befold)に一切到達しない
- [x] #3 check と bookmark の実行順序および両方が実行されることが実際に検証されている
- [x] #4 テストが /tmp の固定パスに依存していない
- [x] #5 テスト実行時にコマンド出力がテストコンソールへ漏れない
- [x] #6 同一構造のテスト群が @Test(arguments:) に集約され、1 ケースの失敗が他ケースの検証を妨げない
- [x] #7 RejectReason のテストが適切なスイートに移動している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
プロダクト側: BefoldCLICommand.run() の実体を execute(addBookmark:printResult:) へ切り出し、ブックマークの追加先と結果の出力先を注入可能にした(ユーザー承認済みの方針)。ArgumentParser の run() は引数を取れないため、run() が既定依存(bookmarkStore / CLICommandResultPrinter.print)を渡して execute を呼ぶ形にしている。static let bookmarkStore は run() からのみ参照される。

検証:
- AC#2(実 UserDefaults 非到達): テスト実行の前後で defaults read com.degino.befold の md5 を比較し、完全に不変であることを実測(ea84ef1cab19c467284ce5714c3f931a で一致)。従来は CLIBookmarkCommand の fileExists ガードに引っかかる偶然だけで書き込みを免れていたが、注入により経路自体が存在しなくなった。
- AC#5(コンソール非汚染): befoldCLITests の実行出力を grep し、Can open: / Bookmarked: / No such path: の漏れが 0 行であることを確認。
- AC#3(順序と両方実行): checkAndBookmarkRunInOrderAndAggregateFailure を書き換え、printResult で収集した 4 件のメッセージの並び(check 2 件 → bookmark 2 件)と、bookmarked に実在パスのみが入ることを検証。従来は ExitCode(1) しか見ておらず、check 単独失敗と区別できていなかった。
- AC#4(/tmp 非依存): /tmp/does-not-exist.md と /tmp/does-not-exist-for-bookmark.md を TempDir 配下の missing.md に置き換え。
- AC#6(パラメタライズ): 表示オプション 4 テスト → 1 本(8 ケース)、不正引数 5 テスト → 1 本(6 ケース)、-h/--help → 1 本(2 ケース)、--help の 7 文字列 → 1 本(7 ケース)、discussion 2 件 → 1 本(2 ケース)に集約。いずれも 1 ケースの失敗が他ケースの検証を妨げない形になった。
- AC#7(凝集): rejectReasonCliMessageIsEnglish を RejectReasonCLIMessageTests スイートへ分離(BefoldCLICommandTests は parseAsRoot 検証のスイートであると /// が宣言しているため)。
- 全体: swift test が 593 tests / 77 suites を 13.815 秒で pass。SwiftFormat --lint は全ターゲットでクリーン。AC#1(コミットして CI に載せる)は本コミットで tracked になり、以降の CI 実行対象となる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
untracked のままで CI に一度も載っていなかった BefoldCLICommandTests.swift をコミットし、あわせて同ファイルが抱えていた問題を解消した。

最も重大だったのは、run() 経由のテストが BefoldCLICommand.bookmarkStore(suiteName com.degino.befold = 利用者の実データ)に到達していたこと。書き込みを免れていたのは CLIBookmarkCommand の fileExists ガードに引っかかる偶然だけで、ガード順序が変われば swift test が利用者のブックマークを破壊しうる状態だった。run() の実体を execute(addBookmark:printResult:) へ切り出し、ブックマーク追加先と結果出力先を注入可能にして経路自体を断った(ArgumentParser の run() は引数を取れないため、run() が既定依存を渡して execute を呼ぶ形)。

テスト名が主張しながら検証していなかった「check→bookmark の順で両方実行される」ことを、収集したメッセージ 4 件の並びと bookmarked の内容で実際に検証するようにした。/tmp の固定パスを TempDir 配下へ移し、同一構造の 5 群を @Test(arguments:) に集約(表示オプション 8 ケース・不正引数 6 ケース・ヘルプフラグ 2 ケース・--help 文字列 7 ケース・discussion 2 ケース)、RejectReason のテストを別スイートへ分離した。

検証: テスト実行前後で defaults read com.degino.befold の md5 が完全一致(実 UserDefaults 不変)、CLI 出力のコンソール漏れ 0 行を実測。swift test は 593 tests / 77 suites を 13.815 秒で pass、SwiftFormat --lint はクリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
