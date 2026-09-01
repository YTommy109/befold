---
id: TASK-572
title: 'PDF: 回転を記憶したファイルへ切り替えると倍率が前のファイルの値で上書きされ、静止画も外れる'
status: Done
assignee:
  - '@claude'
created_date: '2026-08-30 03:37'
updated_date: '2026-08-30 03:56'
labels:
  - bug
dependencies: []
priority: high
type: bug
ordinal: 829000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
同一ウィンドウで、回転（90/180/270）を記憶しているファイルへ切り替えると、`PDFPreviewView.updateNSView` が同期で入れた `initialZoom` が、直後の main キューで**前のファイルの倍率**に上書きされる。倍率が変わるので `PDFSurfacePlaceholder` も外れ、TASK-569 で消したはずの白紙が戻る。

## 再現（実測 / 2026-08-30、一時テストで確認・削除済み）

`updateNSView` と同じ順序（`document =` → `PDFSurfaceLayout.apply(rotation:)` → `apply(zoom:)` → `layoutSubtreeIfNeeded()` → `placeholder.install`）を手で再現。前のファイルを倍率 3.0 で見ていた状態から、回転 90 の記憶があるファイルへ `initialZoom = 1.0` で切り替えた。

```text
zoomAfterSync=1.0  showingAfterSync=true      ← 同期区間の終わりでは正しい
zoomAfterAsync=3.0 showingAfterAsync=false    ← DispatchQueue.main.async 後に 3.0 へ上書き、静止画も外れる
```

## 原因（コード参照）

`PDFSurfaceLayout.rotate(byDegrees:in:)` が `let zoom = currentZoom(of:)` を**呼び出し側が `initialZoom` を入れる前に**捕捉し、`DispatchQueue.main.async` で `apply(zoom:)` を再適用する。`updateNSView` の経路では回転の直後に呼び出し側が倍率を入れるので、この再適用は不要なうえ古い値を運ぶ。`apply(zoom:)` は倍率が変わると `placeholder.dismiss()` するため白紙も戻る。

ユーザー操作の経路: 回転したファイル B → 別ファイル A で倍率を変える → B へ戻る（回転記憶は `WindowPresentationMemory` の窓内 per-URL）。

## 単純化の候補（着手時に検討）

`rotate` から非同期の倍率再適用を外し、倍率の維持は既に `ZoomingPDFView.layout()` にある `keepZoomAfterLayout` に一本化できる可能性がある（`largestPageSize` が回転を織り込むので、同期経路では再適用が元々要らない）。ただし `didRotatePage` 後の PDFKit の再レイアウトで `ZoomingPDFView.layout()` が確実に呼ばれるかは未確認。着手時に実測すること。

## 位置づけ

TASK-567（フィット前の倍率で 1 フレーム描かれる）→ TASK-569（白紙）→ 本件と、「差し替え直後の順序」を原因とする同型のバグが 3 件目。個別修正はここで行うが、構造で塞ぐのはリファクタリング側（PDF 面の差し替え手順を 1 オブジェクトへ集約する子タスク）で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 回転記憶のあるファイルへ切り替えた後、main キューを 1 周させても `ZoomingPDFView.zoom` が `initialZoom` のままであることをユニットテストが固定している
- [x] #2 同じテストで、切り替え直後に静止画が載っており、main キューを 1 周させた後も `scaleFactor` が動いていない（静止画が倍率変更で外れることは `PDFSurfacePlaceholderTests` が固定済みなので、倍率が動かないことで静止画の維持を担保する。`isShowing` を時間経過後に直接見ると並列実行で 0.4 秒の保険タイマが先に切れて flaky になる）
- [x] #3 `rotate` の非同期再適用を撤去した場合、回転オーバーレイのボタン経由で回しても倍率 1.0 = フィットの意味が保たれることをテストが固定している
- [x] #4 Implementation Notes に、単純化案（`keepZoomAfterLayout` への一本化）を採ったか否かと、その根拠の実測が記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 前提の実測（2026-08-30）

1. 回転直後に**同期で** `apply(zoom:)` を入れても、PDFKit の遅延再レイアウト（200ms 待ち）後も `layoutSubtreeIfNeeded()` 後も倍率は期待値のまま（0.4899 = (400-12)/792）で、ページは横長で面に収まる。上書きされない
2. 回転後も `ZoomingPDFView.needsLayout` は false のまま。**回転だけでは `layout()` が呼ばれない**ので、「`keepZoomAfterLayout` に任せる」案は不成立
3. `rotate` の doc にある「ここで同期に入れ直すと、まだ古い `scaleFactorForSizeToFit` を読む」は TASK-567 以前の記述。いまの `fitScale` は `largestPageSize`（`page.rotation` を織り込む）から同期に計算するので、この理由は消えている

## 方針

`PDFSurfaceLayout.rotate(byDegrees:in:)` を「ページを回し、面の覚えている `pdfView.zoom` を同期で入れ直す」だけにする。回転前の `currentZoom` の捕捉と `DispatchQueue.main.async` を撤去する。`updateNSView` の経路では続けて呼び出し側が `initialZoom` を同期で入れるので、後から上書きする者が居なくなる。回転オーバーレイの経路では `pdfView.zoom` がユーザーの意図そのもの（`scaleFactor` の書き手は `apply(zoom:)` だけ）なので意味が保たれる。

## 手順（TDD）

1. `PDFSurfaceLayoutTests` の回転スイートに、切替順序（document → apply(rotation:) → apply(zoom: 1.0) → layout → placeholder.install → main キュー 1 周）で倍率が 1.0 のまま・静止画が残ることを固定するテストを足す（赤）
2. 同スイートに、倍率 2.0 で回転しても 2.0 のまま（同期で）であるテストを足す
3. `rotate` を同期化し、doc を書き換える（緑）
4. 既存テストの「再フィットはメインキューへ積まれる」前提（`rotationKeepsTheFittedZoom` の sleep、`PDFSurfaceRenderingTests.settleLayout` の doc）を実態に合わせる
5. `swift test` 全件、`/swiftlint-baseline`、実機で回転オーバーレイと切替の目視
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の判断（2026-08-30）

起票時の単純化案「`rotate` の非同期再適用を外し、倍率の維持を `ZoomingPDFView.layout()` の `keepZoomAfterLayout` に任せる」は**採らなかった**。実測（一時テスト、削除済み）で、ページを回した後 200ms 待っても `ZoomingPDFView.needsLayout` は false のままで、**回転だけでは `layout()` が呼ばれない**ため。

採ったのは「`rotate` が面の覚えている `pdfView.zoom` を**同期で**入れ直す」。根拠は同じ実測で、回転直後に同期で入れた倍率（0.4899 = (400−12)/792）が、PDFKit の遅延再レイアウト（200ms 待ち）後も `layoutSubtreeIfNeeded()` 後も変わらず、ページは横長で面に収まったこと。かつて非同期にしていた理由「同期だと古い `scaleFactorForSizeToFit` を読む」は、`fitScale` を `largestPageSize`（`page.rotation` を織り込む）から同期計算するようになった TASK-567 の時点で消えていた。

捕捉する値を `currentZoom(of:)`（`scaleFactor` からの逆算）ではなく `pdfView.zoom` にしたのは、文書の差し替え途中では `scaleFactor` が前の文書の値を持つため。`scaleFactor` の書き手は `apply(zoom:)` だけ（grep で 1 箇所）なので `zoom` は常に意図と一致する。

## テストで踏んだこと

新テストの「メインキュー 1 周後も `placeholder.isShowing`」は、単独では 3/3 通るが全件並列では 7.7 秒かかって 0.4 秒の保険タイマが先に外し、1 回落ちた。時間依存の断定はやめ、「倍率と `scaleFactor` が動かない」で固定する形にした（倍率が動けば外れることは `PDFSurfacePlaceholderTests.zoomDismissesImage` が担保）。AC #2 も同じ内容に書き換えた。

`DispatchQueue.main.async` は PDF 関連ファイルから消えた（TASK-574.1 の撤去対象のひとつが先に片付いた形）。

## 検証（2026-08-30）

- 修正を戻すと落ちることを実測: `PDFSurfaceLayout.swift` を HEAD の版に戻して `PDFSurfaceRotationTests` を回すと 3 テスト・5 件の期待が落ちる（「回転を記憶したファイルへ切り替えても initialZoom が後から上書きされない」: zoom 2.0 ≠ 1.0・scaleFactor が 0.98 動く／「拡大して見ていても回転後に同じ倍率のまま、同期で決まる」: currentZoom 1.48 ≠ 2.0／「回転してもフィット倍率のままでいる」: sleep を外したので同期版でしか通らない）。修正版では 9/9 通る
- `swift test --skip Integration --skip FileWatcherTests`: 1703 tests / 269 suites すべて通過
- `xcodebuild build -scheme befold`: BUILD SUCCEEDED
- swiftformat: 整形差分なし。swiftlint: main 54 件 → 54 件、真の新規ゼロ・解消ゼロ
- 型グループ検査: `PDFSurfaceLayoutTests` が 420 行（閾値 400）へ超過したため、既に独立した `@Suite` だった `PDFSurfaceRotationTests` を `PDFSurfaceRotationTests.swift` へ切り出した（234 行 + 190 行）。`xcodegen generate` 済み
- `docs/dev/native-app-design.md` の `ZoomingPDFView` 行を更新（「リサイズ・回転のたびに `layout` で入れ直す」→ 回転は `layout` を起こさないので `PDFSurfaceLayout.rotate` が同期で入れ直す）
- 実機での目視（回転オーバーレイ／回転記憶ファイルへの切り替え）は未実施。ユーザー確認に委ねる
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`PDFSurfaceLayout.rotate(byDegrees:in:)` が回転前の倍率を捕捉して `DispatchQueue.main.async` で入れ直していたのをやめ、面の覚えている `pdfView.zoom` を回した直後に**同期で**入れ直す形にした。回転を記憶したファイルへ切り替える経路（`PDFPreviewView.updateNSView`）では、続けて同期で入る `initialZoom` を後から上書きする者が居なくなり、倍率が動かないので静止画も外れない。

起票時の単純化案「`keepZoomAfterLayout` に任せる」は、回転だけでは `ZoomingPDFView.layout()` が呼ばれない（`needsLayout` が false のまま / 実測）ため採らず、同期化を採った。非同期にしていた理由「同期だと古い `scaleFactorForSizeToFit` を読む」は TASK-567 で `fitScale` を自前計算にした時点で消えていた（同期で入れた倍率は 200ms 後も不変 / 実測）。

検証: 新テスト 2 件＋既存 1 件の sleep 撤去。修正を戻すと 3 テスト・5 件の期待が落ち、修正版で 9/9 通る。`swift test` 1703 tests / 269 suites 全通過、`xcodebuild` BUILD SUCCEEDED、swiftlint は main 54 → 54 で真の新規ゼロ。型グループ閾値のため `PDFSurfaceRotationTests` を別ファイルへ切り出し（`xcodegen generate` 済み）。`native-app-design.md` の `ZoomingPDFView` 行を更新。実機目視は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
