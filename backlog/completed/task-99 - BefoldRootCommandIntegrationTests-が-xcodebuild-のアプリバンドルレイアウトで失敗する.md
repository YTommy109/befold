---
id: TASK-99
title: BefoldRootCommandIntegrationTests が xcodebuild のアプリバンドルレイアウトで失敗する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:38'
updated_date: '2026-07-22 14:06'
labels: []
dependencies: []
references:
  - BefoldApp/befoldTests/BefoldRootCommandIntegrationTests.swift
priority: medium
type: bug
ordinal: 88000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ)で検出。builtExecutableURL() は SPM の .build レイアウト(.xctest の隣に befold 実行ファイル)を前提にしているが、XcodeGen 定義の befoldTests ターゲット(xcodebuild test)では実行ファイルは befold.app/Contents/MacOS/befold にあるため両統合テストが失敗する。さらに実行ファイル存在チェックが #require でなく #expect のため、偽の URL のまま進み Process.run() の無関係なエラーで落ちる。また openOptionsAppearInTopLevelHelp は swift-argument-parser の公開 API BefoldRootCommand.helpMessage() で同等の検証がユニットテストとして可能で、サブプロセス起動とバイナリ配置依存を不要にできる(--version テストは ArgumentParser 内部処理のためサブプロセスが正当)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 xcodebuild test でも統合テストが実行ファイルを解決できる(または SPM 限定であることを明示してスキップする)
- [x] #2 実行ファイル解決失敗時は #require 等で明確に失敗する
- [x] #3 help 文言の検証は helpMessage() ベースのユニットテストに置き換えるか、置き換えない理由を記録する
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
builtExecutableURL() を SPM/xcodebuild 両対応に修正し #require で失敗を明示。openOptionsDoNotAppearInTopLevelHelp を helpMessage() ベースのユニットテストに移行（BefoldRootCommandTests へ）。swift test 572 テスト全パス。
<!-- SECTION:FINAL_SUMMARY:END -->
