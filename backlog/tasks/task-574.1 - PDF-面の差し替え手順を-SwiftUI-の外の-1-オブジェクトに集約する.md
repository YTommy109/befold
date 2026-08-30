---
id: TASK-574.1
title: PDF 面の差し替え手順を SwiftUI の外の 1 オブジェクトに集約する
status: To Do
assignee: []
created_date: '2026-08-30 03:38'
updated_date: '2026-08-30 04:31'
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
- [ ] #1 差し替え（document・回転・倍率・位置・静止画）の順序を 1 つの同期関数が持ち、`NSViewRepresentable.Context` 無しでユニットテストから呼べる
- [ ] #2 PDF 関連ファイル（`App/PDF*.swift` / `App/ZoomingPDFView.swift` / `Viewer/PDF*.swift`）に `DispatchQueue.main.async` と `pendingRestoreFraction` が残っていない
- [ ] #3 `ZoomingPDFView.layout()` から初回配線（`hasFinishedOneTimeSetup`）が消え、`layout()` の仕事が「倍率の意味を保つ」に限られている
- [ ] #4 `PDFSurfaceLayout` に面を変更する副作用（`apply` / `rotate` / `restore` / `configure` / `scrollSmoothly`）が残っておらず、換算だけになっている
- [ ] #5 TASK-572 / TASK-573 で足した順序のテストが緑のまま維持されている
- [ ] #6 `/review-design` の結果が Implementation Plan に反映されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-572（2026-08-30 / e144c501）で `PDFSurfaceLayout.rotate` の `DispatchQueue.main.async` は撤去済み。撤去対象のうち残るのは `pendingRestoreFraction` と `hasFinishedOneTimeSetup`、および `layout()` の多重責務。

TASK-575（静止画の撤去）により、このタスクの撤去対象はさらに減った。残るのは `pendingRestoreFraction` センチネル（TASK-573 で条件は正した）と `hasFinishedOneTimeSetup`、および `layout()` の多重責務。`DispatchQueue.main.async` と静止画の寿命管理は既に消えている。
<!-- SECTION:NOTES:END -->
