---
id: TASK-485.19.4
title: Enter/Shift+Enterの受け口統一とIME結線を整理する
status: To Do
assignee: []
created_date: '2026-08-21 09:12'
labels: []
dependencies:
  - TASK-485.19.2
parent_task_id: TASK-485.19
priority: medium
ordinal: 778000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find は入力欄への keydown、jump は document の keydown（keyboard.ts の
resolveJumpNavigationKey）という構造的に非対称な Enter/Shift+Enter の受け口を、
統合バーの構造に合わせて整理する。

対象:
- find.ts:452-467（入力欄 keydown）
- keyboard.ts:103-114 resolveJumpNavigationKey（document keydown）
- keyboard.ts の ownsEnterKey（リンク上のEnterを奪わない除外ロジック）
- ime.ts の isComposingKeyEvent は検索モードの入力欄に直結させたまま、
  非入力モード（見出し/変更箇所）向けの経路を document keydown に残すか、
  フォーカス設計を変えて入力欄方式に寄せるかを実装時に確定する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 検索/見出し/変更箇所いずれのモードでもEnter/Shift+Enterで前後移動できる
- [ ] #2 IME変換確定のEnterではどのモードでも移動しない（既存テストの型を踏襲）
- [ ] #3 フォーカスがリンク上にあるときEnterを奪わない既存の挙動を壊していない
<!-- AC:END -->
