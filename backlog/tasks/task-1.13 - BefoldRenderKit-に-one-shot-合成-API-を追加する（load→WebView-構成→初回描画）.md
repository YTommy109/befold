---
id: TASK-1.13
title: BefoldRenderKit に one-shot 合成 API を追加する（load→WebView 構成→初回描画）
status: To Do
assignee: []
created_date: '2026-07-19 02:56'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerLoadPipeline.Outcome を render 呼び出しへ変換する糊コードが app 層の ViewerStore.apply（befold/Viewer/ViewerStore.swift:256-296）と ViewerWebView（befold/Viewer/ViewerWebView.swift:76-86、contentRevision / TruncationState の組み立て）に分散しており、QuickLook 拡張はこの糊を再発明する必要がある。BefoldRenderKit に one-shot 用の合成 API（ファイル URL → ViewerLoadPipeline.load(oneShotLoad: true) → WebView 構成 → updateContent）を追加し、QL 実装の本体をほぼゼロにする。あわせて ViewerContentView → ViewerWebView の 15 引数バケツリレー（befold/Viewer/ViewerContentView.swift:34-55）をスナップショット struct 化で整理できる。2026-07-19 のアーキテクチャレビュー（QuickLook 事前レビュー）で特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BefoldRenderKit に、ファイル URL から WebView 構成と初回描画までを 1 呼び出しで行う API がある
- [ ] #2 oneShotLoad: true かつ RendererFeatures でブリッジ無効の構成（QuickLook 想定）で動作する
- [ ] #3 既存アプリの表示経路は挙動不変で、既存テストが通過する
- [ ] #4 新 API の Outcome→描画変換（reject / truncation を含む）にユニットテストがある
<!-- AC:END -->
