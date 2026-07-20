---
id: TASK-73.1
title: CLI 引数パーサー基盤を整備し --help を充実させる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 09:10'
updated_date: '2026-07-20 12:00'
labels: []
dependencies: []
parent_task_id: TASK-73
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 CLIInstaller.shimScriptContents は `exec open -a <bundle> "$@"` のみで、
open(1) の挙動上、追加引数がオプションフラグかファイルパスか区別できない
（open -a はファイル起動用の引数として扱う想定のため、フラグを渡すには
`--args` 経由でアプリ本体に引数を転送するようシム自体の見直しが必要になる可能性がある）。
このタスクでは、他サブタスクが実装する各種オプション・サブコマンドを受け止められる
引数パーサー基盤を用意し、`befold --help` で usage・オプション一覧・サブコマンド一覧を
表示できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold --help / -h で usage、各オプションの説明、各サブコマンドの説明が表示される
- [x] #2 不明なオプション・サブコマンドを指定した場合はエラーメッセージと usage を表示して終了する
- [x] #3 CLI シムがオプションフラグをファイルパスと区別してアプリ本体まで渡せる（open -a の制約がある場合はシムの起動方式を見直す）
- [x] #4 既存のファイルパス指定での起動（フラグなし）が引き続き動作する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstaller.shimScriptContents を open -a 経由から <bundle>/Contents/MacOS/befold を直接 exec する形に変更する（open -a --args は既に起動中のインスタンスに argv を届けられないため）。CLIInstallerTests の期待値も更新する。
2. 新規 CLIArgumentParser.swift（App/）を追加: CommandLine.arguments を解析し CLICommand(.help / .openPaths([String]) / .subcommand(name, args)) を返す純粋関数として実装。未知の -- オプションはエラー、サブコマンドは登録制（現時点は空、73.4/73.5 で登録）。usageText も定義。
3. AppDelegate.main() で app.run() 前に argv をパースし: --help → usage を stdout に出力し exit(0)。不明オプション → usage を stderr に出力し exit(64)。openPaths → 既存インスタンスが起動中なら NSWorkspace 経由でそのインスタンスにファイルを転送して当プロセスは exit(0)、未起動ならそのまま GUI 起動し渡された paths を初期ウィンドウとして開く。空 argv は現行動作のまま。
4. CLIArgumentParserTests.swift を新規追加（Swift Testing）。
5. swift build / swift test で確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: CLIArgumentParser(新規)でargvを解析(.help/.openPaths/.subcommand、未知オプションはエラー、サブコマンドは登録制で現時点は空)。CLIInstaller.shimScriptContentsをopen -a経由からbundle内バイナリの直接execに変更(open -a --argsは起動中インスタンスにargvを届けられないため)。AppDelegate.main()でapp.run()前にargvを解析し、--help→usage表示してexit(0)、不明オプション→stderrにusage付きエラーを表示してexit(64)、openPaths→既存インスタンスが起動中ならCLIInstanceRouter経由でNSWorkspace.open(urls:withApplicationAt:)により転送してexit(0)、なければ新規GUI起動してinitialPathsを開く。空argv時は既存のsessionRestorer.restoreLastSession()経路を維持しAC4を満たす。検証: swift build成功、swift test 489件全パス(CLIArgumentParserTests新規7件、CLIInstallerTests更新1件含む)、swiftlintで新規ファイルに違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI引数パーサー基盤(CLIArgumentParser)とインスタンス転送(CLIInstanceRouter)を追加し、CLIシムをbundle内バイナリ直接execに変更した。--help/-hでusageを表示、不明オプションはエラー+usageを表示して終了、パス指定は既存インスタンスへ転送または新規GUI起動で開く。既存のフラグなしファイルパス起動・GUI起動は影響を受けない。swift build/testで検証済み(489テスト全パス)。後続のTASK-73.2〜73.5がこの基盤を利用してサブコマンド・オプションを追加する。
<!-- SECTION:FINAL_SUMMARY:END -->
