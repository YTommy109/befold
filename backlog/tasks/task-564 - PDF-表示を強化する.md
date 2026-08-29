---
id: TASK-564
title: PDF 表示を強化する
status: In Progress
assignee: []
created_date: '2026-08-29 00:39'
updated_date: '2026-08-29 12:16'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 814000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

現在 PDF は `viewer-src/renderers.ts` の `_renderPdf` が blob URL を `<iframe>` に渡し、WebKit 内蔵の PDF プラグインに丸投げしている。描画・スクロール・ページ送りはすべてプラグイン内部で起き、アプリ側からは中身が一切見えない。

そのため次の 4 つがいずれも実現できていない。

1. 1 ページが画面にフィットした初期表示と、ページ単位のスクロール範囲
2. 表示位置の記憶（他のファイルへ移って戻ったときの復元）
3. 拡大縮小（既存のズームは iframe の width/height を % で伸ばす代用実装。`viewer-src/zoom.ts` の `pdf-body` 特例にコメントで「CSS zoom が効かない」と明記されている）
4. 90 度単位の向き変更

これらは個別の機能不足ではなく「PDF がブラックボックスの iframe である」という単一の根本原因に由来する。したがって描画方式の差し替えを基盤タスクとして先に置き、その上に 4 機能を積む。

## 採用する方式

**PDFKit（`PDFView`）をネイティブに置く。** 要望の 4 つは `PDFView` の標準機能でほぼそのまま得られる（`displayMode = .singlePage` / `autoScales` / `rotate(byDegrees:)` / `go(to:)` / `currentDestination`）。同梱ライブラリが不要で、描画品質と大きい PDF の性能を Apple 側に預けられる。

代償は描画面が WKWebView と 2 枚になること。ただし PDF は既にソース表示・差分・行番号・検索・ジャンプのいずれも持たない最も退化したケースで（`FileType.isBinaryContent` により `canSelectSourceMode` / `canSelectDiffMode` が false）、ズームも既に iframe 特例のハックになっている。外へ出す方が特例が減る見込み。

採らなかった案: pdf.js を viewer.html に同梱する。既存の zoom/scroll/find 基盤にそのまま乗る利点はあるが、1MB 超のバンドル同梱と、レンダリング品質・大きい PDF の性能を自前で抱えることになる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 4 つのサブタスクがすべて完了している
- [ ] #2 PDF の描画方式の選択が ADR として記録されている
- [ ] #3 `viewer-src/zoom.ts` の `pdf-body` 特例と `renderers.ts` の `_renderPdf` / `_createPdfBlobHolder` が撤去されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## サブタスク 5 件の実装が完了（2026-08-29）

564.1（PDFKit へ移行）/ 564.2（1 ページフィット + ページ単位スクロール）/
564.3（表示位置の記憶）/ 564.4（ズームの合流）/ 564.5（90 度回転）をすべて実装し、
それぞれ Done にした。設計判断は ADR 0009 と各タスクの Implementation Notes、
現在仕様は `docs/dev/native-app-design.md` に反映済み。

自動検証はすべて緑（`swift test` 1772 件 / jest 621 件 / site 431 件 /
swiftlint の main とのベースライン差分ゼロ / 型グループの行数上限内 /
markdownlint・doc-symbols・doc-citations）。

## 親タスクを Done にする前に、ユーザーの目視確認が要る

このセッションでは画面のキャプチャもメニューのダンプも取れなかった
（`screencapture` が "could not create image from display"、`/menu-audit` の
osascript が assistive access 不許可）。GUI 層はもともと自動テストの対象外
（`.claude/CLAUDE.md` テスト規約）なので、次の項目だけは実機で見る必要がある。

1. PDF を開くと 1 ページ目の全体が収まって表示される（564.2 AC #1）
2. ホイールでページが 1 枚ずつ送られ、2 ページの端が同時に見える位置で止まらない
   （564.2 AC #2）。1 回のフリックで何ページも飛ばないか
3. PDF → 別種別 → PDF と往復してサーフェスの残留が無い（**564.1 AC #6 は未チェックのまま**）
4. ⌘+ / ⌘- / ⌘0 / ピンチ / Ctrl+ホイールでの拡大縮小と、拡大時に文字が粗くならないこと
5. ⌘R / ⇧⌘R で回転し、回転後もフィットが保たれること。PDF 以外ではこの 2 項目が
   メニューで無効になっていること（564.5 AC #4 の実測）
6. 破損した PDF（`.tmp/broken.pdf` に用意してある）で非対応バナーが出ること

`.tmp/sample.pdf`（3 ページ）と `.tmp/broken.pdf` を置いてある。
アプリは `BefoldApp/.build/xcode/Build/Products/Debug/befold.app` にビルド済み。
<!-- SECTION:NOTES:END -->
