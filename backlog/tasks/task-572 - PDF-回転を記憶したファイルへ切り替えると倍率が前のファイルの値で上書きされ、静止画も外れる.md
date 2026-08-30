---
id: TASK-572
title: 'PDF: 回転を記憶したファイルへ切り替えると倍率が前のファイルの値で上書きされ、静止画も外れる'
status: To Do
assignee: []
created_date: '2026-08-30 03:37'
labels:
  - bug
dependencies: []
priority: high
type: bug
ordinal: 829000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同一ウィンドウで、回転（90/180/270）を記憶しているファイルへ切り替えると、`PDFPreviewView.updateNSView` が同期で入れた `initialZoom` が、直後の main キューで**前のファイルの倍率**に上書きされる。倍率が変わるので `PDFSurfacePlaceholder` も外れ、TASK-569 で消したはずの白紙が戻る。

## 再現（実測 / 2026-08-30、一時テストで確認・削除済み）

`updateNSView` と同じ順序（`document =` → `PDFSurfaceLayout.apply(rotation:)` → `apply(zoom:)` → `layoutSubtreeIfNeeded()` → `placeholder.install`）を手で再現。前のファイルを倍率 3.0 で見ていた状態から、回転 90 の記憶があるファイルへ `initialZoom = 1.0` で切り替えた。

```text
zoomAfterSync=1.0  showingAfterSync=true      ← 同期区間の終わりでは正しい
zoomAfterAsync=3.0 showingAfterAsync=false    ← DispatchQueue.main.async 後に 3.0 へ上書き、静止画も外れる
```

## 原因（コード参照）

`PDFSurfaceLayout.rotate(byDegrees:in:)` が `let zoom = currentZoom(of:)` を**呼び出し側が `initialZoom` を入れる前に**捕捉し、`DispatchQueue.main.async` で `apply(zoom:)` を再適用する。`updateNSView` の経路では回転の直後に呼び出し側が倍率を入れるので、この再適用は不要なうえ古い値を運ぶ。`apply(zoom:)` は倍率が変わると `placeholder.dismiss()` するため白紙も戻る。

ユーザー操作の経路: 回転したファイル B → 別ファイル A で倍率を変える → B へ戻る（回転記憶は `WindowPresentationMemory` の窓内 per-URL）。

## 単純化の候補（着手時に検討）

`rotate` から非同期の倍率再適用を外し、倍率の維持は既に `ZoomingPDFView.layout()` にある `keepZoomAfterLayout` に一本化できる可能性がある（`largestPageSize` が回転を織り込むので、同期経路では再適用が元々要らない）。ただし `didRotatePage` 後の PDFKit の再レイアウトで `ZoomingPDFView.layout()` が確実に呼ばれるかは未確認。着手時に実測すること。

## 位置づけ

TASK-567（フィット前の倍率で 1 フレーム描かれる）→ TASK-569（白紙）→ 本件と、「差し替え直後の順序」を原因とする同型のバグが 3 件目。個別修正はここで行うが、構造で塞ぐのはリファクタリング側（PDF 面の差し替え手順を 1 オブジェクトへ集約する子タスク）で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 回転記憶のあるファイルへ切り替えた後、main キューを 1 周させても `ZoomingPDFView.zoom` が `initialZoom` のままであることをユニットテストが固定している
- [ ] #2 同じテストで、main キューを 1 周させた後も `PDFSurfacePlaceholder.isShowing` が true のままである
- [ ] #3 `rotate` の非同期再適用を撤去した場合、回転オーバーレイのボタン経由で回しても倍率 1.0 = フィットの意味が保たれることをテストが固定している
- [ ] #4 Implementation Notes に、単純化案（`keepZoomAfterLayout` への一本化）を採ったか否かと、その根拠の実測が記録されている
<!-- AC:END -->
