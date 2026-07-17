---
id: TASK-49
title: ViewerWebView のタプルと TruncationState 構造体の重複を解消する
status: To Do
assignee: []
created_date: '2026-07-17 05:10'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 4200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
updateContent/applyRender を通る名前付きタプル (isTruncated, lineCount, loadFailed) が同ファイル内の TruncationState 構造体と同じ構造を持ち、5箇所で手動の展開/再パックが必要。TruncationState を直接パラメータ型として使えば解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 updateContent/applyRender のパラメータが TruncationState 型を直接使用する
- [ ] #2 手動の展開/再パック箇所が解消されている
<!-- AC:END -->
