---
id: TASK-574
title: PDF 面の差し替えライフサイクルを PDFKit の非同期性に合わせて構造化する
status: To Do
assignee: []
created_date: '2026-08-30 03:37'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 831000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDFKit 導入（ADR 0009）で命令の宛先（`DocumentSurfaces`）・読み込み経路（`.binary`）・レイアウト規則（`PDFSurfaceLayout`）は設計し直された一方、**「文書を差し替えてから最初の絵が出るまで」のライフサイクルだけは WebView 時代の前提（差し替えは 1 回の同期処理で完結し、待つものは無い）のまま**になっている。PDFKit は (a) タイル描画がバックグラウンド、(b) `PDFViewDocumentChanged` → `needsLayout`、(c) `didRotatePage` → メインキューの再レイアウト、と 3 箇所で非同期であり、その差分を埋める手当てが個別の仕掛けとして積み上がった。

| 非同期の現れ方 | 入った手当て |
| --- | --- |
| 表示サイクル待ち | `display()`（47dd9aab → 1470785e で revert） |
| 位置を入れる余地がまだ無い | `ZoomingPDFView.pendingRestoreFraction` センチネル |
| 回転後の再レイアウトが後から来る | `PDFSurfaceLayout.rotate` 内の `DispatchQueue.main.async` |
| タイル到着を知れない | `PDFSurfacePlaceholder` ＋ 外す条件 5 つ ＋ 0.4 秒タイマ |
| PDFKit がサブビューを積み直す | `noteLayout` で毎回 `addSubview` し直す |

この積み重ねが順序バグを生んでいる（TASK-567 → TASK-569 → 回転記憶での倍率上書き、と同型 3 件目）。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に従い、個別修正ではなく構造で対処する。

## レビューの裏付け（2026-08-30）

- **実測**: 回転記憶のあるファイルへの切り替えで、同期区間の直後は倍率 1.0・静止画ありだが、main キュー 1 周後に前のファイルの倍率 3.0 へ上書きされ静止画も外れる（一時テスト、削除済み）
- **dagayn `review_tool(mode="changes", base=origin/main)`**: レビュー優先度 0.40（medium）。`BefoldApp/befold/Viewer` は安定コンポーネント（instability 0.33）なのに変更ノードの直接テスト密度が 0（期待 0.8）で、`PDFPreviewView.updateNSView` / `installPlaceholder` が未検証（reason code: `stable_component_contract_gap`）。`refactor_tool(mode="suggest")` は 2,333 件のうち PDF 関連ファイルを 1 件も挙げていない——**サイズや複雑度の問題ではなく、所有権と順序の問題**であることと整合する。なお `tests_for` / `callers_of` は既知の取りこぼし（`PDFSurfaceLayoutTests` があるのに 0 件、`apply` の呼び出し 6 箇所中 1 件）なので、以下の件数は grep による
- **責任の集中（grep / `wc -l`）**:
  - `PDFSurfaceLayout`（258 行・static メンバ 17）が、純粋な換算（`fitScale` / `scrollOffset` / `normalized`）と面への副作用（`configure` / `apply` / `rotate` / `restore` / `scrollSmoothly`）と横断的な副作用（`placeholder.dismiss()`）を 1 つの enum に抱えている。呼び出し元は PDF 関連 4 ファイルすべてで、`apply` だけで 6 箇所
  - `ZoomingPDFView`（176 行・stored property 8）が、ジェスチャ・倍率の記憶・復元待ち・静止画・一度きりの配線・通知購読を持ち、`layout()` の override が 5 つの仕事（初回配線・`allowsMagnification` の毎回切り・倍率維持・復元・静止画の維持）をしている
  - 静止画を外す呼び出しが 3 ファイル 6 箇所に散っている（`PDFSurfaceLayout` 2、`PDFPreviewView` 3、`ZoomingPDFView` 1）
- **同じ概念に 2 つのデータフロー**: スクロール位置は WebView 面が `scrollPositionChanged` で常時 push、PDF 面は `saveScrollPositionBeforeTransition` からの切替時 pull のみ。回転は提示開始時に `store.pdfRotation` へ読み込むが以後 store へは戻さず退出時に面から pull。`WindowPresentationMemory` に PDF 専用の `rotations` 表が生えている
- **共有概念からの除外**: 読み込み表示は `showsLoadingIndicator` の `!fileType.rendersFromData` で PDF を除外している（PDF にとっての「読み込み中」を定義していない）

## 到達したい形

- 差し替えの手順（document → 回転 → 倍率 → 位置 → 静止画）を SwiftUI の外の 1 オブジェクトが同期関数 1 本で持ち、`updateNSView` は入力の変化を伝えるだけにする
- 静止画は `PDFView` の内部階層ではなく `DocumentSurfaceStack` のオーバーレイ層に state 駆動で置く
- 提示記憶（位置・回転）の流れる向きを両面で揃える
- 試行錯誤の残留物（死コード・設計文書の矛盾）を除く

子タスクごとに `/review-design` を回すこと（CLAUDE.md「実装着手前の設計レビュー」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 子タスクがすべて Done で、TASK-569 の測り方（`.tmp/t569/sampler`、18 回）で 200ms 超の跳ねが 0 回のまま維持されている
- [ ] #2 `docs/dev/native-app-design.md` の PDF 関連の記述が実装と一致している（`autoScales` の記述を含む）
<!-- AC:END -->
