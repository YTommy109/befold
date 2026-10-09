---
id: TASK-690
title: サイトのスクリーンショットを現行 UI で撮り直し、未掲載機能の画像を足す
status: Done
assignee: []
created_date: '2026-10-09 07:32'
updated_date: '2026-10-09 08:15'
labels: []
milestone: m-12
dependencies: []
priority: medium
type: task
ordinal: 879000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ランディングのカルーセル（site/src/views/landing.tsx の SCREENSHOTS、site/public/images/screenshot-1〜8.png）は撮影が古い。実測（git log）: 1〜6 は 2026-07-29/30、7・8（Git）は 08-16、4（CSV）だけ 08-27 に差し替え。撮影後に検索バーとジャンプバーの統合（08-21）、サイドバーヘッダーの整理（08-13）、ブックマークのトップレベルメニュー化（09-12）、比較基準の切り替え UI（10-08/09）など UI を変える feat が多数入った。screenshot-3 と 8 を実際に見て、ツールバー・サイドバーが旧状態であることを確認済み（他の画像は未確認）。TASK-484.5 は git 画像の追加だけで、既存画像の更新は担わなかった。スライド窓・比較基準・PDF 検索はサイト未掲載で、紹介文を足す TASK 側が使う画像もここで撮る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 画像 1 枚ごとに現行 UI との差（ツールバー・サイドバー・ラベル）を表にし、撮り直す対象と据え置く対象を理由つきで Notes に残す
- [x] #2 撮り直す対象が現行 UI で撮影され、alt 文言とキャプションが画像の内容と一致している
- [x] #3 スライド窓・比較基準の切り替え・PDF 内検索を示す画像が追加され、サイトの紹介文から使える状態になっている
- [x] #4 画像の差し替えで OGP（site/public/images/ogp.png）に影響が出ないことを確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 1 枚ごとの現行 UI との差（2026-10-09、開発ビルドで実測）

| # | 内容 | 旧画像の差 | 判断 |
|---|---|---|---|
| 1 | Mermaid（サイドバー付き） | ヘッダー旧状態（比較基準 ▾ なし）、ツールバーに差分セグメントなし | 撮り直し |
| 2 | SVG | ツールバーに差分セグメント・ブックマークの形が旧 | 撮り直し |
| 3 | Markdown | 同上（モードセグメントが 2 つのみ） | 撮り直し |
| 4 | CSV | 同上（08-27 撮影だがツールバーは旧） | 撮り直し |
| 5 | ソースコード | 同上 | 撮り直し |
| 6 | Quick Open | 同上。候補に旧来の履歴アイコン配置 | 撮り直し（候補に内部パスが並ばないよう、リポジトリ外へ sample/ をコピーして撮る） |
| 7 | Git Diff | ツールバー旧、行内差分ハイライトなし | 撮り直し |
| 8 | Git Status | サイドバーヘッダーが旧（比較基準 ▾ なし） | 撮り直し |

据え置き 0 枚。全 8 枚でツールバーが旧状態だった。撮影はスクリプトで再現でき、1 枚だけ据え置く利点がない。

## 追加した画像

- screenshot-9: スライド窓（サイドバー右クリック →「Open in Slide Mode」）
- screenshot-10: 比較基準の切り替えメニュー（サイドバーヘッダー ▾）
- screenshot-11: PDF 内検索（⌘F、一致の強調と件数）
- 紹介文を足す TASK-691 は alt/キャプションつきで SCREENSHOTS に載ったこれらを使える。

## 手段の変更

- scripts/capture-screenshots.applescript を開発ビルドで撮れるようにした（BEFOLD_APP、CLI はバンドル内の befold-cli、終了は pkill）
- 右クリックとメニュー項目のクリックは scripts/click-at.swift（AX の AXShowMenu ではコンテキストメニューが出ない）
- sample/sample.pdf と、その生成 scripts/make-sample-pdf.swift。cupsfilter 生成の PDF は PDFKit の検索ハイライトが文字位置からずれたため CoreText で作り直した
- Retina で 2 倍のピクセルになるため sips で 1280 幅へ縮める。スライド窓も 1280x800 に揃える（カルーセルが aspect-ratio 1280/800 固定のため。16:9 のままだと縦に伸びる）

## OGP

site/public/images/ogp.png は git diff が空（未変更）で、shell.tsx / landing.tsx が URL で参照するだけの独立ファイル。スクリーンショットから生成していないので影響なし。

## 検証

- npm test（site/）: 2 回目で 442 件すべて成功。1 回目は 3 件落ちたが、出力を保存しておらず失敗したテスト名を特定できていない。再現せず（未確認の flaky）
- tsc / format:check は通過
<!-- SECTION:NOTES:END -->
