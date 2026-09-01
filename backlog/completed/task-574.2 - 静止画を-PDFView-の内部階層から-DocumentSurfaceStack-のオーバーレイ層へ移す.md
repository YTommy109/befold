---
id: TASK-574.2
title: 静止画を PDFView の内部階層から DocumentSurfaceStack のオーバーレイ層へ移す
status: Done
assignee: []
created_date: '2026-08-30 03:38'
updated_date: '2026-08-30 04:29'
labels:
  - refactor
dependencies:
  - TASK-574.1
parent_task_id: TASK-574
priority: medium
type: task
ordinal: 833000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PDFSurfacePlaceholder` は `NSImageView` を `PDFView` の private なサブビュー階層へ差し込み、PDFKit がレイアウトのたびにサブビューを積み直すため `noteLayout` で毎回 `addSubview(_:positioned:relativeTo:)` し直している（実測: これをしないと 18 回中 2 回静止画が潜って白紙が残った / TASK-569）。フレームワークの内部と取り合う形になっており、外す条件も 3 ファイル 6 箇所に散っている。

`DocumentSurfaceStack` には既に state 駆動のオーバーレイ層（reject / loading / `PDFRotationOverlay`）があるので、静止画も同じ層に置き、「載せる／外す」を面のイベントを直接購読する形から store の state へ移す。

## 期待する効果

- `PDFView` の内部階層に触らないので `noteLayout` の上げ直しが不要になる
- 外す条件（スクロール・倍率・回転・寸法変化・次の差し替え）が state の変更 1 箇所に収斂する
- `showsLoadingIndicator` が `!fileType.rendersFromData` で PDF を除外している点も、PDF にとっての「読み込み中＝静止画を見せている間」として同じ概念に統合できる可能性がある（着手時に検討。無理に統合しない）

## 残留物

`PDFSurfacePlaceholder.draw(_:in:to:)`（`thumbnail(of:for:)` を使う版）は呼び出し元が無い死コードで、生きている `draw(_:rect:box:to:)` と互いに「あちらは使わない」と矛盾する doc を持つ。この移行の中で消す。

## 検証

「白紙が見えない」は自動テストで測れない（GUI 層）。TASK-569 と同じ測り方（`.tmp/t569/sampler`、150 ページ・18 回）で前後を並べる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `PDFView` のサブビューとして `NSImageView` を追加するコードが無く、`noteLayout` による上げ直しが消えている
- [ ] #2 静止画を外す判断が 1 箇所（state の変更）に収斂しており、`placeholder.dismiss()` の直接呼び出しが PDF 関連ファイルに散っていない
- [ ] #3 TASK-569 の測り方（18 回）で 200ms 超の跳ねが 0 回、中央値が対処前（52.3ms）を下回っている
- [ ] #4 `PDFSurfacePlaceholder.draw(_:in:to:)`（thumbnail 版の死コード）が削除されている
- [ ] #5 `/review-design` の結果が Implementation Plan に反映されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
対象だった `PDFSurfacePlaceholder` が TASK-575 で撤去されたため、このタスクは不要になった（実装せずに畳む）。静止画を `PDFView` の内部階層から出す、という問題自体が消えている。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
実装不要。移設対象の `PDFSurfacePlaceholder` が TASK-575 で撤去され、問題が消滅したため畳んだ。
<!-- SECTION:FINAL_SUMMARY:END -->
