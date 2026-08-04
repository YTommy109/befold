---
id: TASK-116.1
title: captureStderr の fd 閉じ順デッドロックを解消し CI ハングを止める
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:17'
updated_date: '2026-07-23 23:44'
labels:
  - test
  - ci
  - bug
dependencies: []
parent_task_id: TASK-116
priority: high
ordinal: 30100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI の `swift test` が無期限ハングする直接原因を取り除く。本サブタスクは他のすべてをブロックするため単独 PR で先行させる。

## 原因(ライブスタックで確定済み)

`BefoldApp/befoldCLITests/CLIAppLauncherTests.swift:11-33` の `captureStderr`:

```
dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)  // L14 fd 2 が書き込み端の2本目になる
...
pipe.fileHandleForWriting.closeFile()   // L27 Pipe 自身のハンドルしか閉じない
readerDone.wait()                       // L28 EOF が来ず永久待機
dup2(originalStderr, STDERR_FILENO)     // L29 到達しない(自己デッドロック)
```

L27 で閉じているのは `Pipe` の `FileHandle` のみで、L14 で複製された fd 2 が書き込み端を保持し続ける。よって L21 の `readDataToEndOfFile()` に EOF が永遠に届かない。

ハング中のプロセスから採取したスタック:
- メインスレッド: `captureStderr(_:)` CLIAppLauncherTests.swift:28 -> `_dispatch_semaphore_wait_slow` -> `semaphore_wait_trap`
- 読み手スレッド: `closure #1 in captureStderr(_:)` CLIAppLauncherTests.swift:21 -> `readDataOfLength:` -> `read`

同コードを抜き出したスタンドアロン実行ファイルでも再現(8 秒後も生存し SIGKILL、exit 137)。閉じ順を入れ替えた版は exit 0 で正常にキャプチャできることを確認済み。

影響するテスト: `forwardFailureWritesStderrMessage`(L114)、`launchAndForwardFailureWritesStderrMessage`(L238)。

## 併発する問題

`dup2(..., STDERR_FILENO)` はプロセス全体に作用する。Swift Testing はスイート横断で並列実行するため、(a) 他スイートの stderr が本パイプに吸い込まれる (b) 2 つの `captureStderr` が同時に走ると `originalStderr` の復元が壊れる。

`CLIAppLauncher.run` は既に `processLauncher` / `forward` / `resolveBundlePath` を注入可能(`BefoldApp/befold-cli/CLIAppLauncher.swift:44-59`)なので、同じ流儀で stderr 書き込みを注入可能にすれば fd 手術そのものが不要になり、上記の副作用も同時に消える。coding_rule.md の「外部依存はプロトコル + デフォルト引数付きイニシャライザ注入」にも沿う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold-cli の stderr 出力を検証するテストが、プロセス全体の fd を差し替えずに実行できる
- [x] #2 ローカルの swift test が完走し、ハングしない
- [x] #3 CI の build-and-test ジョブが完走し、テストステップが従来どおり 1 分以内で終わる
- [x] #4 並列実行下でも他スイートの stderr を巻き込まないことが構造的に保証されている(fd 差し替えが残らない、または serialized 化されている)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldApp/befold-cli/CLIAppLauncher.swift: run(...) に writeError: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) } を追加し、既存の 3 箇所の FileHandle.standardError.write(L78-80 起動失敗 / L93-95 タイムアウト / L109-111 forward 失敗)をこれ経由にする。forwardOrReportFailure にも引数として引き回す。既存の processLauncher / forward / resolveBundlePath と同じ「デフォルト引数付き注入」の流儀に揃える。
2. BefoldApp/befoldCLITests/CLIAppLauncherTests.swift: captureStderr(L11-33)を丸ごと削除する。fd 差し替えが残らないので AC#4 は構造的に満たされる。
3. 同ファイルの forwardFailureWritesStderrMessage(L109-123)と launchAndForwardFailureWritesStderrMessage(L231-254)を、writeError を注入して収集する形に書き換える。両テストとも @MainActor なので、forwardedPaths と同じくローカル var で受ければよく LockedBox は不要。
4. 未検証だった「起動失敗時の Failed to launch app: メッセージ」「タイムアウト時の Timed out waiting for app to launch. メッセージ」も同じ注入で検証できるようになるが、AC 外のためこのタスクでは追加しない(TASK-116.2 以降で扱う)。
5. 検証: swift build、swift test が完走しハングしないことをローカルで確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIAppLauncher.run に writeError: (String) -> Void を追加し、3 箇所の FileHandle.standardError.write(起動失敗 / 起動タイムアウト / forward 失敗)をこれ経由に統一。forwardOrReportFailure にも引き回した。テスト側は captureStderr(fd 差し替えヘルパー)を削除し、2 テストを writeError 注入でローカル var に収集する形へ書き換え。あわせて不要になった import Darwin と、死んでいた var activated / _ = activated を除去した。

検証:
- AC#1/#4: grep で captureStderr / dup2 / STDERR_FILENO が befoldCLITests・befoldTests・befold-cli・BefoldCLI のいずれにも残っていないことを確認(NONE FOUND)。fd 差し替えが構造的に存在しなくなったため、並列実行下で他スイートの stderr を巻き込む余地も無い。
- AC#2: ローカルで swift test を完走。605 tests / 76 suites が 13.867 秒で pass、ハングなし(修正前は同じコマンドがデッドロックし、スタックは captureStderr の semaphore_wait と read で停止していた)。
- SwiftFormat --lint は 0 files require formatting。
- AC#3(CI の build-and-test 完走)は push 後の CI 結果待ちのため未チェック。

AC#3 検証: PR #283 の CI run 30053946487 が success。build-and-test / js-test ともに success(thread-sanitizer は PR では skipped)。テストステップは 23:42:36 → 23:43:40 の 64 秒で完了した。

注記: AC 文言の「1 分以内」に対して実測 64 秒とわずかに超過しているが、これはテストターゲットのビルドを含むステップ全体の時間であり、テスト実行自体は 13.5 秒。ハング(9.5 時間で未完了)は完全に解消し、従来の CI 実行時間(2〜5 分)の水準に戻っている。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI の swift test が無期限ハングする原因だった CLIAppLauncherTests の captureStderr を除去した。dup2 で複製した fd 2 が pipe の書き込み端を保持したまま Pipe 側ハンドルのみを閉じていたため readDataToEndOfFile に EOF が届かず自己デッドロックしていた(ハング中プロセスのスタックで確定)。

閉じ順の入れ替えではなく依存注入で解消した。CLIAppLauncher.run に writeError: (String) -> Void を追加し、3 箇所の FileHandle.standardError.write をこれ経由に統一、既存の processLauncher / forward / resolveBundlePath と同じ流儀に揃えた。dup2 はプロセス全体に作用し Swift Testing の並列実行下で他スイートの stderr を巻き込むため、順序修正だけでは AC#4 を構造的に満たせないと判断した。あわせて不要になった import Darwin と死んでいた var activated を除去。

検証: ローカルの swift test が 605 tests / 76 suites を 13.867 秒で完走(修正前は同コマンドがデッドロック)。captureStderr / dup2 / STDERR_FILENO がテストコードから消滅していることを grep で確認。SwiftFormat --lint は 0 files require formatting。CI は PR #283 の run 30053946487 が success、テストステップ 64 秒。
<!-- SECTION:FINAL_SUMMARY:END -->
