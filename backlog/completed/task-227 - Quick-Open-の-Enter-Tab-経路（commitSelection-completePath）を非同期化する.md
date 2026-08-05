---
id: TASK-227
title: Quick Open の Enter/Tab 経路（commitSelection / completePath）を非同期化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:14'
updated_date: '2026-07-31 12:52'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 340000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppQuickOpenEnvironment.swift:96-102 の isDirectory / resolveFileToOpen が同期 FS アクセスのまま、QuickOpenModel.commitSelection（Enter、SupportedFileResolver 経由でディレクトリ列挙）と completePath（Tab、stat）から MainActor 上で呼ばれている。同ファイルの candidateSet / directoryEntries は task-205 で Task.detached 済み（「応答しないボリュームでは秒単位で止まる」とコメントあり）で、この 2 つだけ取り残されている。プロトコルの 2 メソッドを async 化し、呼び出し元は QuickOpenView のキーハンドラで Task に吸収する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Enter/Tab 押下時に MainActor 上でディレクトリ列挙・stat が実行されない
- [x] #2 決定・補完の挙動（開くファイルの解決・パス補完結果）が従来と同等である
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. QuickOpenModel.swift: QuickOpenEnvironment プロトコルの isDirectory/resolveFileToOpen を async 化。
2. QuickOpenModel.commitSelection/completePath を async 化(environment 呼び出しに await 追加)。
3. AppQuickOpenEnvironment.swift: isDirectory/resolveFileToOpen の実装を Task.detached でラップし、fileReader へのアクセスを MainActor 外で実行(TASK-205 の candidateSet/directoryEntries と同じパターン)。
4. QuickOpenView.swift: .onSubmit(Enter)/.onKeyPress(.tab) のハンドラを Task { await model.xxx() } でラップ(SwiftUI のキーハンドラ自体は同期のまま)。
5. テスト fake(QuickOpenModelTests.StubEnvironment, QuickOpenPanelControllerTests.StubEnvironment)を async 対応させ、既存の commitSelection/completePath 呼び出し箇所に await を追加。
6. AppQuickOpenEnvironmentTests に ThreadRecordingFileReader を追加し、isDirectory/resolveFileToOpen がメインスレッド外で実行されることを検証するテストを2件追加。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 888件全通過(Integration/FileWatcherTests除く、新規2件のスレッド検証テスト含む)。SwiftLint 実行、変更ファイルに新規エラーなし。TASK-205 の Task.detached パターンを isDirectory/resolveFileToOpen にも適用。QuickOpenView のキーハンドラ(onSubmit/onKeyPress(.tab))はそれ自体は同期のままで、内部で Task { await ... } にラップして解決・補完の完了を待たずに戻る(既存の warm(forFileAt:) と同じ fire-and-forget/非同期起点の形)。決定・補完結果の反映自体は QuickOpenModel の @Observable な状態変更(queryText/onOpen)を通じて行われるため、順序保証は従来と変わらない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppQuickOpenEnvironment.isDirectory/resolveFileToOpen を Task.detached でラップし、SupportedFileResolver によるディレクトリ列挙・stat を MainActor 外で実行するようにした。QuickOpenEnvironment プロトコルとQuickOpenModel.commitSelection/completePath を async 化し、QuickOpenView の Enter/Tab ハンドラは Task { await ... } でラップして呼び出す。テスト fake を async 対応させ、AppQuickOpenEnvironmentTests に isDirectory/resolveFileToOpen のスレッドアフィニティ検証テストを追加。swift test 888件全通過で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
