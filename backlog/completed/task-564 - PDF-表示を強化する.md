---
id: TASK-564
title: PDF 表示を強化する
status: Done
assignee: []
created_date: '2026-08-29 00:39'
updated_date: '2026-08-29 12:29'
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

## 目視の代わりにオフスクリーン描画で検証した（2026-08-29）

「画面を見ないと確かめられない」としていた項目のうち、次は
`NSView.cacheDisplay(in:to:)` によるオフスクリーン描画で**実測に置き換えた**
（画面キャプチャではないので TCC の許可が要らない。`SettingsViewSnapshotTests` と
同じ手）。

| 項目 | 置き換えた検証 |
| --- | --- |
| 開いた直後に 1 ページ全体が収まる | `PDFSurfaceRenderingTests` がページの矩形を面の座標で測る |
| 2 ページの端が同時に見えない | `visiblePages.count == 1` |
| 横長・サイズ混在でも破綻しない | 横長ページで矩形が面に収まることを実測 |
| PDF↔他種別の往復で残留しない | 明るい画素の割合が 30%超 → 1%未満 → 30%超と往復する（564.1 AC #6） |
| 回転後もフィットが保たれる | 回転前後の矩形の縦横比と収まりを実測 |
| 回転メニューが PDF 以外で無効 | 実際のメニュー項目を `ViewerMenuValidator` へ通す |
| 破損 PDF でバナーが出る | `UnsupportedFileView` を描いて、文言が乗ることと他の理由と別の画になることを確認 |

**この検証で 1 件の不具合が見つかり、直した。** 回転後に `autoScales` が効き直さず、
ページが面からはみ出していた（詳細と実測値は TASK-564.5 の Implementation Notes）。
当初の単体テストは倍率の**比**だけを見ていたため見逃していた。

## それでも目視でしか分からない残り

- ホイールでのページ送りの操作感（閾値 20 が適切か、1 回のフリックで 1 ページか）
- ピンチ／Ctrl+ホイールの感度
- 拡大時に文字が粗くならないこと（`PDFView` の再ラスタライズ。構造上は満たされる）

いずれも「動くかどうか」ではなく**効き具合**の話で、値としては上のテストで固定済み。
次にアプリを触ったときに確かめてほしい。
<!-- SECTION:NOTES:END -->
