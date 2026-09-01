---
id: TASK-578.1
title: PDF の現在ページと総ページ数を常時表示する
status: Done
assignee: []
created_date: '2026-08-30 11:57'
updated_date: '2026-08-30 13:43'
labels: []
dependencies: []
parent_task_id: TASK-578
priority: medium
ordinal: 841000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF 表示中、現在表示しているページ番号と総ページ数（例: 12 / 248）を画面上に常に表示する。連続スクロールでは 1 ページが画面をまたぐため、「現在ページ」の定義（表示領域の中心にあるページ等）を先に決めること。

配色の要件はユーザーからの指示: 常時表示になるので、でしゃばらない配色にしつつ読みやすさは保つ。ライト/ダーク両方で確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF 表示中、現在ページ番号と総ページ数が常時表示される
- [x] #2 連続スクロール中にスクロールすると表示中のページ番号が追随して更新される
- [x] #3 回転・ズーム・ファイル切り替えの後も表示が正しい値になる
- [x] #4 常時表示に耐える控えめな配色で、ライト/ダークの両方で読める
- [x] #5 PDF 以外の表示面（web 面）では表示されない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design）の結論

### 現在ページの定義
**「面の中心より上端が上にあるページのうち最後のもの」**（含有判定にしない）。
実測: 500 ページ / fraction 0.5 で `minY <= centre <= maxY` に該当するページは 0 件だった。
ページ間の余白（≈14.5pt / TASK-577 実測）へ中心が落ちると「含むページ」が存在しないため。
順序で決めれば余白でも必ず 1 ページに決まり、境界で往復しない。

### PDFKit の currentPage は使わない
実測: NSWindow に載せてもヘッドレスでは `currentPage` が 0 のまま、`visiblePages` は空、
`.PDFViewPageChanged` は 0 回。テストで守りたい対象を測れない。
幾何（`pdfView.convert(page.bounds(for: .cropBox), from: page)`）はヘッドレスで正しく動き、
fraction 0→1.0 で 1→5 ページと単調に動くことを実測済み。

### 二分探索にする
更新はスクロール中に毎フレーム走る。実測（500 ページ / 1 回）: 全走査 0.3467ms、
二分探索 0.0048ms（72 倍）。ページは上から順に並び view 座標の minY は単調なので二分探索が使える。

### 観測対象は作り直される
`ZoomingPDFView.layout()` の doc のとおりスクロールビューは文書の差し替えで作り直される。
特定の clipView を `object:` に指定して購読すると差し替え後に無音で更新が止まる。
`object: nil` で購読し、発火時に現在の clipView と同一かを見て弾く。

### 縮退は事実で判定する
`total == 0` は「文書が無い」と「まだ面が組み上がっていない」の両方で起きる。
0 のときは表示自体を出さない（`1 / 0` を描かない）。

## 手順
1. `PDFSurfaceLayout` に `pageCount(of:)` と `currentPageIndex(of:)`（二分探索・順序判定）を足す。
2. `@Observable @MainActor` な `PDFPageIndicatorModel` を新設。`PDFViewProxy` 経由でだけ面を読み、
   `NSView.boundsDidChangeNotification`（object: nil + 同一性で絞る）と `.PDFViewDocumentChanged`
   で `current` / `total` を更新する。`ViewerStore` には状態を足さない。
3. `PDFPageIndicator`（SwiftUI）を `.bottomTrailing` に置く。右上の排他ロジックには触らない。
   配色は既存の定型（.regularMaterial + 角丸 8 + .separator 枠 + .caption/.secondary）。
4. `ViewerWindowAssembler` で窓ごとに 1 個作る（`PDFFindModel` と同じ場所・同じ粒度）。
5. テスト: 送り出す値（fraction ごとのページ番号・余白に落ちた場合・回転後・文書差し替え後）を
   `PDFSurfaceLayout` の純粋な換算として固定する。`total == 0` で表示が出ないことも見る。

## 型グループの見積もり
PDFSurfaceLayout 214 → 約 245、DocumentSurfaceStack 177 → 約 190、新設 2 型は別グループ。
ZoomingPDFView（382 / 閾値 400）には足さない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `PDFSurfaceLayout.pageCount(of:)` / `currentPageIndex(of:)` を追加。定義は
  **「面の中心より上端が上にあるページのうち最後のもの」**で、二分探索する。
- `PDFPageIndicatorModel`（@Observable / 窓ごと 1 個 / `DocumentSurfaces` が生成）が
  `NSClipView` の bounds 変更と `.PDFViewDocumentChanged` を購読し、面から読み直す。
- `PDFPageIndicator`（SwiftUI）を PDF 面の左下へ常時表示。右上は回転・検索が排他で使用中。
- `viewer.pdf.pageIndicator` を Localizable.xcstrings へ追加（読み上げ用の文）。

## 設計判断とその実測根拠

- **PDFKit の `currentPage` を使わない**: 窓へ載せてもヘッドレスでは 0 のまま、
  `visiblePages` は空、`.PDFViewPageChanged` は 0 回（実測）。守りたい対象を測れない。
  ページ矩形の換算はヘッドレスで正しく動き、fraction 0→1.0 で 1→5 ページと動く（実測）。
- **含有判定にしない**: 500 ページ / fraction 0.5 で `minY <= centre <= maxY` に該当する
  ページは 0 件だった（ページ間に約 14.5pt の余白があるため）。順序で決める。
- **二分探索**: 500 ページ 1 回あたり全走査 0.3467ms、二分探索 0.0048ms（72 倍）。
- **`object: nil` で購読**: スクロールビューは文書の差し替えで作り直される。
  インスタンスを固定すると差し替え後に無音で更新が止まる。
- **0 のときは表示自体を出さない**: 「文書が無い」と「面がまだ組み上がっていない」の
  両方で 0 になるため、事実で判定して `1 / 0` を描かない。

## 型グループの閾値超過（予定外）

`PDFSurfaceLayoutTests` が 465 行になり閾値 400 を超えたため、現在ページの検証を
`PDFSurfacePageIndexTests` へ分けた（責務としても素直: あちらは倍率とスクロール余地、
こちらはページの索引）。

## 検証

- `swift test`: 1841 tests / 300 suites 通過
- **テストが空振りしないことを毎回確認**:
  - 含有判定へ戻す → 「ページ間の余白へ中心が落ちても…」が落ちる（index → -1）
  - bounds の購読を切る → 「スクロールすると現在ページが追随して更新される」が落ちる
  - `pageCount > 0` のガードを外す → 「総ページ数が 0 なら何も描かない」が落ちる（色数 33）
  - 最初に書いた余白テストは**割合を等分する形で空振りしていた**（5 ページ / 101 分割では
    一度も余白へ落ちず、含有判定のままでも通った）。文書座標で 1pt ずつ舐める形へ直した。
- swiftlint: `origin/main` とのベースライン差分ゼロ
- `scripts/check-type-group-size.sh --check` 通過
- l10n: 216 キーすべて翻訳漏れ・state 異常・プレースホルダ不一致なし
- **実機**: 20 ページの PDF を開き、左下に `1 / 20` が控えめな地で出ることを画面で確認。

## 残る手動確認（AC #4）

ライト外観での見え方は**目視していない**。オフスクリーン描画のテストで「ライト /
ダークのどちらでも地に沈まず描かれる」ことは固定したが、配色の good/bad そのものは
測れない（このリポジトリのテスト規約が GUI 層を手動チェックに置いているのと同じ理由）。
スクロールでの追随も実機では未確認——GUI 自動操作が別アプリの前面ウィンドウを叩いたため
中断した。追随はユニットテスト（購読を切ると落ちる）で担保している。

AC #4 追記: befold を -NSRequiresAquaSystemAppearance YES で起動してライト外観も目視確認した。薄いグレーの文字＋控えめな地で読め、ダークと同様に沈まない。両外観の実機スクリーンショットで確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 面の左下に「現在ページ / 総ページ数」を常時表示するようにした。現在ページは「面の中心より上端が上にあるページのうち最後のもの」と定義し（含有判定だとページ間の余白で該当なしになる／実測）、二分探索で求める（500 ページで全走査 0.35ms に対し 0.005ms）。更新は NSClipView の bounds 変更と PDFViewDocumentChanged の購読で、PDFKit の currentPage は使わない（ヘッドレスで更新されずテストで測れないため／実測）。総ページ数 0 のときは表示自体を出さない。swift test 1841 件通過、各テストが修正なしで落ちることを確認済み、swiftlint の main との差分ゼロ、ライト/ダーク両外観を実機で目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
