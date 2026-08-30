---
id: TASK-576
title: PDF の回転が一瞬で切り替わらず、ページ矩形の補間が見える
status: Done
assignee: []
created_date: '2026-08-30 09:24'
updated_date: '2026-08-30 10:08'
labels:
  - pdf
dependencies: []
priority: medium
type: bug
ordinal: 838000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF ビューアで回転ボタンを押すと、切り替わりが一瞬で終わらず、ページの矩形が横方向（縦長 PDF なら縦方向）へ書き変わっていく過程が見える。Mac の Preview.app は同じ操作が一瞬で終わる。

## 原因（実測 / 2026-08-30、1 ページの合成 PDF・実機で確認）

PDFKit が回転時に PDFPageLayer の子レイヤー 5 枚へ position / bounds の CAAnimation を積み、表示サイズを 612x792 から 792x612 へ約 250ms かけて補間している。モデル値（layer.frame）は回転直後に確定していて、presentation() 側だけが遅れて追いつく。この補間が「順次書き変わる」の正体。

計測ログ（presentation layer のサイズ / 回転からの経過）:
+11.3ms 612x792 → +51.2ms 650x754 → +92.5ms 714x690 → +151.2ms 766x638 → +209.8ms 787x617

以下は原因ではないことを実測で確認済み:
- 全ページを回す代入ループ（ZoomingPDFView.rotate）: 200 ページで 0.28ms
- PDFSurfaceLayout.largestPageSize の全ページ走査: 200 ページで 0.05ms
- PDFKit の再レイアウト（documentView の寸法確定）: ページ数に依存せず約 12ms（測定下限）
- ページのラスタライズ: PDFPage.draw は 2 タイル・2.8ms 間隔で完了
- 現象は 1 ページの PDF でも出る（ページ数と無関係）

## 効かなかった対策（実測）

- CATransaction.setDisableActions(true): 効かない（PDFKit は明示アニメーションを add している）
- CATransaction.setAnimationDuration(0): 効かない（PDFKit が duration を明示している）
- rotate(byDegrees:) の末尾で同期に removeAllAnimations: その時点ではまだ積まれていない（removed=0）
- documentView.layer.speed = 1000: 速くはなるが消えない
- DispatchQueue.main.async で 1 周後に剥がす: 1 フレームだけ回転前の形状が出る

## 効いた形（ただしそのまま採用しない）

CFRunLoopObserver（.beforeWaiting / order 1_999_999 = CA のコミット observer の直前）で一度だけ PDFPageLayer 配下の removeAllAnimations を呼ぶと、目視で Preview.app と見分けが付かなくなる（ユーザー確認済み。ログ上は 5 回中 2 回が 1 フレーム目から確定サイズ、3 回が 1 フレームだけ旧形状）。

この形をそのまま入れない理由:
- order 1_999_999 は CoreAnimation 内部の observer order（2_000_000）に依存していて、根拠が外部にある
- 素直な置き場は ZoomingPDFView.layout()（レイアウト段で走るのでコミット前が保証される）だが、そこには「この 2 つ以外の仕事をここへ足さない」という明示の決定（TASK-573 / TASK-574.1）がある。破るなら理由ごと更新する必要があり、黙って足す場所ではない

したがって着手時は /review-design を 1 回通し、抑止をどこへ置くか（layout() の決定を更新するか、別の構造にするか）を決めてから実装する。

計測に使った一時コード（PDFPage サブクラスによる draw ログ、レイヤー木の 120Hz 記録、剥がし処理）はコミットしていない。再現手順は Implementation Notes ではなく本文のこの節に従って組み直すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 回転ボタンを押したとき、ページ矩形の補間（回転前の形状から回転後の形状へ向かう中間フレーム）が 1 フレームを超えて見えない
- [x] #2 抑止の置き場について /review-design を 1 回通し、その結論（layout() の既存決定を更新するか、別の構造を採るか）をタスクの Implementation Plan に記録している
- [x] #3 CoreAnimation の内部 observer order のような外部の実装詳細に依存する場合、その依存を doc コメントで明示し、依存が壊れたときに何が起きるか（補間が再び見える）を書いている
- [x] #4 回転を伴う既存テスト（PDFSurfaceRotationTests / PDFSurfaceLayoutTests）が通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計レビュー（/review-design を 1 回実施）の結論

抑止コードを `layout()` へ置かない（案C 却下 / 明示の決定 TASK-573・574.1 を破る）。
CFRunLoopObserver も第一候補にしない（案B / CoreAnimation 内部 order 2_000_000 への依存が無音で壊れる）。

**採る形（案D）: 補間を剥がすのではなく、補間元を作らない。**
回転は「既存レイヤーの bounds 変更」なので補間が起きる。面にはすでに文書を同期 1 本で
入れ直す `present(document:rotation:zoom:scrollFraction:)` があり、位置は
`PDFSurfaceLayout.documentFraction(of:)` で取れる。`rotate(byDegrees:)` を

  1. 現在の表示位置を取る
  2. 全ページの `page.rotation` を回す（既存ループ）
  3. `present(document:rotation:zoom:scrollFraction:)` を呼ぶ（apply(rotation:) は差分 0 で二重に回らない）

に書き換える。CA・runloop observer・レイヤー木の走査をいずれも持たず、新しい状態も
経路も増えない。順序を持つのは従来どおり `present(...)` だけ。

**未検証の前提**: 同じ PDFDocument の再代入で PDFKit がページレイヤーを作り直し、補間が
消えること。実測で確認する。空振りなら案A（強制レイアウト後に同期で removeAllAnimations）、
それも駄目なら案B（observer + AC #3 の doc コメント）へ落とす。

## 検証手順
- 実機で PDF を開き、回転ボタンを AX 経由でクリック、presentation layer のサイズを
  回転から 300ms 間 NSLog で記録する（起票時と同じ計測）。中間サイズが 1 フレームを
  超えて出ないことを確認する。
- PDFSurfaceRotationTests / PDFSurfaceLayoutTests を通す。位置保存の回帰を見るため
  「回転しても表示位置の割合が保たれる」テストを足す。
- /swiftlint-baseline で差分ゼロを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（案A / 案D は実測で却下）

`ZoomingPDFView.rotate(byDegrees:)` の末尾に `settleRotation()` を足した。
`CATransaction.flush()` で PDFKit の再レイアウトを同期に走らせ、そこで積まれた
`documentView` 配下のレイヤーアニメーションを再帰的に `removeAllAnimations` する。
CFRunLoopObserver も CoreAnimation の内部 order も使っていない。

## 実測（1 ページ 612x792 の合成 PDF を 90 度 / 実機 / presentation layer のサイズ）

- 修正前: +14.0ms 612x792 → +55.0ms 652x752 → +87.5ms 703x701 → +237.5ms 791x613
  （子レイヤー 3 枚に animationKeys 2 件ずつ）
- 修正後: 最初のサンプル +44.7ms の時点で 792x612、以降 400ms まで一定。
  animationKeys は全レイヤーで 0 件。剥がした件数は 10。

## 却下した案D（Implementation Plan の第一候補）を実測で捨てた

同じ `PDFDocument` を `present(...)` で入れ直してもレイヤーは作り直されず、
補間はそのまま出た（修正前とほぼ同じ曲線: +15.7ms 612x792 → +122.2ms 742x662）。
PDFKit はページレイヤーを使い回している。よって「補間元を作らない」は成立しない。

## 回帰テストは窓に入れないと空振りする

`PDFSurfaceRotationTests.rotationLeavesNoLayerAnimations` は、最初 `NSWindow` を
持たない面で書いたため **修正を外しても 0 件で通った**（テスト側で
`CATransaction.flush()` を呼んでも同じ）。面を `NSWindow.contentView` に入れて
初めて PDFKit がアニメーションを積むようになり、修正なしで 20 件を検出して落ちた。

## 検証

- `swift test`: 1822 tests / 297 suites すべて通過
- 修正を外して `rotationLeavesNoLayerAnimations` が落ちることを確認（20 != 0）
- swiftlint ベースライン: `origin/main` との raw diff が完全に空（真の新規 0 件）
- `docs/dev/native-app-design.md` の `ZoomingPDFView` 行へ追随済み
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 回転時に PDFKit がページレイヤーへ積む CAAnimation（約 250ms の矩形補間）を、rotate(byDegrees:) の末尾で CATransaction.flush() → removeAllAnimations により剥がすようにした。実機計測で回転直後のフレームから確定サイズ（792x612）になり中間フレームが出ないことを確認。窓に入れた面での回帰テストが修正なしで 20 件を検出して落ちることも確認済み。swift test 1822 件通過、swiftlint の main との差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
