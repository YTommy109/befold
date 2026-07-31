---
id: TASK-223
title: HTML 直接ロードの全量同期読み込みをレンダリング経路から外す
status: To Do
assignee: []
created_date: '2026-07-31 09:14'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+ContentUpdate.swift:76-77 が Data(contentsOf:) + HTMLCharsetNormalizer で最大 10MB の HTML を @MainActor 上で全量読み込み・再エンコードしている。updateContent は SwiftUI 更新サイクル（ViewerWebView.updateNSView）から呼ばれ、ファイル切替・ライブリロードのたびに走る。ViewerLoadPipeline が既に non-isolated async で data を読んでいるので、正規化結果を Outcome に載せて渡すのが本筋。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 HTML 表示時の読み込み・charset 正規化が MainActor 外で実行される
- [ ] #2 ファイル切替・ライブリロードでの HTML 表示が従来どおり動作する
<!-- AC:END -->
