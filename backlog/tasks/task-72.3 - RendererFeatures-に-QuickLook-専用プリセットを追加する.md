---
id: TASK-72.3
title: RendererFeatures に QuickLook 専用プリセットを追加する
status: To Do
assignee: []
created_date: '2026-07-19 06:44'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
allowDirectHTML/embedImages/allowsInteractiveBridging を全て false にした QuickLook 用の RendererFeatures プリセットを追加し、appex 側の配線を1行にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 RendererFeatures.quickLookRestricted(仮称)が3フラグ全て false である
- [ ] #2 quickLookRestricted 使用時に親ディレクトリreadアクセス・postMessageブリッジが無効化されることをテストで確認している
<!-- AC:END -->
