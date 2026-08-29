---
id: TASK-567
title: PDF のページ送りを連続スクロールへ改める
status: In Progress
assignee: []
created_date: '2026-08-29 20:27'
updated_date: '2026-08-29 20:47'
labels: []
dependencies: []
priority: high
ordinal: 824000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF の表示が `.singlePage` + ホイールのページ送り振り替えになっており、スクロールするとページが瞬時に切り替わる。滑らかにスクロールしないため体感が悪い、というユーザー報告があった。

現状は TASK-564.2 で意図して選んだ形で、`PDFSurfaceLayout.configure` の doc コメントに「連続スクロールにすると 2 ページの端が同時に見える位置で止まらないようにする仕掛けを別に作ることになる。`.singlePage` はそもそも 2 ページを同時に描かないので構造で守れる」と理由が残っている。

今回はこの判断を覆し、`.singlePageContinuous` へ改める。「2 ページの端が同時に見えない」という不変条件は、体感の悪さという不利益に見合わないと判断したため（ユーザー判断 / 2026-08-30）。スナップやページ遷移アニメーションのような新しい仕掛けは足さない（不変条件を守るために機構を増やすのは単純化の逆方向）。

影響範囲: `PagingPDFView` のホイール振り替え、`PDFSurfaceLayout.documentFraction` / `restore` の位置換算（ページ番号 + ページ内位置を 0…1 へ畳む形が連続スクロールでも成立するか）、ADR 0009 と `docs/dev/native-app-design.md` の記述。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF が連続スクロールで表示され、ホイール・トラックパッドのスクロールがページ境界で止まらず滑らかに繋がる
- [ ] #2 ホイールをページ送りへ振り替えていた `PagingPDFView.scrollWheel` の分岐が撤去され、ページ送りのための積算・閾値の状態が残っていない
- [ ] #3 `WindowPresentationMemory` による表示位置の記憶・復元が連続スクロールでも往復し、そのことをオフスクリーンのテストが固定している
- [ ] #4 回転・ズーム（⌘+ / ⌘- / ⌘0）が連続スクロールでも従来どおり効き、既存の PDF 関連テストが通る
- [ ] #5 ADR 0009 に `.singlePage` から連続スクロールへ改めた経緯と理由が追記され、`docs/dev/native-app-design.md` の PDF 表示の記述が実装に追随している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー結果（/review-design / 2026-08-30）

### 方針: 位置の表し方を「ページ番号 + ページ内位置」から「文書全体の 1 本のスクロール」へ単純化する

`.singlePageContinuous` では documentView が全ページ分の高さを持つため、
`verticalScrollRoom` は「文書全体の余地」になる。いまの
`documentFraction = (ページ番号 + ページ内位置) / 総ページ数` はページ内位置が
文書全体の割合に化けるため二重計上で歪む。ページ番号を混ぜる形をやめ、
`contentView.bounds.origin.y / verticalScrollRoom` だけで 0…1 を表す。

これは web 面（1 本のスクロールを 0…1 で表す）と**完全に同じ意味**になり、
`inPageFraction` / `scroll(toInPageFraction:)` / `restore` の `go(to:)` と
ページ数の丸めが丸ごと不要になる（機構が減る）。

### 実装手順

1. `PDFSurfaceLayout.configure` を `.singlePageContinuous` にし、doc コメントの
   「構造で守れる」の段落を、改めた理由（体感を優先し不変条件を捨てた）へ書き換える
2. `documentFraction` / `restore` を上記の単純な形へ置き換え、
   `inPageFraction` / `scroll(toInPageFraction:)` を撤去する
3. `PagingPDFView` からページ送りを撤去する（`hasScrollRoom` /
   `accumulatedDelta` / `pageTurnThreshold` / `scrollWheel` の非 Ctrl 分岐）。
   **Ctrl+ホイールと `magnify` のオーバーライドは残る**ので型自体は消せない。
   実態と名前がずれるので `ZoomingPDFView` へ改名する
4. テストを測り直す（下記）
5. ADR 0009 に経緯を追記し、`docs/dev/native-app-design.md` を追随させる

### テストの手当て（項目 7: 測るものと守るものの一致）

- `PDFSurfaceLayoutTests:46` の `.singlePage` 固定を `.singlePageContinuous` へ
  **書き換えるだけにしない**。撤去した振る舞い（hasScrollRoom / ページ送り）の
  テスト（:86 / :98 / :110 / :154）は削除でよいが、それだけだと守るものが減る
- `documentFraction` / `restore` の往復（:204-220）は**連続スクロール前提で
  期待値を測り直す**。特に :217「幅の違う面へ復元」はページ跨ぎの意味が
  変わるので、期待値を実測で決め直す

### 実装前に確かめること（未確認の前提）

- **復元のタイミング**: `PDFPreviewView.updateNSView` は文書差し替えの直後に
  同期で `restore` を呼ぶ。`.singlePage` では 1 ページ分のレイアウトが早く確定して
  いたが、連続スクロールで全ページを積むとレイアウト確定が遅れ、`verticalScrollRoom`
  が 0 のまま復元が**黙って no-op になる**恐れがある。オフスクリーンで実測し、
  必要なら回転と同じくメインキューへ後から積む
- **回転後の再フィット**: `rotate` の `DispatchQueue.main.async` + `forcingRefit` は
  `.singlePage` での実測（scaleFactorForSizeToFit 0.617→0.495 に scaleFactor が
  追従しない）に基づく。連続スクロールでも同じ挙動かを測り直す

### 該当しなかったチェック項目

- 項目 1（判定の真実の源）: むしろ改善。「スクロールの余地の有無」という
  中身の形での判定（`hasScrollRoom`）が撤去されて無くなる
- 項目 4（新しい状態の表示）: ユーザーへ出す状態は増えない
- 項目 6（高頻度経路）: `currentScrollPosition` の呼ばれ方は変わらない
- 項目 8（非同期の世代管理）: 差し替えの世代管理は `contentRevision` のままで変化なし
- 項目 9（粒度・共有範囲）: 記憶の粒度（窓ごと・ファイルごと）は変えない
- 項目 10（行数・責務）: 実測 PDFSurfaceLayout 169 行 / PagingPDFView 69 行。
  どちらも**減る**見込み。プロトコル準拠・注入クロージャ・stored property は増えず、
  `accumulatedDelta` が 1 つ消える
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-30 / コミット 17385683）

- `PDFSurfaceLayout.configure` を `.singlePageContinuous` へ。ページ送りの振り替えを撤去
- 位置は「スクロール量 / 余地」だけで表す形へ единственный化し、`inPageFraction` /
  `scroll(toInPageFraction:)` / ページ数での丸めを撤去（web の面と同じ式）
- `PagingPDFView` → `ZoomingPDFView` へ改名（ページ送りが無くなり名前が実態とずれたため）

### 実測で分かったこと

- 連続スクロールでは `scaleFactorForSizeToFit` が**幅基準**になる（面 400x500 /
  Letter でページ高 517.65pt = 792 × 400/612）。倍率 1.0 の意味が
  「ページ全体が収まる」→「ページの幅が収まる」へ移った。ADR 0009 と
  native-app-design.md に反映済み
- `displaysPageBreaks = false` は試したが撤回。はみ出しの原因ではなく（原因は幅基準
  フィット）、地の暗い背景が消える副作用のほうが大きい
- 文書を外した面は `underPageBackgroundColor` を描かない。テストは地の色を
  明示してから画素を測る形に変えた
- レビューで挙げた「復元がレイアウト未確定で no-op になる懸念」は起きなかった
  （`restore` → `documentFraction` の往復テストが通る）
- オフスクリーンでは**スクロールしても `currentPage` が更新されない**。位置系の
  検証は `documentFraction` で行う形へ変えた

### 検証

- `swift test`: 1786 件すべて通過（exit=0）
- swiftlint: HEAD ベースラインと差分ゼロ（54 件で同一）
- markdownlint-cli2: 0 issues

### 残り

- AC #1（実機で滑らかにスクロールすること）はユーザーの目視待ち
<!-- SECTION:NOTES:END -->
