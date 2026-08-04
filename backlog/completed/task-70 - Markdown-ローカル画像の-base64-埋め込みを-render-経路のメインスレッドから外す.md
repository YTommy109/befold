---
id: TASK-70
title: Markdown ローカル画像の base64 埋め込みを render 経路のメインスレッドから外す
status: Done
assignee: []
created_date: '2026-07-19 05:31'
updated_date: '2026-07-19 06:10'
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
- [x] #1 ローカル画像の読込・base64 エンコードがメインスレッド外で実行される
- [x] #2 画像入り Markdown の表示結果（埋め込み・キャッシュ挙動）は従来と同一
- [x] #3 既存の MarkdownImageEmbedder / パイプライン系テストが通過する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
メイン側で main worktree に取り込み検証: swift build 成功、swift test 全439件pass(新規テスト2件含む)、swiftlint --strict は該当ファイルで違反0件。render経路(ViewerRenderer+RenderHelpers.swift)は無変更のため task-68 との競合なし。コミット 24d639b で確定。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
render経路は無変更のまま、ViewerLoadPipeline.load(既存のnonisolated async)内でMarkdownImageEmbedderの既存キャッシュを事前ウォームアップする方針で単純化実装。実ディスクI/O(Data(contentsOf:)+base64エンコード)がメインスレッド外で発生することをキャッシュヒット検証テストで実証。swift test 439件全pass、swiftlint違反0件。コミット 24d639b。
<!-- SECTION:FINAL_SUMMARY:END -->
