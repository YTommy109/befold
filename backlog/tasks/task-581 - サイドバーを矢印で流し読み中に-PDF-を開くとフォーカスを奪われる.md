---
id: TASK-581
title: サイドバーを矢印で流し読み中に PDF を開くとフォーカスを奪われる
status: Done
assignee: []
created_date: '2026-08-31 01:41'
updated_date: '2026-08-31 01:42'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 845000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーでカーソルキーを操作していると、PDF の行に来た時点でフォーカスが PDF 面へ移り、続けて矢印を押しても一覧が動かなくなる（ユーザー報告 / 2026-08-31）。

サイドバーは選択が動いた時点でそのファイルを開く（`FileListView+Keyboard.move(to:)` が `model.selection` の更新に続けて `openIfFile` を呼ぶ。Enter は不要）。そのため矢印で PDF の行へ来ると即座に PDF が開き、そこで面が first responder を取ると次の矢印が一覧へ届かなくなる。

## 原因

`PDFPageIndicatorModel.observe()` が `.PDFViewDocumentChanged` を `object: nil` で購読し、そのハンドラで無条件に `cancel()` を呼んでいた。`cancel()` は `936cb4b2`（TASK-578.2）で `focusSurface()`（`window.makeFirstResponder(pdfView)`）を持つようになったため、**編集していなくても PDF 文書がセットされるたびに面がフォーカスを奪う**。同コミット以前の `cancel()` は `endEditing()` だけで、フォーカスを触っていなかった。

`focusSurface()` は `DispatchQueue.main.async` で 1 周遅らせるので、サイドバー側の `SidebarTableFocuser` が同じターンでフォーカスを取っていても後勝ちで奪う。

## 望む挙動（ユーザーの判断 / 2026-08-31）

PDF を開いてもフォーカスは**サイドバーに残す**。面へ移してよいのはユーザーがページ番号入力を閉じたとき（Enter / Esc）だけ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF 文書がセットされてもフォーカスが移らない（サイドバーを矢印で流し読みし続けられる）
- [x] #2 文書が差し替わったときに編集中のページ番号入力が閉じることは保たれる
- [x] #3 ユーザーが Enter / Esc で入力を閉じたときは従来どおり面へフォーカスが移る
- [x] #4 上記 3 点を、修正を戻すと落ちるテストで固定している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討（実装前）

`cancel()` が「ユーザーの Esc」と「文書が変わったので編集を閉じる」の 2 つの意味を
兼ねていたことが原因なので、**兼務をほどく**のが最小の直し方だった。新しい状態も
分岐も増えない。`observe()` のハンドラを `cancel()` → `endEditing()` に変えるだけ。

フォーカス移動を条件付きにする（`isEditing` を見る等）案は採らなかった。`cancel()` は
`endEditing()` で `isEditing` を false にするので、判定の順序に依存する脆い形になる。

## 変更

- `PDFPageIndicatorModel.observe()`: `.PDFViewDocumentChanged` のハンドラを
  `cancel()` から `endEditing()` へ。理由を doc コメントに残した。
- `PDFPageIndicatorModel.cancel()`: 「ユーザーが入力を閉じたときだけ呼ぶ」ことを
  doc コメントで明示。
- `befoldTests/PDFPageIndicatorFocusTests.swift` を新設（4 件）。

## テストが空振りしないことの確認

修正前に実行して、狙った 2 件が実際に落ちることを確認済み:
`Expectation failed: (window.requestedFirstResponder → <befold.ZoomingPDFView: 0x…>) == nil`
（「PDF を開いてもフォーカスを奪わない」「編集中に文書が差し替わると、編集は閉じるが
フォーカスは動かない」）。残る 2 件（Enter / Esc で面へ移す）は修正前から緑で、
意図した移動を壊していないことの担保。

**待ち方は時間で測らない。** `focusSurface()` は `DispatchQueue.main.async` で 1 周遅れて
走るので、同じ main キューへ後から積んだマーカーを待って判定する（FIFO なので、
マーカーが走った時点で先行ブロックは実行済み）。

## 検証（実測 / 2026-08-31）

- `swift test`: 1852 tests / 301 suites 通過（新規 4 件・1 suite ぶん増）
- swiftlint: `origin/main` とのベースライン差分ゼロ（真の新規 0・解消 0・生 diff も空）
- `xcodegen generate`: 新規ファイル追加のため実行済み
- 初回は `makeSurface` が 3 要素タプルを返して `large_tuple` の新規違反 1 件が出たため、
  `Surface` 構造体へ変えて解消した

## 残した既知の点（今回は触っていない）

`.PDFViewDocumentChanged` の購読は `object: nil`（全 PDFView 対象）のままなので、
ある窓で PDF を開くと**他の窓のインジケータの編集も閉じる**。フォーカスは動かなく
なったので実害は小さいが、窓をまたぐ副作用としては残っている。報告された不具合とは
別件なので、必要なら別タスクにする。

## 未検証

**実機での手動確認はしていない。** GUI 操作の確認は対話セッションでしか回せない
（背景ジョブは TCC 不許可）。サイドバーを ↓ で流し読みして PDF の行を通過したあと、
続けて ↓ が一覧に効くかをユーザーに確認してほしい。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーを矢印で流し読み中に PDF の行へ来ると面がフォーカスを奪い、次の矢印が一覧に効かなくなる回帰を直した。原因は `PDFPageIndicatorModel.observe()` の `.PDFViewDocumentChanged` ハンドラが無条件に `cancel()` を呼んでおり、その `cancel()` が 936cb4b2（TASK-578.2）以降 `focusSurface()` を持つようになっていたこと。通知側は `endEditing()` だけを呼ぶ形にして、「ユーザーの Esc」と「文書差し替えで閉じる」の兼務をほどいた。回帰テスト 4 件を新設し、修正を戻すと 2 件が落ちることを実測で確認。swift test 1852 件通過、swiftlint の main との差分ゼロ。実機での手動確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
