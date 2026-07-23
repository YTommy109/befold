---
id: TASK-116.2
title: befold-cli サブプロセステストを安全化し befoldCLITests へ移設する
status: To Do
assignee: []
created_date: '2026-07-23 23:17'
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
- [ ] #1 サブプロセスを起動するテストが、応答しない場合でも有限時間で失敗して終了する
- [ ] #2 サブプロセスの stdout/stderr が必ず drain され、テストコンソールに出力が漏れない
- [ ] #3 Process 起動の定型処理が単一のヘルパーに集約されている
- [ ] #4 テストが befold-cli への依存を宣言したターゲットに配置されており、そのターゲット単独でも実行できる
- [ ] #5 in-process テストと重複するサブプロセステストが削除され、サブプロセス起動回数が減っている
- [ ] #6 ファイル名・スイート名が一致し、未使用の import が無い
<!-- AC:END -->
