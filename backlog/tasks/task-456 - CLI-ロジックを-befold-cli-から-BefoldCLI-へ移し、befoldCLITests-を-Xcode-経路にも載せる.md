---
id: TASK-456
title: CLI ロジックを befold-cli から BefoldCLI へ移し、befoldCLITests を Xcode 経路にも載せる
status: Done
assignee: []
created_date: '2026-08-11 23:28'
updated_date: '2026-08-13 07:25'
labels:
  - ci
dependencies: []
priority: low
type: chore
ordinal: 680000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-439 で確定した残差。

`befoldCLITests` の 14 suites / 72 tests は `swift test` でのみ実行され、`xcodebuild test` では実行されない。8 ファイルが `@testable import befold_cli` で**実行ファイルターゲット**の中身に触るため Xcode ではテストホストが必要だが、**Xcode は plain tool を TEST_HOST として受け付けない**（実測: project.yml へ `TEST_HOST: \$(BUILT_PRODUCTS_DIR)/befold-cli` を書くと、バイナリが実在していても `Could not find test host for befoldCLITests` でスキーム構築の時点で落ちる。スキームのビルド対象に befold-cli を追加しても同じ）。

載せるには、`CLIAppLauncher` / `BefoldCLICommand` / `CLIBookmarkRouter` / `ProcessLaunching` / `AckWaiting` などの CLI ロジックを `befold-cli`（executable）から `BefoldCLI`（framework）へ移し、実行ファイル側を薄い main だけにする構造変更が要る。

現状のずれは project.yml のコメントと `PackageProjectTargetParityTests` の `packageOnlyTargets` に明記してあり、黙って壊れることはない。CI は `swift test` のみを実行するため、CI で走るテスト集合には影響しない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI ロジックが BefoldCLI へ移り、befold-cli は薄い main のみになっている
- [x] #2 project.yml に befoldCLITests ターゲットがあり、xcodebuild test で実行される
- [x] #3 PackageProjectTargetParityTests の packageOnlyTargets が空になっている
- [x] #4 swift test と xcodebuild test のテスト件数が一致する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLI ロジック 6 ファイル（AckWaiting / BefoldCLICommand / CLIAppLauncher / CLIBookmarkRouter / CLIRequestForwarder / OpenCLIOptions）を befold-cli から BefoldCLI framework へ移す。
2. BefoldCLICommand は public にせず、`BefoldCLIEntryPoint.run()` の 1 点だけを公開入口にする（ArgumentParser の宣言まで public 化すると framework の公開 API がコマンドラインの内部構造そのものになる）。
3. befold-cli は `@main enum BefoldCLIExecutable` が `BefoldCLIEntryPoint.run()` を呼ぶだけにする。
4. ArgumentParser 依存を BefoldCLI へ移す（Package.swift と project.yml の両方）。QuickLook 拡張は BefoldCLI に依存しないため appex には入らない。
5. befoldCLITests の `@testable import befold_cli` を `@testable import BefoldCLI` へ。テスト依存から befold-cli を外す。
6. project.yml に befoldCLITests（bundle.unit-test、TEST_HOST なし）を追加し、befold スキームの test targets へ入れる。
7. PackageProjectTargetParityTests の packageOnlyTargets を空にする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- CLI ロジック 6 ファイルを `befold-cli` -> `BefoldCLI` へ移動（git mv）。`befold-cli` は `BefoldCLIExecutable.swift`（@main、`BefoldCLIEntryPoint.run()` を呼ぶだけ）の 1 ファイルのみになった。
- 公開面は `BefoldCLIEntryPoint` の 1 点に絞った。`BefoldCLICommand` を public にすると `@Flag` / `@Option` / `@Argument` の宣言まで public 化が要り、framework の公開 API がコマンドラインの内部構造になるため。
- ArgumentParser 依存は BefoldCLI へ移した（Package.swift / project.yml の両方。片方だけだと `xcodebuild` が Undefined symbol でリンク失敗する。実測済み）。QuickLook 拡張は BefoldCLI に依存しないため appex には入らない。
- project.yml の befoldCLITests は TEST_HOST を持たない bundle.unit-test。ロジックが framework にあるためテストホストが不要になった（これが本タスクの目的そのもの）。

## 検証（実測）

- `swift test`（全件・skip なし）: **1478 tests / 234 suites 通過**
- `xcodebuild test -scheme befold -destination 'platform=macOS'`: **passedTests 1478 / failedTests 0 / skippedTests 0**（resultBundle を xcresulttool で集計）。**両経路の件数が一致**（AC #4）。
- 結果バンドルに `befoldCLITests` バンドルと CLI テスト名（`befold-cli --version は…` 等）が含まれることを確認（AC #2）。
- CLI の実動作: `.build/debug/befold-cli --version` -> `1.12.3`、`--help` が正常に出力される。
- swiftlint: main とのベースライン差分 **ゼロ**（git archive origin/main で別ディレクトリへ展開して比較。両者 65 件）。移設中に生じた duplicate_imports 2 件は解消済み。
- markdownlint-cli2: 0 issues。`check-type-group-size.sh` / `check-doc-symbols.sh` 通過。

## ドキュメント

`docs/dev/native-app-design.md` のモジュールツリーと依存表を更新（BefoldCLI が CLI 本体、befold-cli は薄い入口）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI ロジック 6 ファイルを befold-cli から BefoldCLI framework へ移し、実行ファイルを @main の薄い入口だけにした。これで befoldCLITests がテストホストを必要としなくなり、project.yml へ追加して xcodebuild test 経路に載せた。swift test 1478 件と xcodebuild test 1478 件が一致（いずれも失敗 0）。swiftlint はベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
