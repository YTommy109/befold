---
id: TASK-574.1
title: PDF 面の差し替え手順を SwiftUI の外の 1 オブジェクトに集約する
status: Done
assignee: []
created_date: '2026-08-30 03:38'
updated_date: '2026-08-30 04:48'
labels:
  - refactor
dependencies:
  - TASK-572
  - TASK-573
parent_task_id: TASK-574
priority: medium
type: task
ordinal: 832000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PDFPreviewView.updateNSView` に書かれた差し替えの手順（`document =` → `PDFSurfaceLayout.apply(rotation:)` → `apply(zoom:)` → `pendingRestoreFraction` → `layoutSubtreeIfNeeded()` → `placeholder.install`）を、SwiftUI の外にある 1 つのオブジェクトが**同期関数 1 本**で持つ形にする。`updateNSView` は「新しい入力が来た」ことを伝えるだけにし、順序をそこに書かない。

## いま順序を守っている仕掛け（撤去の対象）

- `ZoomingPDFView.pendingRestoreFraction`（レイアウト後の別タイミングへ復元を先送りするセンチネル）
- `PDFSurfaceLayout.rotate` の `DispatchQueue.main.async` による倍率の再適用（TASK-572 の原因）
- `ZoomingPDFView.layout()` の `hasFinishedOneTimeSetup` による初回配線
- `ZoomingPDFView.layout()` が毎回行う 5 つの仕事（初回配線・`allowsMagnification` 切り・倍率維持・復元・静止画の維持）

## あわせて分離するもの

`PDFSurfaceLayout` が純粋な換算（`fitScale` / `scrollOffset(forFraction:room:)` / `normalized` / `expectedScaleFactor`）と面への副作用（`configure` / `apply` / `rotate` / `restore` / `scrollSmoothly`）と横断的な副作用（`placeholder.dismiss()`）を 1 つの enum に抱えている（static メンバ 17・呼び出し元 4 ファイル）。副作用側を差し替えオブジェクトへ寄せ、`PDFSurfaceLayout` は換算だけにする。

## 前提の確認（着手時）

- `didRotatePage` 後の PDFKit の再レイアウトで `ZoomingPDFView.layout()` が呼ばれるか（TASK-572 の単純化案の可否を決める）
- `PDFViewDocumentChanged` の通知が差し替え関数の中で同期に届くか、後から届くか

dagayn `review_tool` が `PDFPreviewView.updateNSView` / `installPlaceholder` を安定コンポーネントの未検証ノードとして挙げている（`stable_component_contract_gap`）。差し替えオブジェクトは `NSViewRepresentable` の `Context` 無しで呼べる形にし、順序をテストで固定する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差し替え（document・回転・倍率・位置・静止画）の順序を 1 つの同期関数が持ち、`NSViewRepresentable.Context` 無しでユニットテストから呼べる
- [x] #2 PDF 関連ファイル（`App/PDF*.swift` / `App/ZoomingPDFView.swift` / `Viewer/PDF*.swift`）に `DispatchQueue.main.async` と `pendingRestoreFraction` が残っていない
- [x] #3 `ZoomingPDFView.layout()` から初回配線（`hasFinishedOneTimeSetup`）が消え、`layout()` の仕事が「倍率の意味を保つ」に限られている
- [x] #4 `PDFSurfaceLayout` に面を変更する副作用（`apply` / `rotate` / `restore` / `configure` / `scrollSmoothly`）が残っておらず、換算だけになっている
- [x] #5 TASK-572 / TASK-573 で足した順序のテストが緑のまま維持されている
- [x] #6 `/review-design` の結果が Implementation Plan に反映されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（2026-08-30）

### 採用案: 案 B（副作用を `ZoomingPDFView` のメソッドにする）

案 A（新規 `PDFSurfaceDriver`）を採らない。決め手は **`layout()` に残る副作用を Driver へ移せない**こと。`allowsMagnification = false` / `keepZoomAfterLayout` / `needsLayout = true` はいずれも「レイアウトのたびに入れ直す」ことが正しさの根拠なので `layout()` の外へ出せず、案 A では**倍率の書き込み口が Driver と View の 2 箇所に割れる**。これは TASK-572 で実際に壊れた「倍率の上書き」と同じ形の再発面を作る。

WebView 面（`ViewerWebView.makeCoordinator() -> ViewerRenderer`）が案 A の形をしているのは事実だが、**WKWebView は `layout()` の責務を持たない素の View** である一方 `ZoomingPDFView` は倍率維持を毎レイアウト行う。この非対称が対称性の論拠を打ち消す。ただし「実行するドライバ + 純粋な換算」という分業自体は WebView 面（`ViewerRenderer` + 純関数 `ContentUpdatePlanner`）と同型で、案 B の `ZoomingPDFView` + 純粋な `PDFSurfaceLayout` はその対応を保つ。

AC #1 の「SwiftUI の外の 1 オブジェクト」は `ZoomingPDFView` が満たす（`NSViewRepresentable.Context` 無しでユニットテストから直接生成・呼び出しできる）。

### チェックリストの回答

1. **判定の真実の源**: 該当あり（改善）。復元の可否を `pendingRestoreFraction` という**保留状態の有無**で決めていたのをやめ、`present(...)` の直線順序へ畳む。保留状態をそもそも作れなくする＝「破りようのない構造」。
2. **既存の不変条件との衝突**: 面を破棄・再生成しない（TASK-266）は保つ。`present(document: nil)` で文書だけ外す経路を残す。
3. **消費経路と兄弟判断**: `pdfView.document =` の代入は `PDFPreviewView.updateNSView` の 2 箇所のみ（grep 実測）。副作用の呼び出し元は `ZoomingPDFView` / `PDFDocumentRenderer` / `PDFPreviewView` の 3 ファイルで、QuickLook 拡張は PDF 面を使わない（grep 実測）。全部を新メソッドへ付け替える。
4. **新しい状態に対応する表示**: 該当しない。新しい表示状態は増えない（静止画は TASK-575 で撤去済み）。
5. **ライフサイクル・順序の変化**: 中核。実測で裏取り済み（下記）。
6. **高頻度経路のコスト**: `present(...)` は revision 変化時のみ。`layout()` は仕事が減る（復元の分岐が消える）。
7. **測るものと守るものの一致**: `present(...)` を Context 無しで呼べるので、本番と同じ関数をテストが測る（現状のテストは updateNSView の順序を**手で真似ていた** = `simulateSwitch`）。
8. **非同期で置き換わる表示状態の世代管理**: 該当しない。`present(...)` は完全同期で、非同期の着地が無い。世代管理は `Coordinator.appliedRevision` が従来どおり担う。
9. **決めた粒度を守らせるもの**: 保留状態の撤去そのものが構造的担保。加えて `configure` を `ZoomingPDFView.init` へ移し、**未設定の面が存在できなくする**（L1）。
10. **型グループの行数と責務**: `ZoomingPDFView` 177 → 250 前後、`PDFSurfaceLayout` 264 → 150 前後（いずれも閾値以下）。関心の差し引きは **+1 / −2**（+ `present`、− 復元待ちの保留、− 一度きり配線フラグ）。新しい stored property は増えず 2 つ減る。プロトコル準拠・クロージャ注入（`onZoomChanged` の 1 つ）は不変。

### 実測で裏を取った前提（一時テスト / 削除済み）

- **直線順序で位置が入る**: document → rotation → zoom → `layoutSubtreeIfNeeded()` → restore で `isLaidOut=true` / 余地 23233.5 / 復元後 fraction = 0.5000000000015。`pendingRestoreFraction` は不要。
- **後追いレイアウトで戻されない**: 300ms + 再レイアウト後も 0.5000000000015 のまま。
- **`hasFinishedOneTimeSetup` は撤去できる**: init で `addGestureRecognizer` した認識器はレイアウト後も生きている。
- **ベースライン**: PDF 関連 44 tests / 8 suites すべて緑。

### 別タスクへ切り出す（このタスクでは直さない）

**`isLaidOut` は frame 0 の面でも true を返す**（実測: 余地 24045 を返し、復元は成功したように見えるが、本物の frame が付いた瞬間に位置が 0 へ戻る / 0.5 → 1.06e-06）。センチネル方式でも同じレイアウトパスで使い切るため**既存の穴であり本タスクの退行ではない**が、撤去すると再試行の余地が無くなる。`updateNSView` が最終 frame 確定後に走るかは未確認（確認方法: 実機で `present` 時の `bounds` を測る）。起票して分離する。

### 実装手順

1. `PDFSurfaceLayout` から副作用 6 つ（`configure` / `apply(zoom:to:)` / `apply(rotation:to:)` / `rotate(byDegrees:in:)` / `restore(fraction:in:)` / `scrollSmoothly(by:in:)`）を `ZoomingPDFView` のメソッドへ移す。`configure` は `init` へ畳む。
2. `ZoomingPDFView.present(document:rotation:zoom:scrollFraction:)` を同期 1 本で追加（document → rotation → zoom → `layoutSubtreeIfNeeded()` → restore）。
3. `pendingRestoreFraction` / `applyPendingRestore` / `hasFinishedOneTimeSetup` を撤去。`layout()` は `allowsMagnification` 切りと倍率維持だけにする。
4. `PDFPreviewView.updateNSView` を `present(...)` の 1 呼び出しへ縮める。
5. 呼び出し元（`PDFDocumentRenderer`）とテスト 5 本を新しい呼び出し形へ付け替える。順序のテストは `simulateSwitch` の手真似をやめ `present(...)` を直接呼ぶ形にする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-572（2026-08-30 / e144c501）で `PDFSurfaceLayout.rotate` の `DispatchQueue.main.async` は撤去済み。撤去対象のうち残るのは `pendingRestoreFraction` と `hasFinishedOneTimeSetup`、および `layout()` の多重責務。

TASK-575（静止画の撤去）により、このタスクの撤去対象はさらに減った。残るのは `pendingRestoreFraction` センチネル（TASK-573 で条件は正した）と `hasFinishedOneTimeSetup`、および `layout()` の多重責務。`DispatchQueue.main.async` と静止画の寿命管理は既に消えている。

## 実装（2026-08-30）

案 B を採用（`/review-design` の結果は Implementation Plan に記載）。

### 変えたもの

- `PDFSurfaceLayout` 264 → 163 行。副作用 6 つ（`configure` / `apply(zoom:to:)` / `apply(rotation:to:)` / `rotate(byDegrees:in:)` / `restore(fraction:in:)` / `scrollSmoothly(by:in:)`）を撤去し、換算だけの enum にした。
- `ZoomingPDFView` 177 → 315 行。上の 6 つを面のメソッドとして受け、`present(document:rotation:zoom:scrollFraction:)` を同期 1 本で追加。`configure` は `init(frame:)` へ畳み、`init?(coder:)` は `@available(*, unavailable)` にした（**未設定の面が存在できない**）。
- `pendingRestoreFraction` / `applyPendingRestore` / `hasFinishedOneTimeSetup` を撤去（stored property 純減 2）。`layout()` は `allowsMagnification` 切りと `keepZoomAfterLayout()` の 2 行だけになった。
- `PDFPreviewView.updateNSView` は `present(...)` の 1 呼び出しへ（77 → 67 行）。
- `docs/dev/native-app-design.md` の該当 3 行を新しい構造へ更新。

### 検証

- `swift test` 全件: **1810 tests / 293 suites 緑**（23.6 秒）。PDF 関連は 44 → 54 tests（`present` 経由の順序テストを 4 本追加）。
- swiftlint ベースライン差分: main 54 件 / head 54 件、**真の新規 0・解消 0**。
- swiftformat fix モード適用済み。
- markdownlint / `check-doc-symbols.sh` / `check-doc-citations.sh` すべて 0 件。
- AC #2 の grep: PDF 関連ファイルのコードに `DispatchQueue.main.async` と `pendingRestoreFraction` は 0 件（doc コメント内の履歴記述 2 箇所のみ残す。再導入を防ぐための記録なので意図的）。

### テストの質の変化

順序のテストが `simulateSwitch` で `updateNSView` の手順を**手で真似ていた**のをやめ、`present(...)` を直接呼ぶ形にした。従来は「テストが真似た順序」を測るだけで、本番の順序が変わっても気づけなかった（`/review-design` チェック項目 7「測るものと守るものの一致」）。

### 切り出した課題

TASK-574.5（`isLaidOut` が frame 0 でも true を返し、記憶していた位置が捨てられる）。既存の穴で本タスクの退行ではないが、`present` の同期 1 本化で再試行の余地が無くなったため分離した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
PDF 面の差し替え手順を `ZoomingPDFView.present(document:rotation:zoom:scrollFraction:)` の同期 1 本に集約し、`PDFSurfaceLayout` を換算だけの enum に痩せさせた（264 → 163 行）。順序を守るための保留状態（`pendingRestoreFraction`）と一度きり配線フラグ（`hasFinishedOneTimeSetup`）を撤去し、`layout()` の仕事を 2 つに絞った。`configure` を `init` へ畳んだことで未設定の面が存在できなくなっている。

`/review-design` で案 A（新規 Driver 型）と案 B（面のメソッド）を比較し B を採用。決め手は `layout()` に残る副作用（`allowsMagnification` / 倍率維持）を Driver へ移せず、案 A だと倍率の書き込み口が 2 箇所に割れて TASK-572 と同型の再発面を作ること。

検証: `swift test` 1810 tests 全緑、swiftlint 新規違反 0（54 → 54）、AC の grep 条件を満たすことを確認。`docs/dev/native-app-design.md` を新構造へ更新。副次的に、順序のテストが手順を手で真似る形から本番の `present(...)` を直接呼ぶ形になった。
<!-- SECTION:FINAL_SUMMARY:END -->
