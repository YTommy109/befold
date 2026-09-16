---
id: TASK-628
title: macOS 27 / Xcode 27 で PDFKit 系テスト 6 件が落ちる
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-09-16 00:46'
updated_date: '2026-09-16 01:44'
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
- [x] #1 6 件が macOS 27 / Xcode 27 で通る
- [ ] #2 CI（Xcode 26.6）でも引き続き通る
- [x] #3 原因が PDFSurfaceLayout の実装かテストの測り方かを実測で切り分け、Notes に記録する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化の検討（実装より先）

- **案 A: 反転を丸ごと撤去して macOS 27 の向き（y は下向きに増える）へ揃える。**
  分岐も述語も増えず最も単純だが、CI の macOS 26 では `isFlipped == false` のままなので
  AC #2 が落ちる。採らない。
- **案 B: 向きを知る述語を 1 つ置き、3 つの式がそれを読む。** 現状は同じ 1 つの事実
  （スクロール座標の向き）が 3 つの式に暗黙のリテラルとして散っている。面に訊く形へ
  畳めば、決め打ちは 1 箇所に減り、状態も経路も増えない。**これを採る。**
  メモリ `degrade-on-facts-not-empty-data` と同じ形（データの形ではなく事実で判定する）。
- **案 C: `verticalScroller.doubleValue`（AppKit が 0=先頭で正規化する）を読む。**
  向きを問わず正しいが、スクローラはヘッドレスや overlay 設定で nil / 非表示になりうる。
  面の `bounds` から離れる分かえって脆い。採らない。

## 手順

1. `PDFSurfaceLayout` に `scrollsDownward(in:)` を足す。クリップビューの
   `isFlipped` を読むだけ。**向きを決め打ちするのはこの 1 箇所だけ**である旨を
   doc に書き、旧 OS / macOS 27 の実測値を両方残す。
2. `documentFraction(of:)` をこの述語で分岐させる。
3. `scrollOffset(forFraction:room:)` を `scrollOffset(forFraction:in:)` へ変える
   （面が要るため）。`room` は中で `verticalScrollRoom` から取る。
   呼び出し元は `ZoomingPDFView.restore(fraction:)` の 1 箇所。
4. `scrollAmount(for:in:)` の符号をこの述語で決める。
5. 既存テスト 6 件が通ることを確認する。
6. **修正を戻すと落ちることを確かめる**（メモリ `verify-tests-fail-without-the-fix`）。
7. `docs/dev/native-app-design.md` に PDF 面の向きの記述があれば追随させる。

## /review-design の結果（実装着手前 / 2026-09-16）

### 実装方針を変えるもの（1 件）

**項目 7「測るものと守るものの一致」— `PDFSurfaceLayoutTests` の
`directionIsCarriedBySignOfTheAmount`（「下へ送ると負、上へ送ると正になる」）は
守りたい保証ではなく OS 依存の符号規約を測っている。**

このテストは macOS 27 でも**通っている**（実測: 今回の失敗 6 件に含まれない）。
`scrollAmount` が決め打ちした符号をそのままアサートしているため、
実アプリでスペースキーが逆方向へ送っていても緑になる。**偽陽性の緑**であり、
手順 5 で 6 件を通すだけでは残る。

差し替える先は、決め打ちを含まない関係そのもの:

```swift
// 先頭の y と末尾の y の差の向きと、「下へ送る量」の符号が一致する。
#expect((bottomY - topY).sign == downwardAmount.sign)
```

`scrollSmoothly(by:)` の式をテスト側で真似ない（それは「テストが真似た式」を
測るだけになる。TASK-574.1 で同じ理由により `present(...)` を直接呼ぶ形へ直した前例）。
`documentFraction` の 0=先頭 / 1=末尾 は `PDFSurfacePositionTests` が固定するので、
この 2 本で「送り量の符号 ↔ y の向き ↔ fraction の向き」が繋がる。

### 該当しない項目

1. **判定の真実の源** — 読むのは `NSClipView.isFlipped`（`bounds.origin.y` の
   意味を決めている当の事実）。データの中身の有無・形では判定していない。
2. **既存の不変条件との衝突** — 不変条件（0=先頭 / 1=末尾）は変えない。
   むしろ OS 差でそれが破れていたのを戻す変更。
3. **消費経路と兄弟判断の全列挙** — `rg` で列挙済み。クリップビューの y を
   読み書きするのは `documentFraction` / `scrollOffset` / `scrollAmount` /
   `restore(fraction:)` / `scrollSmoothly(by:)` の 5 箇所。後ろ 2 つは
   `PDFSurfaceLayout` の値を受けるだけで、`scrollSmoothly` の `[0, maxY]`
   クランプは向きに依らない。`go(toPageAt:)` / `scroll(toFindMatch:)` /
   `PDFFindHighlighter` は PDFKit の `go(to:)` へ委譲するので向きを持たない。
   `PDFPageIndicatorModel` は clipView を同一性比較に使うだけ。
4. **新しい状態に対応する表示** — ユーザーに見える新しい状態は生まれない。
5. **ライフサイクル・順序の変化** — `isFlipped` は `bounds` と同じく呼び出し時に
   読む。常駐化もキャッシュもしないので順序は変わらない。
6. **高頻度経路のコスト** — `documentFraction` はスクロール中に毎フレーム走るが、
   増えるのは `documentView?.enclosingScrollView` のプロパティ連鎖 1 回
   （同じ経路を `verticalScrollRoom` が既に 2 回辿っている）。syscall もループも無い。
8. **非同期で置き換わる表示状態の世代管理** — すべて同期。
9. **決めた粒度・共有範囲を守らせるもの** — 「向きを決め打ちするのは 1 箇所」は
   構造では守れない（誰でも `bounds.origin.y` を読める）。担保はテスト側に置く:
   `fractionPointsFromTopToBottom`（0=先頭 / 1=末尾）と、上で差し替える
   符号一致テストの 2 本。どちらかの向きを決め打ちに戻すと落ちる。
10. **型グループの行数と責務の増分** — `PDFSurfaceLayout` は実測 266 行
    （`scripts/check-type-group-size.sh`）で、述語 1 つ（約 +15 行）を足して約 281 行。
    上限 400 に対して余裕がある。enum の static 関数なので stored property は
    増えず、プロトコル準拠もクロージャ注入も増えない。

## 手順（改訂）

手順 5 の前に次を挿入する。

4.5. `PDFSurfaceLayoutTests.directionIsCarriedBySignOfTheAmount` を、
     符号規約ではなく「`scrollOffset` の向きと符号が一致すること」を測る形へ
     差し替える（余地のある文書 = 複数ページの `makeView` を使う）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 原因（実測 2026-09-16 / macOS 27.0 / Xcode 27.0）

**実装側のバグ。テストの測り方ではない（AC #3）。**

使い捨ての probe テストを `befoldTests` に置いて `swift test --filter` で実測した:

```
PROBE docView.isFlipped   = true
PROBE clipView.isFlipped  = true
PROBE room                = 3196.52
PROBE docView.bounds      = (0, 0, 620, 4008)
```

`PDFSurfaceLayout.scrollOffset(forFraction:room:)` の doc コメントが記録している
旧 OS での実測値は `documentView.isFlipped == false`（「開いた直後 y = 2394.5 =
余地いっぱい、最終ページで y ≈ 0」）。**macOS 27 の PDFKit は documentView を
反転させた**ため、クリップビューの y の意味が上下逆になった。

失敗の形がそれを裏づける。`currentPageAdvancesMonotonicallyWithScroll` の実測値は
`seen = [4, 4, 3, 3, 2, 2, 2, 1, 1, 0, 0]` で、期待値の**完全な逆順**。
`currentPageIndex(of:)` は `pdfView.convert(_:from: page)` でページ矩形を
換算しており向きに依らないため、`restore(fraction:)` が逆の位置へ飛ばしている
ことだけが原因と分かる。

実害はローカルの赤だけではない。**macOS 27 上では実アプリでも PDF の表示位置の
記憶が上下反転し、スペースキーの送り方向も逆になる**（`PDFSurfaceLayout` の
doc コメントがまさにその症状を予告している）。

## 向きを決め打ちしている箇所（3 つ）

- `PDFSurfaceLayout.documentFraction(of:)` — `1 - y / room`
- `PDFSurfaceLayout.scrollOffset(forFraction:room:)` — `room * (1 - fraction)`
- `PDFSurfaceLayout.scrollAmount(for:in:)` — 符号 `backwards ? +magnitude : -magnitude`

`ZoomingPDFView.scrollSmoothly(by:)` の `[0, maxY]` クランプは向きに依らないので
そのままでよい。

## 実装（2026-09-16）

**単純化を先に検討した（CLAUDE.md「調査後・実装前の単純化検討」）。** 反転を丸ごと
撤去する案は CI の macOS 26 が落ちるため採れず、`verticalScroller.doubleValue` に
乗り換える案は面の `bounds` から離れてかえって脆い。採ったのは**向きの事実を
1 箇所へ畳む**案で、状態も経路も増えていない（enum の static 関数が 1 つ増えるだけ）。

- `PDFSurfaceLayout.scrollsDownward(in:)` を新設。`NSClipView.isFlipped` を読む。
  **向きを読むのはここだけ。** 旧 OS / macOS 27 両方の実測値を doc に残した。
- `documentFraction(of:)` / `scrollAmount(for:in:)` をこの述語で分岐。
- `scrollOffset(forFraction:room:)` → `scrollOffset(forFraction:in:)`。
  面から向きを引くため。`room` は中で `verticalScrollRoom` から取る。
  呼び出し元は `ZoomingPDFView.restore(fraction:)` の 1 箇所。
- `ZoomingPDFView.scrollSmoothly(by:)` は変更なし（`[0, 余地]` クランプは向きに依らない）。
  doc の参照先だけ `scrollsDownward(in:)` へ更新。
- `docs/dev/native-app-design.md` の「下へ行くほど y が小さい」という記述を
  「面に訊く」へ更新（旧記述は macOS 27 で誤りになっていた）。

### 設計レビューが拾った偽陽性テストを差し替えた

`PDFSurfaceLayoutTests.directionIsCarriedBySignOfTheAmount` は
`#expect(downward < 0)` と符号規約そのものを測っており、**macOS 27 でも通っていた**
（今回の失敗 6 件に含まれていない）。実アプリでスペースキーが逆へ送っていても
緑になる形。守りたい保証——「下へ送る量は文書の末尾へ向かう」——を測る形へ差し替えた:

```swift
#expect((towardsEnd - towardsTop).sign == downward.sign)
```

`scrollSmoothly(by:)` の式をテスト側で真似ない（TASK-574.1 と同じ理由）。
絶対的な向き（0=先頭）は `PDFSurfacePositionTests.fractionPointsFromTopToBottom` が
固定しているので、2 本合わせて「送り量の符号 ↔ y の向き ↔ 表示位置の向き」が繋がる。

## 検証（実測 / macOS 27.0 / Xcode 27.0 / Swift 6.4）

- `swift test`（全件）: **1990 テスト / 325 スイート + 72 テスト / 14 スイート、いずれも緑**。
  修正前は 1876 テスト中 10 issues。
- **修正を戻すと落ちることを確認した**（メモリ `verify-tests-fail-without-the-fix`）。
  `scrollsDownward(in:)` を `false`（旧 OS の決め打ち）へ戻すと、起票時とまったく同じ
  10 issues / 6 テストが再現した。
- swiftlint: main とのベースライン差分 **0 件**（main 46 件 / HEAD 46 件、
  「真の新規」「解消したもの」ともに空。`/swiftlint-baseline` の手順 4）。
- swiftformat: 差分なし。
- markdownlint-cli2: 0 issues。
- `scripts/check-doc-symbols.sh` / `scripts/check-doc-citations.sh`: 出力なし（合格）。
<!-- SECTION:NOTES:END -->
