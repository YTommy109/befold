---
id: TASK-628
title: macOS 27 / Xcode 27 で PDFKit 系テスト 6 件が落ちる
status: To Do
assignee: []
created_date: '2026-09-16 00:46'
labels:
  - test
dependencies: []
priority: medium
type: bug
ordinal: 825000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ローカル（macOS 27 / Xcode 27.0 / Swift 6.4）で `swift test` を回すと、PDFKit を実際に動かす 3 スイート・6 テストが落ちる。CI（macos-26 / Xcode 26.6）は緑のままで、環境差によるもの。

実測（2026-09-16、TASK-627 の作業中に発見）: 1876 テスト中 10 issues、失敗は次だけ。

- `PDFSurfacePositionTests` 「表示位置は 0 が先頭、1 が末尾を指す」
  — `PDFSurfaceLayout.documentFraction(of:)` が先頭で < 0.01、末尾で > 0.99 にならない
- `PDFSurfacePageIndexTests` 「スクロールに応じて現在ページが単調に進む」
  — seen.first == 0 / seen.last == 4 / 単調性が全て崩れる
- `PDFPageIndicatorModelTests` 「面から総ページ数と現在ページを読む」「スクロールすると現在ページが追随して更新される」「文書を差し替えると新しい文書の値になる」「編集を始めると現在ページが初期値になる」

いずれも実 `PDFView` を作ってスクロールさせ、その結果を測るテスト。macOS 27 の PDFKit がレイアウト・スクロール挙動を変えた可能性が高い。

CI は macos-26（Xcode 26.6 が上限）のままなので緑で、実害は今のところローカルで `swift test` が赤くなることだけ。ただし GitHub が macos-27 を出した時点で CI も落ちる。

着手時の論点: 落ちているのは `PDFSurfaceLayout` の実装か、テストが環境依存の実測値を見ていることか。CLAUDE.md のテスト規約「環境に依存する実測値をアサートしない」に照らすと後者の可能性がある（窓・レイアウト結果ではなく `PDFView` のスクロール座標を測っている）。まず macOS 27 の PDFKit で何が変わったかを実測すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 6 件が macOS 27 / Xcode 27 で通る
- [ ] #2 CI（Xcode 26.6）でも引き続き通る
- [ ] #3 原因が PDFSurfaceLayout の実装かテストの測り方かを実測で切り分け、Notes に記録する
<!-- AC:END -->
