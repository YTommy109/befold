---
id: TASK-70
title: Markdown ローカル画像の base64 埋め込みを render 経路のメインスレッドから外す
status: To Do
assignee: []
created_date: '2026-07-19 05:31'
labels: []
dependencies: []
priority: low
type: task
ordinal: 600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-07-19 の PR #262 コードレビュー時のスレッド独立性調査で特定。MarkdownImageEmbedder.embedLocalImages が render 経路のメインスレッドで同期ディスク読込＋base64 エンコードを行う（BefoldRenderKit/ViewerRenderer+RenderHelpers.swift:145 → BefoldKit/MarkdownImageEmbedder.swift:98-99 の Data(contentsOf:) + base64EncodedString()）。キャッシュにより未変更画像の再読込は回避されるが、初回は大きなローカル画像を含む md で render 途中にメインスレッドを塞ぎ体感遅延となる。改善方向: 画像埋め込みをロードパイプライン側（nonisolated async の ViewerLoadPipeline.load）へ寄せ、render にはエンコード済み content を渡す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ローカル画像の読込・base64 エンコードがメインスレッド外で実行される
- [ ] #2 画像入り Markdown の表示結果（埋め込み・キャッシュ挙動）は従来と同一
- [ ] #3 既存の MarkdownImageEmbedder / パイプライン系テストが通過する
<!-- AC:END -->
