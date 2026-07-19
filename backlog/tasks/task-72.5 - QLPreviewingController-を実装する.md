---
id: TASK-72.5
title: QLPreviewingController を実装する
status: To Do
assignee: []
created_date: '2026-07-19 06:44'
labels: []
dependencies: []
parent_task_id: TASK-72
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
View-based QLPreviewingController を実装し、preparePreviewOfFile(at:completionHandler:) 内で FileType.quickLookSupportedExtensions による対象外拡張子の早期reject、対象拡張子は RendererFeatures.quickLookRestricted を設定した ViewerRenderer.loadOneShot を呼び出し WKWebView をview階層に埋め込む。appex側にはロジックを持たせず配線のみとする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 QuickLook対象拡張子のファイルがFinderのQuickLookでレンダリング/ハイライト表示される
- [ ] #2 対象外拡張子(PDF/画像等)がbefoldのQuickLook Extensionでは処理されない
- [ ] #3 appex側コードがloadOneShot呼び出しと分岐のみで、レンダリングロジックを独自に持たない
<!-- AC:END -->
