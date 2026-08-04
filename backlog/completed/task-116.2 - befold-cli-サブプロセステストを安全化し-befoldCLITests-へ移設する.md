---
id: TASK-116.2
title: befold-cli サブプロセステストを安全化し befoldCLITests へ移設する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:17'
updated_date: '2026-07-23 23:46'
labels:
  - test
  - cli
dependencies:
  - TASK-116.1
parent_task_id: TASK-116
priority: high
ordinal: 30200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befoldTests/BefoldRootCommandIntegrationTests.swift`(本ブランチで +107 行書き換え、実サブプロセス起動に変更)の構造的な問題をまとめて解消する。

## 1. タイムアウト保護が無い

全 6 テスト(L10 / L32 / L58 / L83 / L109 / L126)が `process.waitUntilExit()` を `.timeLimit` なしで呼ぶ。Swift Testing にグローバルタイムアウトは無いため、`befold-cli` がブロックすれば CI ジョブごと無期限ハングする。

現状の引数(`--version` / `--help` / `--check <path>`)では befold.app 起動経路に到達しないことは確認済み(`BefoldApp/befold-cli/BefoldCLICommand.swift:43` の `if !check, !bookmark` を通らない。ローカル実測で exit 0 / 0 / 1)。しかしパスのみを渡すテストを 1 本足した瞬間に `/usr/bin/open -a` の `waitUntilExit()`(CLIAppLauncher.swift:15-22)+ 既定 10 秒のポーリング(同 :59,:86-91)+ `maxAttempts 3 × ackTimeout 0.5s` の RunLoop 待ち(CLIInstanceRouter.swift:58-64,70-84)に入る。構造的に防いでいるものが何も無い状態。

なお `func ... throws`(同期)なので `.timeLimit` を付けても `waitUntilExit()` の同期ブロックは中断できない。実効的な保護は「明示的な期限 + `process.terminate()`」または async 化。

## 2. Pipe を drain していない

`checkFlagWithoutPathFails`(L116-118)は stderr パイプを設定して一度も読み出さない(他 5 本は `readDataToEndOfFile()` を先に呼ぶ正しい順序)。ArgumentParser の usage は 64KB 未満なので現状は詰まらないが、パイプバッファ枯渇デッドロックそのもののパターンで、読み出しハンドルも閉じられずリークする。stdout はリダイレクトされておらず usage がテストコンソールに漏れる。

## 3. Process ボイラープレートの 6 重複

L14-21 / L36-42 / L64-71 / L89-96 / L113-118 / L129-136。coding_rule.md の「定型が 3 回以上なら private func に抽出」違反。`runCLI(_ args:currentDirectory:) -> (status, stdout, stderr)` に集約すれば、両パイプの確実な drain と期限付き terminate を 1 箇所で担保でき、上記 1 と 2 が同時に解消する。

## 4. 配置ターゲットが誤り

このファイルは `befoldTests/` にあるが、`BefoldApp/Package.swift:89` のとおり befoldTests の依存は `["befold", "BefoldKit", "BefoldCLI", "BefoldRenderKit"]` で **`befold-cli` を含まない**。テスト対象バイナリのビルドがビルドグラフ上保証されておらず、`swift test` が全ターゲットをビルドするので偶然通っているだけ。`--filter` で befoldTests だけ回すと L163 の `#require` が落ち得る。`befoldCLITests/`(Package.swift:97 で befold-cli に依存)へ移すのが正しい。

## 5. 重複テストの削減

サブプロセス版が固有に検証している価値は「バイナリが実際に起動し、その終了コードで終わる」ことと、`currentDirectoryURL` を使う相対パス解決(L83-104、in-process では再現不可)だけ。以下は in-process 版と同内容:

| サブプロセス版 | 同内容の in-process 版 |
|---|---|
| L31-53 `helpDisplaysAllOptionsAtTopLevel` | `BefoldCLICommandTests.swift:201-212` |
| L106-121 `checkFlagWithoutPathFails` | `BefoldCLICommandTests.swift:70-74` |
| L123-143 `checkFlagWithMissingPathFails` | `BefoldCLICommandTests.swift:76-87` |

## 6. 名前の不整合

ファイル名は `BefoldRootCommandIntegrationTests.swift` だがスイートは `BefoldCLIIntegrationTests`(L8)。`BefoldRootCommand` 型はもう存在しない。L1 `import ArgumentParser` は未使用、L2 `@testable import BefoldCLI` も不要(`AppVersion.current` は public)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サブプロセスを起動するテストが、応答しない場合でも有限時間で失敗して終了する
- [x] #2 サブプロセスの stdout/stderr が必ず drain され、テストコンソールに出力が漏れない
- [x] #3 Process 起動の定型処理が単一のヘルパーに集約されている
- [x] #4 テストが befold-cli への依存を宣言したターゲットに配置されており、そのターゲット単独でも実行できる
- [x] #5 in-process テストと重複するサブプロセステストが削除され、サブプロセス起動回数が減っている
- [x] #6 ファイル名・スイート名が一致し、未使用の import が無い
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldApp/befoldTests/BefoldRootCommandIntegrationTests.swift を削除し、BefoldApp/befoldCLITests/BefoldCLIIntegrationTests.swift として作り直す(AC#4/#6: befold-cli に依存するターゲットへ移設、ファイル名とスイート名 BefoldCLIIntegrationTests を一致させる)。

2. private func runCLI(_ arguments:currentDirectory:timeout:) -> (status, stdout, stderr) を用意し、6 箇所の Process 定型を集約する(AC#3)。
   - 出力は Pipe ではなく TempDir 内の一時ファイルへリダイレクトする。パイプはバッファ(64KB)が埋まると子の write がブロックし親の読み出し待ちとデッドロックするが、ファイルには上限が無いため読み出し順序を気にせず安全(AC#2)。並行読み出しスレッドも不要になり、TASK-116.1 で除去した fd 手術の再発も防げる。
   - process.isRunning を期限までポーリングし、期限超過なら Issue.record した上で terminate → 残存すれば SIGKILL。同期関数のため .timeLimit では中断できない waitUntilExit を、明示的な期限で保護する(AC#1)。

3. in-process テストと重複する 4 テストを削除する(AC#5)。重複の裏取り済み:
   - helpDisplaysAllOptionsAtTopLevel → BefoldCLICommandTests.allOptionsAppearInTopLevelHelp が同じ 7 文字列を検証
   - checkFlagWithoutPathFails → BefoldCLICommandTests.checkOrBookmarkWithoutPathsThrows
   - checkFlagWithMissingPathFails → BefoldCLICommandTests.checkAggregatesMultiplePathsAndFailsIfAnyFails(ExitCode 1)+ CLICheckCommandTests:27-36(No such path のメッセージ)
   - checkFlagRunsAsRealSubprocess → checkFlagResolvesRelativePath が exit 0 と Can open: を同時に検証しており完全に包含される
   残すのは versionFlagPrintsVersionAndExitsSuccessfully(実バイナリでの AppVersion 解決は in-process で再現不可)と checkFlagResolvesRelativePath(currentDirectoryURL の効果は実プロセスでしか検証不可)の 2 本。サブプロセス起動は 6 回 → 2 回。

4. 未使用の import ArgumentParser と不要な @testable import BefoldCLI を除去する(AC#6)。

5. 検証: swift test を完走させ、テスト数と所要時間を記録する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
befoldTests/BefoldRootCommandIntegrationTests.swift を削除し、befoldCLITests/BefoldCLIIntegrationTests.swift として作り直した。

設計判断: 出力を Pipe ではなく TempDir 内の一時ファイルへリダイレクトした。パイプはバッファ(64KB)が埋まると子の write がブロックし親の読み出しと待ち合うが、ファイルには上限が無く読み出し順序も問わない。並行読み出しスレッドが不要になるため、TASK-116.1 で除去した fd 手術・並行処理の再発も構造的に防げる。

検証:
- AC#1(有限時間で失敗して終了): runCLI のタイムアウト経路のみを抜き出したスタンドアロン実行ファイルで、応答しない子プロセス(/bin/sleep 60)に対し timeout=2 秒を与えて実測。elapsed=2.09s / issueRecorded=true / stillRunning=false / status=15(SIGTERM)。期限超過を検知して確実に終了させられることを確認した。
- AC#2(drain とコンソール非汚染): --version テストが stdout の内容を AppVersion.current と厳密一致で検証して pass しており、出力が確実に捕捉されている。テストコンソールへの usage 漏れも無い。
- AC#3(定型の集約): Process 起動の 6 重複を private func runCLI(_:currentDirectory:timeout:) 1 箇所へ集約。
- AC#4(ターゲット単独実行): swift test --filter BefoldCLIIntegrationTests が 2 tests / 1 suite を 0.104 秒で pass。befoldCLITests ターゲット単独でも 47 tests / 5 suites が 0.142 秒で pass。Package.swift:97 で befold-cli への依存が宣言済みのため、ビルドグラフ上もテスト対象バイナリの存在が保証される。
- AC#5(重複削除): 4 テストを削除しサブプロセス起動を 6 回 → 2 回に削減。全体のテスト数は 605 → 601。削除対象の重複は事前に in-process 側の該当テストを読んで裏取りした。
- AC#6(名前一致・未使用 import): ファイル名とスイート名を BefoldCLIIntegrationTests に統一。import ArgumentParser と @testable import BefoldCLI(→ import BefoldCLI)を整理。grep で BefoldRootCommand の残存参照が無いことを確認。
- 全体: swift test が 601 tests / 76 suites を 13.509 秒で pass。SwiftFormat --lint は全ターゲット 0 files require formatting。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold-cli の実サブプロセステストを befoldTests から befoldCLITests へ移設し、BefoldCLIIntegrationTests.swift としてファイル名とスイート名を一致させた。befoldTests は Package.swift 上 befold-cli に依存していないため、テスト対象バイナリのビルドがビルドグラフ上保証されていなかった問題を解消した。

Process 起動の 6 重複を runCLI ヘルパー 1 箇所に集約し、(1) 出力を一時ファイルへリダイレクトしてパイプバッファ枯渇デッドロックを構造的に排除、(2) 明示的な期限でポーリングし応答しなければ Issue.record → terminate → SIGKILL する保護を追加した。同期関数のため .timeLimit では waitUntilExit を中断できないという制約に対する実効的な対策になっている。

in-process テストと重複する 4 テスト(help 全オプション表示・--check 引数なし・--check 存在しないパス・--check 成功系)を、重複先を実際に読んで裏取りした上で削除し、サブプロセス起動を 6 回 → 2 回に削減した。残したのは実バイナリでしか検証できない --version(AppVersion 解決)と --check 相対パス(currentDirectoryURL の効果)の 2 本。

検証: タイムアウト経路は /bin/sleep 60 を用いたスタンドアロン実測で 2.09 秒での確実な終了を確認。swift test 全体が 601 tests / 76 suites を 13.509 秒で pass、befoldCLITests 単独でも 47 tests が pass。SwiftFormat --lint クリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
