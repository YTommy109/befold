---
id: TASK-76
title: CLI引数パーサーをswift-argument-parserへ移行する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 00:00'
updated_date: '2026-07-21 00:21'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
自前のCLIArgumentParser(argv手動走査)はcheck/bookmarkという名前のパスとサブコマンド名の衝突(task-73.9)、ハイフンで始まるパス名の誤認識(task-73.10)など、標準的なCLIパーサーライブラリなら型システムと--ターミネータで自然に回避できる不具合を繰り返し生んでいる。swift-argument-parserを導入し、CLIArgumentParser/CLISubcommandCommand/AppDelegate.mainのディスパッチをArgumentParserベースに置き換える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 swift-argument-parserへ移行し、CLIArgumentParserの自前argv走査を廃止する
- [x] #2 check/bookmarkという名前のパス、ハイフンで始まるパスを--エスケープで開ける
- [x] #3 既存のCLI機能(パス複数指定・表示オプション・bookmark/checkサブコマンド・--help)がすべて動作し、swift test全件パスする
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Package.swift/project.ymlにswift-argument-parser依存を追加\n2. CLIArgumentParser.swiftを廃止し、BefoldRootCommand.swiftへ全面移行(ParsableCommand)\n3. ルートコマンド自体には positional 引数を持たせない(subcommands併用時に配列引数がサブコマンド名を飲み込む実装上の制約が判明したため、defaultSubcommand=OpenPathsCommand(非表示)へ委譲する構成にする)\n4. bookmark/checkサブコマンドはcaptureForPassthroughで既存のCLIBookmarkCommand/CLICheckCommandへ委譲し、それらの実装・テストは変更しない\n5. AppDelegate.main()をparseAsRoot+run()ベースに書き換え、--help/エラー表示はBefoldRootCommand.exit(withError:)に委譲する\n6. --helpのUSAGE/OPTIONS説明が失われないようCommandConfigurationのusage/discussionに明記する\n7. xcodegen generateでXcodeプロジェクトへ依存を反映、swift build/testで検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Package.swift/project.ymlにswift-argument-parser(1.5.0)依存を追加。CLIArgumentParser.swiftを削除し、BefoldRootCommand.swift(ParsableCommand)へ全面移行。判明した制約: ルートコマンドに@Argument var paths:[String]とsubcommandsを併置すると、配列引数が'bookmark'/'check'を先に飲み込みサブコマンド解決が機能しない(実機検証で確認)。回避策としてルートはsubcommands一覧のみを持ち、パス・表示オプションはdefaultSubcommand指定のOpenPathsCommand(shouldDisplay:false、CLI上は隠しサブコマンド)に持たせた。bookmark/checkサブコマンドは@Argument(parsing:.captureForPassthrough)で生の引数配列を捕捉し、既存のCLIBookmarkCommand.run/CLICheckCommand.run(シグネチャ・実装・テスト共に無変更)へそのまま委譲。AppDelegate.main()はparseAsRoot()+command.run()、エラー/ヘルプはBefoldRootCommand.exit(withError:)に一本化。--helpでオプション一覧が消えないようCommandConfiguration.usage/discussionに明記。xcodegen generateでXcodeプロジェクトにも依存追加を反映。CLIArgumentParserTests.swiftを削除しBefoldRootCommandTests.swiftへ書き換え(--エスケープでcheck/bookmark名パス・ハイフン始まりパスが開けることを検証)。CLIBookmarkCommandTests/CLICheckCommandTests/CLIInstanceRouterTestsは無変更のまま全パス。swift test 522件全パス、swiftlint新規警告なし。実バイナリでbefold --help/check/bookmarkの手動検証済み(GUI起動を伴うopenPathsパスは自動テスト環境では検証不可のためユニットテストの--エスケープ検証で代替)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
自前argv走査のCLIArgumentParserを廃し、swift-argument-parserベースのBefoldRootCommand(+隠しdefaultSubcommand OpenPathsCommand、bookmark/checkはcaptureForPassthroughで既存実装へ委譲)へ移行した。--エスケープでcheck/bookmark名パスやハイフン始まりパスを開けるようになり(task-73.9/73.10相当)、--help/エラー表示もArgumentParserの検証済み実装に委譲される。
<!-- SECTION:FINAL_SUMMARY:END -->
