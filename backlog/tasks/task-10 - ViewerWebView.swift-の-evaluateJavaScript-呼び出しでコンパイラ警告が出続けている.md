---
id: TASK-10
title: ViewerWebView.swift の evaluateJavaScript 呼び出しでコンパイラ警告が出続けている
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 08:45'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/193
priority: low
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #193 から移行。async コンテキストから evaluateJavaScript(_:completionHandler:) を呼んでいる 3 箇所（ViewerWebView.swift:292-313）で Swift コンパイラが非同期代替関数の使用を提案する警告を毎ビルド出力。意図的な fire-and-forget だがコンパイラは知らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ビルド時にこの警告が出なくなっている
- [x] #2 既存テストで挙動の変化がないことが確認されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 調査: 警告は ViewerWebView.swift の handleLoadMoreLines() 内、Task { @MainActor in ... }(async コンテキスト)から evaluateJavaScript(_:completionHandler: nil) を呼んでいる3箇所(appendChunkScript, truncatedScript, allLinesLoadedScript)でのみ発生。他の evaluateJavaScript 呼び出し(applyRender、ViewerWindowController.swift)は非asyncメソッドから呼ばれておりコンパイラ警告の対象外。
2. 単純化検討: 3箇所とも既にasyncコンテキスト内にあるため、ラッパー関数を新設せずコンパイラの提案通り `try? await webView.evaluateJavaScript(script)` にその場で置き換えるのが最小の変更。befoldTests配下にhandleLoadMoreLines/evaluateJavaScriptへの依存テストは無いことをサブエージェント調査で確認済みのため、挙動変化(JS実行完了を待ってから次チャンク取得に進む、より厳密な直列化)は許容範囲と判断。
3. 実装: 3箇所を completionHandler: nil から try? await 形式に書き換え。
4. 検証: swift build で警告0件になることを確認、swift test --skip Integration --skip FileWatcherTests(323件)が全てpassすることを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証結果:
- swift build (ViewerWebView.swift を touch してキャッシュを無効化した上でクリーンにビルド): evaluateJavaScript関連の警告が0件になったことを確認(修正前は454/456/463行目の3箇所で "consider using asynchronous alternative function" が出ていた)。
- swift test --skip Integration --skip FileWatcherTests: 323件全てpass(修正前と同数、挙動の変化なし)。
- サブエージェント調査により、befoldTests配下にhandleLoadMoreLines/evaluateJavaScriptへ直接依存するテストが存在しないことを確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWebView.swift の handleLoadMoreLines() 内、async コンテキスト(Task { @MainActor in ... })から evaluateJavaScript(_:completionHandler: nil) を呼んでいた3箇所(appendChunkScript/truncatedScript/allLinesLoadedScript)を、コンパイラの提案通り try? await webView.evaluateJavaScript(script) に置き換えた。ラッパー関数などの新規抽象化は追加せず最小限の書き換えに留めた。swift build で警告が0件になったこと、swift test 323件が全てpassし挙動に変化がないことを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
