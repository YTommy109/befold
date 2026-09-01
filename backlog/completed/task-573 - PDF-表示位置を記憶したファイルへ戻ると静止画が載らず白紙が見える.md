---
id: TASK-573
title: 'PDF: 表示位置を記憶したファイルへ戻ると静止画が載らず白紙が見える'
status: Done
assignee:
  - '@claude'
created_date: '2026-08-30 03:37'
updated_date: '2026-08-30 04:30'
labels:
  - bug
dependencies: []
priority: medium
type: bug
ordinal: 830000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PDFPreviewView.installPlaceholder` は `pendingRestoreFraction != nil` のとき静止画を載せない（載せた直後に復元スクロールで絵がずれるため）。そのため、**表示位置を記憶しているファイルへ戻る経路**では TASK-569 の対処が効かず、白紙の区間がそのまま見える。切り替えの中でもっとも多い経路（サイドバーで行き来する）がこれに当たる。

## 裏付け

- コード参照: `PDFPreviewView.installPlaceholder` の guard（`pdfView.pendingRestoreFraction == nil`）、`ZoomingPDFView.applyPendingRestore` が `verticalScrollRoom > 0` でないと値を捨てない点
- **未実測**: 実機で「位置記憶のあるファイルへ戻る」ときの白紙区間は測っていない。TASK-569 の計測一式（`.tmp/t569/sampler.swift` / `compare.sh`）で、位置記憶あり／なしの 2 条件を並べて測ることで確認できる
- 派生の疑い（未確認）: 1 ページで面に収まる文書では余地が 0 のまま `pendingRestoreFraction` が消えず、静止画が永久に載らない可能性がある。`verticalScrollRoom` の実値で確認できる

## 位置づけ

原因は「位置の復元がレイアウト後の別タイミングへ先送りされ、静止画の生成がそれを待てない」順序の問題で、TASK-567 / TASK-569 と同型。個別の対処（復元後に載せ直す等）で症状は消せるが、構造で塞ぐのは PDF 面の差し替え手順を 1 オブジェクトへ集約するリファクタリング側で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 余地が生まれない文書（1 ページで面に収まる等）で `pendingRestoreFraction` が居残らないことをユニットテストが固定している
- [x] #2 居残った復元待ちが後から発火して表示が飛ばないことを、拡大で余地が生まれる経路のユニットテストが固定している
- [x] #3 余地がある文書の復元（同じレイアウトの中で位置まで入る）が壊れていないことを回帰テストが固定している
- [x] #4 面がまだ組み上がっていない間は復元待ちを使い切らないことをテストが固定している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 起票時の前提が崩れた（実測 / 2026-08-30）

「表示位置を記憶しているファイルへ戻る経路では静止画が載らない」は**誤りだった**。`PDFPreviewView.updateNSView` と同じ順序を再現して測ると、**多ページ文書では `layoutSubtreeIfNeeded()` の中で復元待ちが消え、位置も復元され、静止画も載る**（余地 23233、fraction 0.5、`isShowing` true）。

実在したのは**余地が生まれない文書**（1 ページで面に収まる等）だけの問題で、`verticalScrollRoom` が余地 0 を返し続けるため `pendingRestoreFraction` が永久に残っていた（実測: 余地 −9.47、3 回のレイアウト後も 0.0 のまま）。

## 採用した修正

`applyPendingRestore` が待つ条件を「余地があるか」から**「面が組み上がっているか」**（`PDFSurfaceLayout.isLaidOut`）へ変えた。余地 0 には「まだ組み上がっていない（待つべき）」と「文書全体が収まっていて動かせない（待っても変わらない）」の 2 つの意味があり、`verticalScrollRoom` はどちらも 0 を返して区別できない。復元自体は余地 0 なら `restore` が何もしないので、そこで使い切ってよい。

## 本当の症状は白紙ではなく「表示が飛ぶ」

静止画の有無より重い帰結が見つかった。**余地が無い文書を開いた後にユーザーが拡大すると、居残っていた復元待ちがそのレイアウトで発火し、記憶していた位置へ表示が飛ぶ**（実測: 修正前は拡大しただけで fraction 0.0 → 1.0（末尾）へジャンプ。修正後は 0.50 に留まる）。AC はこの帰結を固定する形に書き換えた。

なお静止画そのものは TASK-575 でユーザーの判断により撤去したため、AC から静止画への言及は外した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`ZoomingPDFView.applyPendingRestore` が復元待ちを消す条件を「スクロールの余地があるか」から「面が組み上がっているか」（`PDFSurfaceLayout.isLaidOut`）へ変えた。

起票時の前提は実測で崩れた——多ページ文書では復元も静止画も正しく動いており、実在したのは**余地が生まれない文書**（1 ページで収まる等）だけの居残りだった。そして本当の症状は白紙ではなく、**その後に拡大して余地が生まれた瞬間に居残った待ちが発火し、表示が記憶していた位置へ飛ぶ**ことだった（実測: 修正前 fraction 0.0 → 1.0、修正後 0.50 に留まる）。

検証: ユニットテスト 4 件（居残らない / 拡大で飛ばない / 余地がある文書の復元が壊れていない / 組み上がる前は使い切らない）。修正を戻すと該当テストが落ちることを実測。`swift test` 1699 tests / 268 suites 全通過、`xcodebuild` BUILD SUCCEEDED、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
