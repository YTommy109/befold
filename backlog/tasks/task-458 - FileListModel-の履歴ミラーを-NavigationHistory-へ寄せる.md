---
id: TASK-458
title: FileListModel の履歴ミラーを NavigationHistory へ寄せる
status: To Do
assignee: []
created_date: '2026-08-12 01:54'
labels:
  - chore
dependencies: []
priority: low
ordinal: 682000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListModel の backHistory / forwardHistory / canGoBack / canGoForward は NavigationHistory が既に持つ知識の二重表現で、SidebarHistoryController.refreshState が毎回写している。写し忘れれば戻る/進むボタンの有効状態だけが古くなる形。

寄せるには View（HistoryButtonView）が @Observable 経由で読んでいる経路を保つ必要があるため、NavigationHistory 側を @Observable にして FileListModel が参照を持つ形にする。TASK-443 では影響範囲が別（App/ 配下の履歴制御）のためスコープ外とした。

出典: TASK-443 で回した responsibility-reviewer の指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FileListModel が履歴の写しを stored property として持たない
- [ ] #2 戻る/進むボタンの有効状態が NavigationHistory の変化で更新される（テストで担保）
- [ ] #3 swift test が既存どおり通る
<!-- AC:END -->
