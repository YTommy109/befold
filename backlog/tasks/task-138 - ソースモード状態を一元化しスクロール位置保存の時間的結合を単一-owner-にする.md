---
id: TASK-138
title: ソースモード状態を一元化しスクロール位置保存の時間的結合を単一 owner にする
status: To Do
assignee: []
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 00:25'
labels:
  - refactor
  - structural
  - app
dependencies: []
priority: medium
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VWC.isSourceMode は store.isSourceMode の純粋なミラーで、モード変更は setSourceMode→applySourceMode→resetSourceMode を流れ各所で perFileState.sourceMode を永続化し、applySourceMode の 4 呼び出し点がそれぞれツールバー fan-out を記憶する。また 遷移前に退出モードのスクロール位置を保存する idiom(webViewCommands.saveCurrentScrollPosition(..., mode: isSourceMode ? .source : .rendered))が performFileSwitch と setSourceMode の 2 箇所で同一表現で複写され、順序ハザードを説明する同趣旨コメントが重複している。save-then-mutate の順序制約が各変更点の暗黙プロトコルになっている。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 save-before-mutate のスクロール保存が単一のエントリ(例: beginTransition(savingScrollFor:) か applySourceMode/performFileSwitch の共有入口)へ集約され、複写が解消している
- [ ] #2 VWC.isSourceMode の重複ミラーが見直され、ソースモード状態の所在が一元化されている(可能なら store.isSourceMode を直接参照)
- [ ] #3 swift build/test・webview-smoke が通り、モード切替・ファイル切替時のスクロール位置復元に回帰がない
<!-- AC:END -->
