---
id: TASK-577
title: PDF 面のキーボードスクロールを web 面と揃え、Space をページ単位にする
status: Done
assignee: []
created_date: '2026-08-30 11:05'
updated_date: '2026-08-30 11:22'
labels:
  - pdf
dependencies: []
priority: medium
type: feature
ordinal: 839000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF 面のキーボードスクロールが web 面（markdown レンダリング）と揃っていない。

- Space の送り量が可視高 × 0.9（`PDFSurfaceLayout.keyboardScrollOverlap`）で、縦フィットしていてもページ 1 枚ぶんに足りず、押すたびにページの境目がずれていく。ページ区切りのある PDF では読み進める操作にならない
- ↑ ↓ と vi の j / k、Shift 付きの半ページ送りが PDF 面に無く、`super.keyDown`（PDFView 既定）へ落ちている

## 決めたこと（ユーザー承認済み）

**送り量からオーバーラップを外す。** ページ区切りのある PDF ではオーバーラップは無用で、
「いま表示されているものが綺麗にスクロールアウトする」ほうが読み進める操作に合う。
拡大している時も同じ規則で、その時の表示ぶんが送られる。

| キー | 送り量 |
|---|---|
| Space / Shift+Space | 可視高 × 1.0 |
| ↓ / j、↑ / k | 画面上 24pt 相当（`24 / scaleFactor`）。web 面の 1 行（line-height ≈ 24 CSS px）と見た目の移動量が一致する |
| Shift+↓ / Shift+j、Shift+↑ / Shift+k | 可視高 ÷ 2 |

モディファイアは web 面と同じく Shift だけを見る（Option / Ctrl は無視、Cmd は super へ渡してメニューへ）。
← → ・PageUp/PageDown・Home/End・g/G は**追加しない**（web 面に無く、足すと両面がズレるため）。

## 採らなかった案

**ページ先頭へのスナップは入れない。** TASK-567 が「止め方の仕掛け（スナップ・遷移
アニメーション）は足さない」と明示的に決めており、連続スクロールの滑らかさを優先して
その不変条件を捨てた経緯がある。ここで復活させない。

**web 面（`viewer-src/keyboard.ts`）は変更しない。** markdown には物理ページが無いので
0.9 のオーバーラップに意味がある。両面で値が違うことを許容する。

## 既知の残る誤差（実測 / 3 ページ Letter を 400x500 の面・縦フィット・documentView 座標系）

ページ高 792pt、ページ間の余白 ≈ 14.5pt、ページピッチ ≈ 806.5pt に対し、可視高は 811.5pt。
可視高ぶん送るとページピッチより約 5pt 大きいので、Space を押すたびにページ先頭が
5pt ずつ行き過ぎる（10 ページで 50pt ≒ ページ高の 6%）。スナップを入れない以上これは残る。
ユーザー承認済みの許容誤差。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Space / Shift+Space の送り量が可視高そのもの（オーバーラップ無し）になっている
- [x] #2 ↓ / j / ↑ / k が画面上 24pt 相当を送り、倍率を変えても画面上の移動量が変わらない
- [x] #3 Shift+↓ / Shift+j / Shift+↑ / Shift+k が可視高の半分を送る
- [x] #4 キーと送り量の対応が NSEvent を作らずに検証できる純関数として置かれ、その表がテストで固定されている
- [x] #5 keyboardScrollOverlap が削除され、リポジトリ内に参照が残っていない
- [x] #6 既存の PDF 面テストが通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. `PDFSurfaceLayout` に純関数 `keyboardScroll(forKey:shift:)`（キー → 送り量の種類と向き）と
   `scrollAmount(for:in:)`（文書座標の符号つき送り量）を置く。`keyboardScrollOverlap` は削除する。
2. `ZoomingPDFView.keyDown` は Cmd を `super` へ逃がし、解決できたら `scrollSmoothly` へ渡すだけにする。
3. 対応表と送り量をテストで固定する（web 面に無いキーを受けないことも含む）。
4. `ViewerShortcutCatalog` の doc と `docs/dev/native-app-design.md` を追随させる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `PDFSurfaceLayout.KeyboardScroll`（step: page / halfPage / line, backwards）と
  `keyboardScroll(forKey:shift:)` / `scrollAmount(for:in:)` を追加。向きの符号を持つのは
  `scrollAmount` の 1 箇所だけにした。
- `ZoomingPDFView.keyDown` は Cmd を `super` へ逃がして表を引くだけになった。
- `keyboardScrollOverlap` は削除（リポジトリ内に参照なし）。

## 予定外の分割（型グループの閾値超過）

`ZoomingPDFView` グループは**変更前から 400 行ちょうど**で、キー処理を足した時点で 417 行に
なり `scripts/check-type-group-size.sh --check` が落ちた。extension へ割っても合算は減らない
（その逃げ道を塞ぐための仕組み）ので、責務ごと切り出した。

- `PDFMagnificationGesture`（新規 48 行）: 認識器の所有と、累積値 → 増分の帳簿。
  面であることと無関係な唯一の塊。倍率の意味と上下限は `ZoomingPDFView` 側に残した。
- `ZoomingPDFView+Input.swift`: AppKit のオーバーライドとして面に居るしかない
  `magnify` / `scrollWheel` / `keyDown` と、両入口が合流する `applyZoom(scaledBy:)`。
- 分割時に `MagnificationTracker` の `private` を取りこぼしてビルドを 1 往復した
  （CLAUDE.md が警告している型。Swift の `private` はファイルスコープ）。

結果: ZoomingPDFView グループ 382 行（閾値以内）。

## 検証

- `swift test`: 1828 tests / 297 suites 通過
- **テストが空振りしないことを確認**: 送り量に 0.9 を戻し `/ scaleFactor` を外すと
  「Space は可視高ちょうどを送る」「1 行ぶんの送りは倍率によらず画面上 24pt」が落ちる。
  ピンチの配線を切ると「ピンチの認識器が倍率へ繋がっている」が落ちる。
- swiftlint: `origin/main` との raw diff が完全に空
- `scripts/check-type-group-size.sh --check` 通過
- markdownlint / check-doc-citations / check-doc-symbols 通過
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 面のキーボードスクロールを web 面と同じ割り当て（Space・↑↓・j/k・Shift 付き半ページ）にし、送り量からオーバーラップを外して Space が可視高ちょうど＝縦フィット時にページ 1 枚ぶんを送るようにした。キーと送り量の対応は PDFSurfaceLayout の純関数に置き、表をテストで固定。型グループの閾値超過を受けてピンチの受け皿を PDFMagnificationGesture へ切り出した。swift test 1828 件通過、swiftlint の main との差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
