---
id: TASK-129
title: 画像埋め込みの共有インスタンス不変条件をテストで再ピン留めする
status: To Do
assignee: []
created_date: '2026-07-24 22:23'
labels:
  - test
dependencies: []
priority: medium
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で確認(CONFIRMED)。befoldTests/ViewerLoadPipelineTests.swift:84 のモック化されたウォームキャッシュテストは、ViewerLoadPipeline.load のウォームアップと ViewerRenderer.renderableContent の描画時埋め込みが同一の embedder インスタンス(.shared)を共有するという本番不変条件をピン留めしなくなった。テストはローカル生成した同一 MarkdownImageEmbedder を両側に渡すため、本番のコールサイト(BefoldKit/ViewerLoadPipeline.swift:43 と BefoldRenderKit/ViewerRenderer+RenderHelpers.swift:174 の独立した「= .shared」デフォルト引数)が別インスタンスに分岐してもテストは緑のまま。
分岐するとウォームアップが無効化され、markdown 描画のたびに全ローカル画像をメインスレッドで再読込・base64 化する(画像の多いドキュメントでビーチボール)。旧テスト(loadWarmsMarkdownImageEmbedCache / DoesNotWarmCache、chmod-0000 画像による実 FS テスト)が捕捉していた回帰。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 本番デフォルト(.shared 共有)が分岐したら fail するテストが存在する
- [ ] #2 テストは実 FS 依存を最小にしつつ不変条件を検証する
<!-- AC:END -->
