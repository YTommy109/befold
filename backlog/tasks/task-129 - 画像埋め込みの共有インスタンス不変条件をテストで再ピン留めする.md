---
id: TASK-129
title: 画像埋め込みの共有インスタンス不変条件をテストで再ピン留めする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:23'
updated_date: '2026-07-25 07:12'
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
- [x] #1 本番デフォルト(.shared 共有)が分岐したら fail するテストが存在する
- [x] #2 テストは実 FS 依存を最小にしつつ不変条件を検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 本番デフォルト(引数を渡さない呼び出し)を両側で実行する end-to-end テストを新規追加する
2. 実 FS は TempDir + 8 バイト PNG 1 個のみに抑える(chmod は使わず、ウォームアップ後に画像を削除して再読込不能にする)
3. ViewerLoadPipeline.load(imageEmbedder 未指定) でウォームアップ → 画像削除 → ViewerRenderer.renderableContent(imageEmbedder 未指定) で data URI が返ることを検証する(キャッシュ共有 = 同一インスタンスの証明)
4. 片方のデフォルトを別インスタンスへ変えると fail することを実際に確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
追加: befoldTests/MarkdownImageEmbedderSharedInstanceTests.swift。imageEmbedder を注入せず本番デフォルト(.shared)のまま ViewerLoadPipeline.load でウォームアップ → 画像を chmod 0o000 → ViewerRenderer.renderableContent(既定値)で data URI が返ることを検証する。

設計判断:
- 削除ではなく chmod: MarkdownImageEmbedder.dataURI は fileSize を先に読み、nil なら埋め込み自体を中止するため、削除ではキャッシュ共有の有無を判定できない(実装確認済み)。size/mtime を保ったまま内容だけ読めなくする必要がある。
- root 実行等で chmod が効かないと無意味に緑になるため、埋め込み実行前に #require((try? Data(contentsOf:)) == nil) で読み込み不能を確認する。
- 実 FS 依存は TempDir 1 個 + 8 バイト PNG 1 個のみ(.shared は DefaultFileReader を持つため注入不可)。

ミューテーション検証: ViewerRenderer+RenderHelpers.swift:174 / ViewerLoadPipeline.swift:43 のデフォルトをそれぞれ MarkdownImageEmbedder() に変えると本テストが fail することを個別に確認(いずれも確認後 git checkout で復元)。swift test 全体 644 tests / 92 suites パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
本番デフォルトの .shared 共有をピン留めする MarkdownImageEmbedderSharedInstanceTests を追加。imageEmbedder を注入せずロード側ウォームアップと描画側埋め込みを実行し、chmod 0o000 で内容のみ読めなくした画像が data URI として返るか(=キャッシュ共有)を検証する。2 箇所のデフォルトをそれぞれ別インスタンスへ変えるミューテーションで fail することを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
