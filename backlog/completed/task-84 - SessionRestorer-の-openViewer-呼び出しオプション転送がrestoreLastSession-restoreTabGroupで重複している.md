---
id: TASK-84
title: >-
  SessionRestorer の openViewer
  呼び出しオプション転送がrestoreLastSession/restoreTabGroupで重複している
status: Done
assignee: []
created_date: '2026-07-21 05:46'
updated_date: '2026-07-21 06:10'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SessionRestorer.swift
priority: low
type: enhancement
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
restoreLastSession() と restoreTabGroup() は共に windowManager.openViewer(for:initialSortOrder:showLineNumbersOverride:sourceModeOverride:) をバイト単位で同一のオプション転送コードで呼んでいる。今回の diff で新たに重複したもので、共通ヘルパーへ切り出されていない。
将来 CLIOpenOptions に新しいオーバーライドフィールドが追加され openViewer に引き渡す際、片方の呼び出し箇所だけ更新して他方を更新し忘れるリスクがある。これは task-73.13/task-77 で修正した『CLI オプションがセッション復元時に無視される』クラスの回帰を再度生みかねない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 restoreLastSession と restoreTabGroup の openViewer 呼び出しが共通ヘルパー/共通コードパスに統合されている
- [x] #2 CLIOpenOptions のオーバーライドフィールドを追加した場合、片方だけ更新して反映漏れが起きない構造になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
restoreLastSession と restoreTabGroup で byte 単位に重複していた windowManager.openViewer(...) 呼び出しを、private func openViewer(for:options:) ヘルパーに抽出し両方から呼ぶ。CLIOpenOptions のオーバーライドフィールドの転送を1箇所に集約することで、フィールド追加時の片側更新漏れを構造的に防ぐ。過剰な抽象化(プロトコル/新規型)は導入しない。既存 SessionRestorerTests で回帰確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
openViewer(for:options:) private ヘルパーを新設し、restoreLastSession のレイアウト外ファイル復元ループと restoreTabGroup の両方をこのヘルパー経由に統合。転送コード(initialSortOrder/showLineNumbersOverride/sourceModeOverride)が1箇所に集約され、AC#1・AC#2 を満たす。swift build 成功。SessionRestorerTests 3件パス。(注: 全体テストで CLIInstanceRouterTests が1件失敗するが、これは別作業による CLIInstanceRouter.swift の同時編集が原因で本タスクとは無関係)

確認依頼を受けて再精査: コミット済み HEAD(67a5ebe)には openViewer ヘルパーは存在せず、restoreLastSession(L110) と restoreTabGroup(L132) に windowManager.openViewer(...) の重複が実在していた。ヘルパー統合済みに見えたのは本タスクで加えた未コミットの作業ツリー変更(git status: M)を指しており、コミット済みコードと取り違えたもの。したがって重複は実在し、本タスクの変更が正しい解決。revert 不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
restoreLastSession/restoreTabGroupで重複していたwindowManager.openViewer(...)呼び出しをprivate openViewer(for:options:)ヘルパーに抽出し両方から呼ぶよう統合。CLIOpenOptionsのオーバーライド転送が1箇所に集約され、フィールド追加時の片側更新漏れを構造的に防ぐ(過剰な抽象化は導入せず)。検証: swift build成功、プロジェクト全543テストgreen(既存SessionRestorerTests含む回帰なし)。
<!-- SECTION:FINAL_SUMMARY:END -->
