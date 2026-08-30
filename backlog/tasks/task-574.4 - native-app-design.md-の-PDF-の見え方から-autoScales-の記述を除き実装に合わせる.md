---
id: TASK-574.4
title: native-app-design.md の PDF の見え方から autoScales の記述を除き実装に合わせる
status: Done
assignee: []
created_date: '2026-08-30 03:38'
updated_date: '2026-08-30 04:49'
labels:
  - docs
dependencies: []
parent_task_id: TASK-574
priority: low
type: docs
ordinal: 835000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`docs/dev/native-app-design.md` の「PDF の見え方」が、現在の実装と矛盾している。

- 文書: 「既定ではページの幅が収まる倍率に自動追従する（`autoScales`）。ウィンドウをリサイズしてもフィットし続け、ユーザーが倍率を変えた時点で追従を外し、⌘0（既定のサイズ）で戻す」
- コード: `PDFSurfaceLayout.configure` は `autoScales = false`。フィットは「ページ全体が収まる」倍率で、リサイズ追従は `ZoomingPDFView.layout()` の `keepZoomAfterLayout` が行う（同じ文書の `ZoomingPDFView` の行はこちらを正しく書いている）

単一の情報源（三層構造の「現在の仕様」層）の中で矛盾しているので、他の子タスクを待たずに直す。同じ節の他の記述（連続スクロール・影・表示位置の向き）は実装と一致していることを確認済み（2026-08-30）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「PDF の見え方」の段落に `autoScales` による幅追従の記述が無く、フィットの定義（ページ全体が収まる・文書内最大ページ基準）とリサイズ追従の担い手（`ZoomingPDFView.layout`）が書かれている
- [x] #2 `markdownlint-cli2` と `scripts/check-doc-citations.sh` が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-574.1 で `PDFSurfaceLayout.configure` が `ZoomingPDFView.init` へ畳まれたため、起票時に「コード」欄で引いていた `PDFSurfaceLayout.configure は autoScales = false` という所在も変わっている。文書は新しい所在（`ZoomingPDFView`）で書いた。

検証: `markdownlint-cli2` 0 件 / `scripts/check-doc-citations.sh` 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「PDF の見え方」から `autoScales` による幅追従の記述を除き、実装（`autoScales = false`・フィットはページ全体・リサイズ追従は `ZoomingPDFView.layout`）に合わせた。幅基準だとページ下端が画面外に出るという実測値も併記した。
<!-- SECTION:FINAL_SUMMARY:END -->
