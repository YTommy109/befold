---
id: TASK-576
title: PDF の回転が一瞬で切り替わらず、ページ矩形の補間が見える
status: To Do
assignee: []
created_date: '2026-08-30 09:24'
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
- [ ] #1 回転ボタンを押したとき、ページ矩形の補間（回転前の形状から回転後の形状へ向かう中間フレーム）が 1 フレームを超えて見えない
- [ ] #2 抑止の置き場について /review-design を 1 回通し、その結論（layout() の既存決定を更新するか、別の構造を採るか）をタスクの Implementation Plan に記録している
- [ ] #3 CoreAnimation の内部 observer order のような外部の実装詳細に依存する場合、その依存を doc コメントで明示し、依存が壊れたときに何が起きるか（補間が再び見える）を書いている
- [ ] #4 回転を伴う既存テスト（PDFSurfaceRotationTests / PDFSurfaceLayoutTests）が通り、swiftlint の main とのベースライン差分がゼロである
<!-- AC:END -->
