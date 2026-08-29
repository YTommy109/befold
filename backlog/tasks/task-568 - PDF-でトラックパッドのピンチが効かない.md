---
id: TASK-568
title: PDF でトラックパッドのピンチが効かない
status: In Progress
assignee: []
created_date: '2026-08-29 20:34'
updated_date: '2026-08-29 20:47'
labels: []
dependencies:
  - TASK-567
priority: high
type: bug
ordinal: 825000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF を開いてトラックパッドでピンチイン/アウトしても**見た目が一切変わらない**（ユーザー報告 / 2026-08-30）。

`PagingPDFView` は `override func magnify(with:)` を持ち `applyZoom(scaledBy:)` へ通しているが、この実装へイベントが届いていない。

実測（オフスクリーン、`PagingPDFView` 400x500 + Letter 1 ページ）:

- ビュー階層は PagingPDFView > PDFScrollView > PDFClipView > PDFDocumentView > PDFPageView
- 中央の hitTest は `PDFPageView` を返す
- `magnifyWithEvent:` を NSView と別 IMP で持つのは `PDFScrollView`（IMP は NSScrollView のものと同一）と `PagingPDFView` のみ。間の 3 つは持たない
- `PDFScrollView.allowsMagnification = true`（min 0.1 / max 100.0 / 現在 magnification 0.6165 = フィット倍率）

つまりピンチは `PagingPDFView` に届く手前の `PDFScrollView` が消費している。オーバーライド自体は生きている（IMP が PDFView のものと異なる）ので、届けば動く。

見た目が変わらない理由は、`PDFSurfaceLayout.configure` が `autoScales = true` のままであるため、スクロールビューが倍率を動かしても PDFView がフィットへ戻していると考えられる（**未確認**: NSEvent にジェスチャを合成する公開 API が無く、実イベントでの観測はできていない）。

対処: 面の設定時に内側のスクロールビューの `allowsMagnification` を false にし、自前の `magnify` オーバーライドへ届かせる。倍率の入口が `applyZoom` へ一本化され、そこで `autoScales = false` が入るため打ち消しも起きない。PDFKit の標準ピンチに任せる案は、この打ち消しが残るため採らない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF でトラックパッドのピンチイン/アウトが効き、拡大縮小が見た目に反映される（実機で確認する）
- [ ] #2 ピンチによる倍率変更が `onZoomChanged` 経由で窓へ伝わり、その後の ⌘0 や ⌘+ がピンチ後の倍率を基準に動く
- [ ] #3 内側のスクロールビューの `allowsMagnification` を false にする設定が `PDFSurfaceLayout` に置かれ、オフスクリーンのテストがその値を固定している
- [ ] #4 ピンチの上下限が `ZoomStore.minZoom` / `maxZoom` に収まる（スクロールビュー既定の 0.1〜100.0 が漏れ出さない）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-30 / コミット 17385683 / TASK-567 と同時）

症状はユーザーの再報告により訂正: 「見た目が一切変わらない」ではなく
**拡大は反応するがフィットへ戻る / 縮小は無視される**。これは当初の読み
（`PDFScrollView` がピンチを消費し、`autoScales` がフィットへ戻す）と一致する。

- `ZoomingPDFView.layout()` で内側のスクロールビューの `allowsMagnification` を
  切る。**`PDFSurfaceLayout.configure` には置かない**——configure は文書を入れる
  前に呼ばれ、そのときスクロールビューがまだ無い（実測: configure だけだと
  true のまま残り、テストが落ちた）。レイアウトのたびに入れ直すのが呼ぶ順番に
  依存しない唯一の形
- `PDFSurfaceLayout.scrollView(in:)` は documentView 経由で取れないとき部分木を
  探す。検証から見たいので internal

### 残り

- AC #1 / #2（実機でピンチが効き、その後の ⌘0・⌘+ が基準を引き継ぐこと）は
  ユーザーの目視待ち
<!-- SECTION:NOTES:END -->
