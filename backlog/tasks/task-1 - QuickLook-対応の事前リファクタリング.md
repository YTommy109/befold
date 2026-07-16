---
id: TASK-1
title: QuickLook 対応の事前リファクタリング
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
labels: []
dependencies: []
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QuickLook 拡張でレンダリングコアを再利用するための事前リファクタリング群。GitHub Issues #209〜#214 から移行。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerWebView のレンダリングコアが BefoldKit に抽出されている
- [ ] #2 ローカライズ文字列が QuickLook 拡張からもアクセスできる
- [ ] #3 viewer.html のブリッジ postMessage がガード付きヘルパーに一本化されている
- [ ] #4 ViewerStore が静的読込パイプラインと監視オーケストレーションに分離されている
- [ ] #5 ViewerWindowController の責務が整理され依存注入されている
- [ ] #6 小さな重複・整合課題が解消されている
<!-- AC:END -->
