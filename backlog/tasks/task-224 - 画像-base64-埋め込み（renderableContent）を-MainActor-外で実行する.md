---
id: TASK-224
title: 画像 base64 埋め込み（renderableContent）を MainActor 外で実行する
status: To Do
assignee: []
created_date: '2026-07-31 09:14'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+RenderHelpers.swift の applyRender/applyAppend が MarkdownImageEmbedder.embedLocalImages（全行の正規表現走査 + キャッシュ未命中時は最大 50MB の readData + base64 化）を @MainActor 上で同期実行している。ウォームは先頭チャンク分のみで、2 チャンク目以降の append・ソース/プレビュー切替・画像変更時はコールドになる。renderableContent は既に nonisolated static なので、加工を Task.detached に逃がし evaluateJavaScript だけ MainActor に戻す。DataURICache は NSLock 保護済みで並行呼び出し可。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 render/append 時の画像埋め込み処理（正規表現走査・画像読み込み・base64 化）が MainActor 外で実行される
- [ ] #2 複数チャンク・ソース切替・画像更新の各経路で埋め込み結果が従来と同等である
<!-- AC:END -->
