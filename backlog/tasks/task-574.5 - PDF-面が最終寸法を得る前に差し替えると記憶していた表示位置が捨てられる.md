---
id: TASK-574.5
title: PDF 面が最終寸法を得る前に差し替えると記憶していた表示位置が捨てられる
status: To Do
assignee: []
created_date: '2026-08-30 04:46'
labels:
  - bug
dependencies: []
parent_task_id: TASK-574
priority: low
ordinal: 837000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PDFSurfaceLayout.isLaidOut` は **frame が 0 の面でも true を返す**（実測: `isLaidOut=true` / 余地 24045.0）。この状態で位置を復元すると成功したように見えるが、**本物の frame が付いた瞬間に位置が 0 へ戻る**（実測: 復元直後 0.5 → frame 付与後 1.06e-06 / TASK-574.1 の一時テスト、削除済み）。

`isLaidOut` が答えているのは「スクロールビューまで組み上がったか」であって「最終的な寸法で組み上がったか」ではない。この 2 つは別の問いで、後者を判定する術がまだ無い。

**既存の穴であり TASK-574.1 の退行ではない。** センチネル方式（`pendingRestoreFraction`）でも同じレイアウトパスで使い切っていたため、frame 0 で復元して捨てられる挙動は同じだった。ただし TASK-574.1 で `present(...)` の同期 1 本に畳んだことで**後のレイアウトで再試行する余地が無くなった**ので、起きたときに自力で回復しない。

## 未確認の前提

**本番で実際にこの経路を通るかは未確認。** `PDFPreviewView.updateNSView` は SwiftUI のレイアウトパスで呼ばれ、`contentRevision` のガードがあるため、実際の文書が入るのは面が寸法を得た後である可能性が高い。着手時にまずこれを測ること（確認方法: `present(...)` の入口で `bounds` を実機のログに出し、切り替え・新規ウィンドウ・別種別からの復帰の 3 経路で 0 になるか見る）。

**通らないなら塞がない。** 通らない経路のために状態を足すのは TASK-574 が撤去したばかりの仕掛けを戻すことになる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `present(...)` の入口で `bounds` が 0 になる経路が本番に存在するかを実測し、結果を Notes に残している
- [ ] #2 存在する場合、面の寸法が確定してから位置を入れる形になっている（保留状態を新設せずに済む形を優先する）
- [ ] #3 存在しない場合、その実測を Notes に残したうえでクローズしている（コードは変えない）
<!-- AC:END -->
