---
id: TASK-564.4
title: PDF の拡大縮小を既存のズーム操作に合流させる
status: To Do
assignee: []
created_date: '2026-08-29 00:42'
updated_date: '2026-08-29 00:42'
labels: []
dependencies:
  - TASK-564.1
  - TASK-564.2
parent_task_id: TASK-564
priority: medium
type: feature
ordinal: 818000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を既存のズーム操作（`⌘+` / `⌘-` / `⌘0` / Ctrl+ホイール）で拡大縮小できるようにする。PDF 専用の別操作を新設しない。

## 現状（実測 / 2026-08-29 時点）

ズームは全種別共通の仕組みが既にあり、PDF にも「効いてはいる」が実装が代用品になっている。

- JS: `viewer-src/zoom.ts` の `_createZoomStore()` / `_mmdApplyZoom()` / `_mmdZoomIn` / `_mmdZoomOut` / `_mmdZoomReset` / `_mmdWheelZoom` / `_mmdInitWheelZoom`。
- **PDF 特例**: `_mmdApplyZoom()` は `pdf-body` クラスのとき CSS `zoom` を 1 に固定し、`wrap.style.width/height` を `zoom*100 + "%"` にする。コメントに「iframe 内の PDF プラグイン描画には CSS zoom が効かない」と理由が書かれている。幅が広がることで結果的に拡大に見せているだけで、倍率の意味が他種別と一致していない。
- Swift→JS: `ViewerBridge.zoomInScript` / `zoomOutScript` / `zoomResetScript` / `initialZoomScript(_:)` / `applyZoomScript(_:)`。JS→Swift は `ViewerBridge.zoomChangedMessageName`。適用の投影は `BefoldRenderKit/PageZoomProjector.swift`。
- 永続化: `befold/App/ZoomStore.swift`。UserDefaults キー `"ViewerZoomLevels"`、`PathKeyedDictionary<Double>`、`defaultZoom 1.0` / `minZoom 0.5` / `maxZoom 2.0` / `zoomStep 0.25`。
- コマンド: `WebViewCommandController.changeZoom(_:)` / `zoomIn()` / `zoomOut()` / `resetZoom()`（`capabilities().canZoom` でガード）。
- メニュー: `MainMenuBuilder+ViewMenu.addZoomItems(to:)`（`menu.view.actualSize` ⌘0 / `menu.view.zoomIn` ⌘+ / `menu.view.zoomOut` ⌘-）。有効判定は `ViewerMenuValidator` が `capabilities.canZoom` を返す。

## 論点（実装着手前に `/review-design` で詰める）

- **`⌘0` の意味**: 他種別では「等倍（100%）」。PDF では「1 ページが画面にフィットする倍率」（`PDFView.scaleFactorForSizeToFit`）の方が有用で、TASK-564.2 の初期表示とも一致する。等倍に揃えるのか、PDF だけフィットにするのかを決める。PDF だけ変えるならメニュー項目のラベル（`menu.view.actualSize`）が実態と食い違うため、その扱いも決めること。
- **倍率の範囲**: `ZoomStore` の 0.5〜2.0 という上下限は PDF の実用に足りるか。広げるなら他種別への影響を確認すること。
- **永続化の粒度**: 倍率は既存どおり `ZoomStore` で per-file 永続にするのか、TASK-564.3 の「ウィンドウ内だけの表示状態」に含めるのか。倍率と表示位置で永続の有無が分かれるなら、その理由を記録すること。
- **JS 経路の撤去**: `PDFView` へ移ったあと、PDF の倍率は `ViewerBridge` の zoom スクリプトを通らない。`PageZoomProjector` と `zoomChanged` メッセージの経路が PDF では使われない形になるので、コマンド側がサーフェスへ委譲する構造（TASK-564.1 の論点）と整合させる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF で `⌘+` / `⌘-` / `⌘0` / Ctrl+ホイール（トラックパッドのピンチを含む）が拡大縮小として働く
- [ ] #2 倍率の変化が滑らかで、拡大しても文字が粗くならない（`PDFView` による再ラスタライズが効いている）
- [ ] #3 `⌘0` の意味（等倍かページフィットか）が決められ、メニューのラベルと一致している
- [ ] #4 `viewer-src/zoom.ts` の `pdf-body` 特例が撤去され、JS 側に PDF 用の分岐が残っていない
- [ ] #5 倍率を永続化するかどうかの判断と理由が Implementation Notes に記録されている
<!-- AC:END -->
