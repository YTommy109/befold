---
id: TASK-564.1
title: PDF の描画を WebKit 内蔵プラグインから PDFKit へ移す
status: To Do
assignee: []
created_date: '2026-08-29 00:40'
labels: []
dependencies: []
parent_task_id: TASK-564
priority: high
type: task
ordinal: 815000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を `<iframe>` + blob URL（WebKit 内蔵 PDF プラグイン）で描くのをやめ、`PDFKit` の `PDFView` で描く。TASK-564 配下の 4 機能はすべてこの基盤の上に載るため、これを最初に片付ける。

## 現状（実測 / 2026-08-29 時点）

- 読み込み: `ContentLoader.load(from:fileType:computeHash:)` が Data を **base64 文字列**にし、`ViewerLoadPipeline.load` が `fileType.isBinaryContent` で分岐してこの経路へ流す。上限は `ContentLoader.maxFileSizeBytes`（50MB）。
- 描画: `viewer-src/renderers.ts` の `_renderPdf` が `base64ToBytes`（`viewer-src/encoding.ts`）→ `_createPdfBlobHolder()` の `issue()` で blob URL を作り `<iframe>` の src に入れる。`#diagram-wrap` に `pdf-body` クラス。
- blob の解放: `viewer-src/render.ts` の `render()` 冒頭で `_mmdPdfBlob.release()`。
- CSP: `BefoldKit/Resources/viewer.html` の meta で `frame-src blob:` のみ許可。
- スタイル: `BefoldKit/Resources/style.css` の `.viewer:has(> #diagram-wrap.pdf-body)` ほか。
- `ViewerRenderer` / `ViewerBridge` に PDF 固有の分岐は無い。
- QuickLook 拡張は PDF を扱わない（`FileType.quickLookSupportedExtensions` が `!isBinaryContent` で絞り、`BefoldQuickLook/Info.plist` の `QLSupportedContentTypes` にも `com.adobe.pdf` は無い。`befoldCLITests/QuickLookInfoPlistTests.swift` が担保）。**このタスクの影響範囲外**。

## 論点（実装着手前に `/review-design` で詰める）

- **サーフェス切替の置き場所**: 種別ごとの出し分けは既に「メニュー構築時の分岐」ではなく `ViewerCapabilities` の有効判定に一本化されている（`ViewerCapabilitiesFactory` → `ViewerMenuValidator` / `ViewerToolbarController+State` / `WebViewCommandController`）。PDF サーフェスの分岐も同じ原則で 1 箇所に閉じる必要がある。`ViewerCapabilities` に真偽値を足すのか、描画サーフェスの抽象を 1 つ導入して zoom / print / scroll のコマンドが委譲する形にするのかを決める。ADR 0002 段 2「条件は 1 箇所」を崩さないこと。
- **base64 経路の扱い**: `PDFView` は Data か URL を直接受けられるため、PDF に限れば base64 化（サイズ 1.33 倍）は不要になる。`ContentLoader` のバイナリ経路を PDF と画像で分けるか、共通のまま PDF だけ別に読むかを決める。
- **ファイル監視の再描画**: `FileWatcher → ViewerStore → ViewerRenderer(evaluateJavaScript)` の伝搬が PDF では `PDFView` の差し替えに変わる。再描画時に表示位置を失わないこと（詳細は表示位置の記憶タスク側で扱うが、経路はここで用意する）。
- **印刷**: `capabilities.canPrint` の実体が WKWebView 前提なら PDF 側の印刷経路も要る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF が `PDFView` で描画され、`<iframe>` + blob URL 経路を通らない
- [ ] #2 `viewer-src/renderers.ts` の `_renderPdf` / `_createPdfBlobHolder` / `_mmdPdfBlob`、`render.ts` の `shape === "pdf"` 分岐、`style.css` の `pdf-body` 規則、viewer.html の CSP `frame-src blob:` のうち PDF のためだけに存在するものが撤去されている
- [ ] #3 `viewer-src/zoom.ts` の `_mmdApplyZoom()` にある `pdf-body` 特例が撤去されている
- [ ] #4 PDF サーフェスかどうかの分岐が 1 箇所に閉じており、メニュー・ツールバー・コマンドがそれぞれ独自に種別を見ていない
- [ ] #5 描画方式の選択（PDFKit を採り pdf.js を採らなかった理由、代償として描画面が 2 枚になること）が `docs/adr/` の ADR として記録されている
- [ ] #6 PDF を開く・別種別へ切り替える・PDF へ戻る、を往復してもサーフェスの残留やリークが起きない
- [ ] #7 `swift test` が通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->
