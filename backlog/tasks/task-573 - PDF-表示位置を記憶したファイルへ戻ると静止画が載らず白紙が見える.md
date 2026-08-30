---
id: TASK-573
title: 'PDF: 表示位置を記憶したファイルへ戻ると静止画が載らず白紙が見える'
status: To Do
assignee: []
created_date: '2026-08-30 03:37'
labels:
  - bug
dependencies: []
priority: medium
type: bug
ordinal: 830000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`PDFPreviewView.installPlaceholder` は `pendingRestoreFraction != nil` のとき静止画を載せない（載せた直後に復元スクロールで絵がずれるため）。そのため、**表示位置を記憶しているファイルへ戻る経路**では TASK-569 の対処が効かず、白紙の区間がそのまま見える。切り替えの中でもっとも多い経路（サイドバーで行き来する）がこれに当たる。

## 裏付け

- コード参照: `PDFPreviewView.installPlaceholder` の guard（`pdfView.pendingRestoreFraction == nil`）、`ZoomingPDFView.applyPendingRestore` が `verticalScrollRoom > 0` でないと値を捨てない点
- **未実測**: 実機で「位置記憶のあるファイルへ戻る」ときの白紙区間は測っていない。TASK-569 の計測一式（`.tmp/t569/sampler.swift` / `compare.sh`）で、位置記憶あり／なしの 2 条件を並べて測ることで確認できる
- 派生の疑い（未確認）: 1 ページで面に収まる文書では余地が 0 のまま `pendingRestoreFraction` が消えず、静止画が永久に載らない可能性がある。`verticalScrollRoom` の実値で確認できる

## 位置づけ

原因は「位置の復元がレイアウト後の別タイミングへ先送りされ、静止画の生成がそれを待てない」順序の問題で、TASK-567 / TASK-569 と同型。個別の対処（復元後に載せ直す等）で症状は消せるが、構造で塞ぐのは PDF 面の差し替え手順を 1 オブジェクトへ集約するリファクタリング側で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 位置記憶あり／なしの 2 条件で、切り替えから中身が出るまでの時間が TASK-569 と同じ測り方（18 回・中央値・最大・200ms 超の回数）で記録されている
- [ ] #2 位置記憶のあるファイルへ戻ったときも静止画が載ることをユニットテストが固定している（復元が済んだ状態で `isShowing` が true）
- [ ] #3 1 ページで面に収まる文書（余地 0）で `pendingRestoreFraction` が残り続けないことをテストが固定している
<!-- AC:END -->
