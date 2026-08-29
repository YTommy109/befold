---
id: TASK-564.2
title: 1 ページが画面にフィットする初期表示とページ単位のスクロールにする
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-29 00:40'
updated_date: '2026-08-29 11:46'
labels: []
dependencies:
  - TASK-564.1
parent_task_id: TASK-564
priority: medium
type: feature
ordinal: 816000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 目的

PDF を開いたとき、まず 1 ページ全体が画面に収まって見えるようにし、スクロールの単位をページにする。連続スクロールで隣り合うページの端が同時に見える状態にはしない。

## 前提

TASK-564.1 で `PDFView` へ移行済みであること。iframe（WebKit 内蔵 PDF プラグイン）のままではページの概念にアクセスできない。現状のコードにページ数・ページ送り・ページ番号の概念は存在しない（`PDFDocument` / `pageCount` / `currentPage` の識別子は Swift・TS のどちらにも 0 件）。

## 論点（実装着手前に `/review-design` で詰める）

- **`displayMode` の選択**: `.singlePage` はページを 1 枚ずつ差し替えるためスクロール範囲が自然にページ単位になる。`.singlePageContinuous` は連続スクロールなのでページ境界での停止を別途作る必要がある。要望は「スクロール範囲をページ単位」なので `.singlePage` が素直だが、ページ送りの操作感（スクロールで次ページへ送れるか、キー操作のみか）を決める必要がある。
- **フィットの基準**: `autoScales` はビューのサイズに合わせて倍率を追従させる。ウィンドウをリサイズしたときフィットし続けるのか、初回だけフィットして以後はユーザーの倍率を保つのかを決める。拡大縮小タスク（TASK-564.4）の `⌘0` の意味と整合させること。
- **拡大時のページ内スクロール**: フィット時はページ内スクロールが不要だが、拡大するとページ内でスクロールが必要になる。「ページ単位のスクロール範囲」と両立する形を決める。
- **ページ位置の提示**: 現在ページ／総ページ数をユーザーに見せるかどうか。見せる場合の置き場所（ツールバー／統合バー）。スコープに含めるかを判断すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF を開いた直後、1 ページ目の全体が画面内に収まって表示される
- [x] #2 スクロール操作の結果が常にいずれかのページ境界に収まり、2 ページの端が同時に見える中途半端な位置で止まらない
- [x] #3 ウィンドウをリサイズしたときの倍率の振る舞いが決められ、その判断が Implementation Notes に記録されている
- [x] #4 ページが 1 枚だけの PDF、ページごとにサイズが違う PDF、横長ページを含む PDF で表示が破綻しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
実装着手前の /review-design を実施した（チェックリスト 10 項目）。結論を A、
レビューで出た是正を B に置く。

## A. 起票時の論点に対する結論

A1. displayMode → **`.singlePage`**。連続スクロール（`.singlePageContinuous`）だと
    ページ境界での停止を自前で作ることになり、AC #2（2 ページの端が同時に見える
    位置で止まらない）を「止め方」で守る形になる。`.singlePage` は**そもそも
    2 ページを同時に描かない**ので、構造で守れる（`.claude/CLAUDE.md`
    「決めたことには、破れたら落ちるものを付ける」の「破りようのない構造」）。

A2. フィットの基準 → **`autoScales = true` を既定にし、リサイズ中もフィットし続ける。**
    ユーザーが倍率を変えた時点で `autoScales = false` にし、⌘0（`.reset`）で
    `autoScales = true` へ戻す。これで TASK-564.4 の ⌘0 が PDF では
    「フィットへ戻す」の意味になり、WebView 側の「等倍へ戻す」と同じく
    **その面での基準状態へ戻す**という 1 つの意味に揃う。

A3. 拡大時のページ内スクロール → ページ内スクロールは `PDFView` に任せる。
    ページ全体が見えていて**スクロールの余地が無いときだけ**、ホイールを
    ページ送りへ振り替える（下の B2）。拡大中は通常のスクロールが優先される。

A4. ページ位置の提示（現在ページ／総ページ数）→ **このタスクのスコープ外**。
    AC に無く、置き場所（ツールバー／統合バー）を決めると窓側の状態が増える。
    必要になった時点で別タスクとして起票する。

## B. レビューで出た是正

B1. **「倍率 1.0 = ページ全体が収まる状態」の換算を 1 箇所に集める。**
    TASK-564.1 の実装では `PDFPreviewView.updateNSView`（文書差し替え後の初期倍率）と
    `PDFDocumentRenderer.applyZoom`（ユーザー操作）の 2 箇所に
    `scaleFactorForSizeToFit` を基準に掛け直す式が写されている（実測: 同じ 3 行が
    2 ファイルに存在）。チェックリスト項目 3（消費経路と兄弟判断の全列挙）に
    該当する。`PDFSurfaceLayout` を新設して換算と面の設定をそこへ寄せ、
    両者が同じ 1 つの規則を呼ぶ形にする。**この分だけでレイアウトの型を作る
    価値がある**（displayMode の設定も同じ型に入る）。

B2. **ページ送りをホイールへ繋ぐ入口が要る。** `.singlePage` はページを 1 枚ずつ
    差し替えるため、ページ全体が収まっている状態ではスクロールの余地が無く、
    **ホイールを回しても何も起きない**。AC #2 は満たすが「ページ単位のスクロール」
    という要望は満たさない。`PDFView` のサブクラスで `scrollWheel(with:)` を
    受け、スクロールの余地が無いときだけ `goToNextPage` / `goToPreviousPage` へ
    振り替える。慣性（`momentumPhase`）のイベントは無視し、1 回のジェスチャで
    何ページも飛ばさない。

B3. **新しい状態に対応する表示（項目 4）は増えない。** ページが 1 枚だけの PDF
    でも `goToNextPage` は何もしない（`PDFView` が端で止める）。0 ページの PDF は
    `PDFDocument(data:)` が nil を返すため TASK-564.1 の `damagedDocument` で
    既に弾かれている。

B4. **高頻度経路（項目 6）**: `scrollWheel` はホイールのたびに走るが、行うのは
    スクロールビューの寸法比較 1 回だけで、走査もサブプロセスも無い。
    `PDFDocument` の再パースは `contentRevision` が変わったときだけ
    （TASK-564.1 の B6 の抑止をそのまま使う）。

B5. **型グループの行数（項目 10）**: 実測で `PDFDocumentRenderer` 137 行 /
    `PDFPreviewView` 57 行。B1 で換算を `PDFSurfaceLayout`（新設）へ出すため
    両者は減る。stored property は増えない（サブクラスは状態を持たず、
    ホイールの積算だけをローカルに持つ）。

B6. **非同期の世代管理（項目 8）は関係しない。** ページ位置は同期の操作で、
    非同期取得で置き換わる表示状態ではない。TASK-564.3（表示位置の記憶）で
    初めて関係する。

## C. 実装順序

1. `PDFSurfaceLayout` を新設し、`.singlePage` の設定と倍率換算を寄せる（B1）
2. `PDFPreviewView` / `PDFDocumentRenderer` を `PDFSurfaceLayout` 経由へ変える
3. `PagingPDFView`（`PDFView` サブクラス）でホイールをページ送りへ振り替える（B2）
4. 実 `PDFView` + 実 `PDFDocument` の単体テストで固定する。`PDFView()` は窓が
   無くても生成でき、`displayMode` / `autoScales` / `scaleFactor` /
   `currentPage` を実測できる（GUI 層でも「設定が入っているか」は自動テストできる）
5. `swift test` / swiftlint ベースライン差分ゼロ
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-29）

Implementation Plan の C を実施した。

- `PDFSurfaceLayout`（新設）が面の設定（`.singlePage` / `autoScales`）と
  「倍率 1.0 = ページ全体が収まる状態」の換算、ページ内スクロールの余地の測り方を持つ。
  `PDFPreviewView` と `PDFDocumentRenderer` は両方ここを通る（B1）。
- `PagingPDFView`（`PDFView` サブクラス）が、ページ内にスクロールの余地が無いときだけ
  ホイールをページ送りへ振り替える（B2）。慣性イベントは無視し、閾値 20 を超えた分で
  1 ページだけ送る。

### リサイズ時の倍率（AC #3）

**`autoScales = true` を既定にし、リサイズ中もフィットし続ける。** ユーザーが倍率を
変えた時点で `autoScales = false` になり、⌘0（既定倍率）で `true` へ戻る。
これで ⌘0 は「その面での基準状態へ戻す」という 1 つの意味になり、WebView 側の
「等倍へ戻す」と揃う（TASK-564.4 の前提）。

### 実測で分かったこと（設計時に未確認だったもの）

**ページ内スクロールの余地を `scrollView.contentSize` と比べてはならない。**
`PDFView` は倍率をスクロールビューの magnification で表すため、`documentView.bounds` は
倍率のかからないページ座標のまま。実測（400x500 のビュー / Letter 1 ページ / フィット時）
では `documentView` 811pt に対し `contentSize` 500px で、フィット表示なのに 311 の
「余地」があるように見えた。可視領域は clip view の bounds が同じ文書座標で持つ
（フィット時 811 = ページ全体、2 倍時 405.5 = 半分）。この誤りは TASK-564.1 で書いた
`currentScrollPosition` にも入っていたので同時に直した。

### 検証

- `swift test` 1755 件すべて成功。`PDFSurfaceLayoutTests` を新設し、実 `PDFView` +
  実 `PDFDocument`（`CGContext` で生成したページ）に対して displayMode・autoScales・
  倍率換算・ページサイズ混在・1 ページ文書・スクロール余地を実測で固定した
  （`PDFView()` は窓が無くても生成でき、これらの値は測れる）。
- swiftlint の main とのベースライン差分ゼロ（双方 54 件、新規・解消とも空）。

### 目視が必要な残り

ホイールの操作感（1 回のフリックで 1 ページだけ送られるか、閾値 20 が適切か）は
実機の目視でしか確かめられない。表示の破綻が無いこと（AC #1 / #2 / #4）も、
設定値としては上のテストで固定したが**画面としては未確認**。このセッションでは
`screencapture` が使えず（"could not create image from display"）、目視確認ができていない。
<!-- SECTION:NOTES:END -->
