---
id: TASK-564.4
title: PDF の拡大縮小を既存のズーム操作に合流させる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-29 00:42'
updated_date: '2026-08-29 12:16'
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
- [x] #1 PDF で `⌘+` / `⌘-` / `⌘0` / Ctrl+ホイール（トラックパッドのピンチを含む）が拡大縮小として働く
- [x] #2 倍率の変化が滑らかで、拡大しても文字が粗くならない（`PDFView` による再ラスタライズが効いている）
- [x] #3 `⌘0` の意味（等倍かページフィットか）が決められ、メニューのラベルと一致している
- [x] #4 `viewer-src/zoom.ts` の `pdf-body` 特例が撤去され、JS 側に PDF 用の分岐が残っていない
- [x] #5 倍率を永続化するかどうかの判断と理由が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-29）

TASK-564.1 / 564.2 で片付いていた分と、このタスクで足した分を分けて記す。

### 先行タスクで済んでいた分

- AC #4（JS 側の `pdf-body` 特例の撤去）は TASK-564.1 で完了。`ViewerBridgeContractTests`
  が「バンドルに `shape === "pdf"` と `pdf-body` が無いこと」を走査で固定している。
- ⌘+ / ⌘- / ⌘0 は `WebViewCommandController` → `DocumentSurfaces.operating(on:)` →
  `PDFDocumentRenderer` を通り、PDF でも既に働く（メニュー側は種別を見ない）。

### このタスクで足した分

- **ピンチと Ctrl+ホイール**（AC #1）。`PDFView` の既定のピンチは `scaleFactor` を
  直接動かすため、そのままだと窓のライブ値・保存値と食い違う。`PagingPDFView` で
  `magnify(with:)` と Ctrl+ホイールを受け、`applyZoom(scaledBy:)` 1 箇所へ収斂させて
  倍率の意味（1.0 = フィット）と上下限（`ZoomStore` と共有）を通す。
- **倍率変化の受け口を 1 箇所に寄せた**。JS 由来の `didChangeZoom` が持っていた
  「一致すればライブ値・常に保存値」の規則を `ViewerWindowController.recordZoomChange`
  へ切り出し、PDF の通知も同じ入口へ入れた。面ごとに規則が分かれると片方だけ直る。

### ⌘0 の意味（AC #3）

**「その面での基準の倍率へ戻す」に統一し、メニューのラベルを
`実際のサイズ` / `Actual Size` から `既定のサイズ` / `Default Size` へ変えた。**
WebView では 100%、PDF ではページ全体が収まる倍率で、どちらも
`ZoomStore.defaultZoom`（1.0）にあたる。ラベルを種別で出し分けなかったのは、
メニュー構築時に種別で分岐しないという既存の原則（ADR 0002 段 2）を崩さないため。
「実際のサイズ」のままだと PDF で実態と食い違う。

### 倍率の永続化（AC #5）

**既存どおり `ZoomStore` の per-file 永続のままにする。** 表示位置（TASK-564.3）は
窓の生存期間だけの記憶にしたので寿命が分かれるが、これは
`WindowPresentationMemory` の doc が既に線を引いている——位置は内容・幅・倍率の
どれが変わっても意味を失う値で、倍率は**内容に依存しないユーザーの意図**。
PDF でもこの区別は変わらない（ページ幅に対する倍率は次に開いたときも同じ意味を持つ）。

### 倍率の範囲

0.5〜2.0 のまま変えない。広げると全種別に効き、他の面での上限の妥当性を測り直す
必要がある。PDF で足りないという実測が出た時点で別タスクにする。

### 検証

- `swift test` 1762 件すべて成功（ピンチの上限・下限での頭打ちと通知を実測で固定）。
- swiftlint の main とのベースライン差分ゼロ。jest 621 件成功。
- AC #2（拡大しても文字が粗くならない）は `PDFView` が倍率変更のたびに再ラスタライズ
  するため構造的に満たされる（CSS zoom で引き伸ばしていた iframe 経路との違い）。
  **目視は未実施**。ピンチの効き具合・Ctrl+ホイールの感度（1 ノッチ = 1%）も実機の
  目視が要る。
<!-- SECTION:NOTES:END -->
