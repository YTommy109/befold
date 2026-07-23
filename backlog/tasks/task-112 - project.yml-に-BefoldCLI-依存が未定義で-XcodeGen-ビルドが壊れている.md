---
id: TASK-112
title: project.yml に BefoldCLI 依存が未定義で XcodeGen ビルドが壊れている
status: Done
assignee: []
created_date: '2026-07-23 12:19'
updated_date: '2026-07-23 12:40'
labels:
  - bug
  - build
dependencies: []
priority: high
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold ターゲットのソースファイルが import BefoldCLI しているが、project.yml に BefoldCLI のターゲット定義・依存関係がない。xcodegen generate → xcodebuild build -scheme befold が no such module BefoldCLI で失敗する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 project.yml に BefoldCLI ターゲットと befold ターゲットからの依存が定義されている
- [x] #2 xcodegen generate && xcodebuild build -scheme befold が成功する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. project.yml に BefoldCLI framework target を追加(sources: BefoldCLI, dependencies: BefoldKit + ArgumentParser package)、他フレームワークターゲット(BefoldRenderKit)と同じ書式に揃える。
2. befold target の dependencies に BefoldCLI を追加する。
3. xcodegen generate → xcodebuild build -scheme befold で成功することを確認する。
4. Package.swift には既に定義済みの befold-cli 実行ファイル・befoldCLITests ターゲットが project.yml に無いことを確認し、AC の範囲外(xcodebuild -scheme befold のビルド成功)であれば別スコープとしてユーザーに確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
befold-cli 実行ファイルターゲットも project.yml に追加(BUILD SUCCEEDED 確認済み)。befoldCLITests は tool ターゲットを TEST_HOST とする xcodebuild test が undefined symbol でリンク失敗する(Xcode のネイティブテストホスト機構が command line tool を正式サポートしないため)ことを確認し、Xcode プロジェクトへの追加は見送った。CLI のテストは既存通り swift test(SPM)で実行する(swift test --filter BefoldCLICommandTests: 25 tests passed)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
project.yml に BefoldCLI framework target(BefoldKit + ArgumentParser 依存)と befold target からの依存を追加。合わせて Package.swift には既にあった befold-cli 実行ファイルターゲットも project.yml に追加した(befoldCLITests は Xcode ネイティブの TEST_HOST 機構が command line tool をサポートせずリンクエラーになるため見送り、CLI テストは既存の swift test 経路を継続)。検証: xcodegen generate → xcodebuild build -scheme befold(BUILD SUCCEEDED)、xcodebuild build -scheme befold-cli(BUILD SUCCEEDED)、swift build(成功)、swift test --filter BefoldCLICommandTests(25 tests passed)。
<!-- SECTION:FINAL_SUMMARY:END -->
