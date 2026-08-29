---
id: TASK-560
title: LT 用のスライドを sample/presentation に置く
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-27 12:16'
updated_date: '2026-08-27 12:24'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 810000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold 自身で映す前提の LT 資料を `sample/presentation/` に置く（ユーザー依頼、2026-08-27）。1 ページ 1 ファイルの HTML・黒基調・22 ページ。

構成はユーザー指定の 22 ページ（宣伝 → 問題提起 → befold の紹介 → 対応形式 6 種 → QuickLook → CLI → CTA）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 22 ページが 1 ファイルずつ用意され、befold で開いて順に送れる
- [x] #2 外部リソースを読まずに描画できる（Web フォント・CDN なし）
- [x] #3 画像の出どころが README に残っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 作り

- 22 ファイル（`01-intro.html` 〜 `22-thanks.html`）+ `style.css` + `images/` + `README.md`。ファイル名の連番が進行順で、befold のツールバーの ← → で送れる
- 黒基調。方眼グリッド + 2 色のグロー + 四隅の括弧 + 左上の識別子 / 右下のノンブル / 下端の進捗バーで、装飾は下地に寄せて本文を邪魔しない
- 文字サイズは `vmin` + `clamp()` なのでウィンドウの大きさに追随する

## befold で映すうえでの制約（README にも書いた）

- **各ページの先頭に `<meta charset="utf-8">` が必須。** `DirectHTMLModeController` は charset 宣言のある HTML だけを `loadFileURL(_:allowingReadAccessTo:)` で読み、そのときだけ兄弟の `style.css` と `images/` が参照できる。宣言が無いと `loadData` へ倒れて相対リソースが読めず、文字だけのページになる
- 外部読み込みは `RemoteLoadBlocker` が遮断するので Web フォント・CDN は使わない（system-ui と SF Mono / Menlo）

## 画像

- 既存の配布サイト用スクショを流用: `ogp` / `markdown`(screenshot-3) / `code`(screenshot-5) / `diff`(screenshot-7) / `csv`(screenshot-4) / `pdf`(usecase-medical-receipt)
- 新規に撮影: `befold-image.jpg`（befold で写真を開いた画面。macOS 標準壁紙を sips で PNG 化して開いた）、`befold-quicklook.png`（Finder で `sample/flowchart.mmd` を選び Space。"befold QL, version 1.15.0" の透かしが写っており、befold の QL 拡張であることが画像から分かる）
- `appicon.png` は `AppIcon.icns` を sips で書き出したもの。角が四角いままなので CSS 側で `border-radius: 22.4%` を当てている

QuickLook のパネルは AX から列挙できず（`QuickLookUIService` の window が取れない）、qlmanage 経由も window を掴めなかった。**Finder を activate → ファイルを選択 → Space → そのまま screencapture**（間に focus を奪う処理を挟まない）で撮れた。切り出し範囲はいったん広く撮って実測してから `-R875,235,810,638` に決めた。**ユーザーの他ウィンドウが写り込まないよう、パネルだけを切り出している。**

## 検証

- befold で 7 ページ（01 / 02 / 05 / 08 / 18 / 20 / 21）を実際に開いて撮影し、画像を目視確認。CSS・画像とも読めており、グリッド・括弧・ノンブル・進捗バーも出ている
- `markdownlint-cli2`: 0 issues
- サイズは `sample/presentation` 全体で 1.7MB

表紙（01-intro.html）に登壇情報を右下・右寄せで追加した（XP 祭り 2026 / 2026/09/05 / Tommy @ Degino Inc.）。ノンブルの上に積み、そのぶん表紙の画像だけ `max-height` を 58vh → 44vh に落としている（`.shot-intro`）。befold で開いて目視確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
22 ページの LT スライドを sample/presentation に作成した（1 ページ 1 ファイルの HTML、黒基調、共通 style.css）。befold で 7 ページを実際に開いて描画を目視確認。QuickLook と画像表示の 2 枚は新規に撮影した。
<!-- SECTION:FINAL_SUMMARY:END -->
