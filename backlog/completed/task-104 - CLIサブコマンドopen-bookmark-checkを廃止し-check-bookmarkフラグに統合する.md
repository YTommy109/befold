---
id: TASK-104
title: CLIサブコマンド(open/bookmark/check)を廃止し--check/--bookmarkフラグに統合する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 02:30'
updated_date: '2026-07-23 04:04'
labels: []
dependencies:
  - TASK-97
references:
  - docs/superpowers/specs/2026-07-23-cli-flatten-subcommands-design.md
priority: high
ordinal: 92000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-94.4(openのオプションをトップレベルhelpにも表示する)とTASK-97(サブコマンド前のopen専用フラグを黙って捨てる問題の修正)が、@OptionGroup共有という同じ実装手段の下で対立し、後者の修正で前者の効果が失われた(befold --helpの先祖返りとしてユーザーから再報告)。根本原因はサブコマンド分割自体にあるため、open/bookmark/checkの3ParsableCommandを廃止し、単一のBefoldRootCommandに--check/--bookmarkブールフラグとして統合する。設計は docs/superpowers/specs/2026-07-23-cli-flatten-subcommands-design.md を参照。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold --help のトップレベルOPTIONSに --check/--bookmark/--hidden-files/--sort/--line-numbers/--source/--preview がすべて表示される
- [x] #2 befold --check a.md b.md が両方のパスをcheckし、いずれか1件でも失敗すれば終了コードが非0になる
- [x] #3 befold --bookmark a.md b.md が両方のパスをbookmarkに追加する
- [x] #4 befold --check --bookmark a.md がcheck→bookmarkの順で実行される
- [x] #5 --check/--bookmark 指定時はpathsが空だとエラーになり、ファイルは開かれない
- [x] #6 旧構文 befold bookmark add <path> / befold check <path> は受け付けない(クリーンブレイク)
- [x] #7 befold --hidden-files check.md のように旧サブコマンド名と同名のファイルパスがそのままopen対象として扱われる(サブコマンド解釈が存在しないことの確認)
- [x] #8 既存テスト(BefoldRootCommandTests/BefoldRootCommandIntegrationTests/CLIBookmarkCommandTests/CLICheckCommandTests)が新フラグ体系に合わせて更新され、swift testが全件成功する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: BefoldRootCommand.swift から OpenPathsCommand/BookmarkPassthroughCommand/CheckPassthroughCommand の3ParsableCommandを削除し、単一のBefoldRootCommandに--check/--bookmarkブールフラグ+共通paths引数へ統合。CLISubcommandCommand.swift のCLIBookmarkCommand/CLICheckCommandは単一パスを受け取る関数に変更し、独自--help/-hハンドリングと引数個数チェックを削除(ArgumentParserに委譲)。check→bookmarkの順で全pathsに実行し、いずれか1件でも失敗すれば終了コード非0(ExitCodeをthrowする方式、生のexit()は使わない)。

回帰: 新規テストがswift testのフル実行(--skip無し)でのみ signal 5 (SIGTRAP) でクラッシュする問題が発生。原因はMainActor.assumeIsolatedをMainActor外のスレッドから呼ぶ既存の危険パターン(run()内のbookmarkループ)を、@MainActor注釈なしのテスト関数から直接呼び出したため、フル並列実行時に非MainActorスレッドで実行されassumeIsolatedがtrapした。CLIBookmarkCommandTestsが元々@MainActorスイートだったのと同じ理由。修正: run()にbookmark=trueを含むテスト(checkAndBookmarkRunInOrderAndAggregateFailure)に@MainActorを付与。修正後、swift test をフル実行で3回連続成功(588 tests)。

検証: swift test(フル、3回連続、588 tests成功)/ swiftformat --lint(0/74 require formatting)/ 手動スモークテスト(befold --help の全オプション表示、befold --check <複数パス> の集計終了コード、befold --check(paths空)のエラー、befold bookmark add / befold check がサブコマンドとして解釈されずplain pathsになることを単体テストで確認)。

補足: AC#3(--bookmark 複数パス)は実UserDefaultsへの書き込みを避けるため、CLIBookmarkCommandTestsによる単一パスロジックの検証と、--checkループで検証済みの集計ロジックの構造的同一性(コードレビュー)を根拠としている。直接の複数パスbookmark統合テストは実UserDefaultsを汚染するリスクがあるため追加していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
open/bookmark/check の3ParsableCommandサブコマンドを廃止し、単一のBefoldRootCommand + --check/--bookmarkブールフラグ + 共通paths引数に統合した(BefoldRootCommand.swift, CLISubcommandCommand.swift)。これによりトップレベル--helpに全オプションが自動的に表示されるようになり(ArgumentParserの標準機構、サブコマンド分割自体が無いため位置依存のフラグ黙殺(TASK-97)も構造的に発生しない)、旧構文(befold bookmark add/befold check)はクリーンブレイクで廃止した。--check/--bookmarkは複数パスを対象にでき、併用時はcheck→bookmarkの順で実行し1件でも失敗すれば終了コード非0。BefoldRootCommandTests/BefoldRootCommandIntegrationTests/CLIBookmarkCommandTests/CLICheckCommandTestsを新フラグ体系に合わせて全面改訂し、swift testをフル実行で3回連続成功(588 tests)、swiftformat --lintも通過。実装中にrun()内のMainActor.assumeIsolatedを非MainActorテストから呼んでいたことによるフル並列実行時のSIGTRAPクラッシュを発見・修正した(該当テストに@MainActorを付与)。
<!-- SECTION:FINAL_SUMMARY:END -->
