---
id: TASK-98
title: CLI エラー出力の英語化取りこぼし(check の Reason 日英混在・AppDelegate の日本語 stderr)
status: Done
assignee:
  - '@claude'
created_date: '2026-07-22 13:37'
updated_date: '2026-07-22 13:58'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/CLISubcommandCommand.swift
  - BefoldApp/befold/App/AppDelegate.swift
priority: high
type: bug
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(inselberg-ramada ブランチ)で検出。TASK-94.3 の AC#1「CLI エラーメッセージを英語に統一」に対して 2 箇所の取りこぼしがある。(1) CLISubcommandCommand.swift:63 の check 拒否メッセージが locale 依存の RejectReason.localizedMessage(ja 訳あり)を英語文に埋め込むため、日本語ロケールの配布版では「Cannot open: ...」「Reason: ファイルが大きすぎるため表示できません」という日英混在出力になる。(2) AppDelegate.swift:131 の既存インスタンス転送失敗時 stderr「既存インスタンスへの転送に失敗しました」が日本語のまま残っている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI の check 拒否理由が英語(または一貫した言語方針)で出力される
- [x] #2 AppDelegate の転送失敗 stderr メッセージが英語化されている
- [x] #3 GUI 側の RejectReason ローカライズ表示(TASK-94.3 AC#3)は locale 追従のまま維持される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RejectReason に cliMessage プロパティ(英語固定)を追加する 2. CLICheckCommand で localizedMessage の代わりに cliMessage を使う 3. AppDelegate.swift の日本語 stderr を英語に変更する 4. CLICheckCommandTests の既存テストを cliMessage に合わせて更新する
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RejectReason に英語固定の cliMessage プロパティを追加し、CLICheckCommand が cliMessage を使うよう変更。AppDelegate の日本語 stderr を英語化。GUI 側の localizedMessage はそのまま維持。CLICheckCommandTests を cliMessage に合わせて更新。
<!-- SECTION:FINAL_SUMMARY:END -->
