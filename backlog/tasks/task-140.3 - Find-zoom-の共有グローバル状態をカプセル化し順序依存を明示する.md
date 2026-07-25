---
id: TASK-140.3
title: Find/zoom の共有グローバル状態をカプセル化し順序依存を明示する
status: To Do
assignee: []
created_date: '2026-07-24 22:42'
labels:
  - refactor
  - structural
  - js
dependencies:
  - TASK-140.1
parent_task_id: TASK-140
priority: medium
ordinal: 57000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find 状態が 6 つの裸のモジュールグローバル(_mmdFindOptions/_mmdFindQuery/_mmdFindMatches/_mmdFindCurrentIndex/_mmdFindIsOpenFlag/_mmdIsTruncated)に散り、_mmdFindRun/_mmdFindRefresh/_mmdFindNext/Prev/_mmdFindUpdateCount/_mmdSetTruncated/appendChunk が横断的に読み書きする。_mmdModeJustSwitched や _lastChunkEndedWithNewline が render→appendChunk/setViewMode→refresh を跨ぐ順序依存を持つ。find 状態+操作を FindController 相当(クロージャ/クラス)へ閉じ込め、render/zoom 状態も小さなレコードに集約し、next/prev の循環・refresh の位置維持ロジックを単体テスト可能にする。TASK-140.1 のエクスポート境界導入が前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 find 状態+操作が単一のコントローラ相当に閉じ込められ、裸のモジュールグローバルが解消している
- [ ] #2 next/prev の循環ナビゲーションと refresh の現在位置維持ロジックが単体テストされている
- [ ] #3 順序依存(モード切替直後の refresh・チャンク末尾改行の持ち越し)が明示的な受け渡しになり、find/切替/追記読み込みに回帰がない
<!-- AC:END -->
