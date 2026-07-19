---
id: TASK-72.1
title: WKWebView描画完了検知とappexバンドルリソース解決をプロトタイプ検証する
status: To Do
assignee: []
created_date: '2026-07-19 06:44'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loadOneShot は WKWebView への描画予約までしか行わず、mermaid.js 等の非同期描画完了を通知するコールバックが現状ない。QuickLook のプレビュー表示タイミングを決めるために、ViewerRenderer に描画完了通知(onRenderComplete相当)を追加できるか検証する。また、appex バンドル内で BefoldKit の Bundle.befoldKitResources が正しく解決できるかを実機で確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WKWebView の描画完了(mermaid等の非同期処理完了含む)を検知する仕組みの設計案が明確になっている
- [ ] #2 appex バンドル内で BefoldKit のリソース(viewer.html等)が解決できることを実機で確認している
<!-- AC:END -->
