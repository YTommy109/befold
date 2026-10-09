---
id: TASK-691
title: サイトにスライド窓・比較基準の切り替え・PDF 内検索の説明を足す
status: To Do
assignee: []
created_date: '2026-10-09 07:32'
updated_date: '2026-10-09 07:38'
labels: []
milestone: m-12
dependencies:
  - TASK-690
priority: medium
type: enhancement
ordinal: 880000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実装側にあってサイトに一切書かれていない主要機能がある。調査（2026-10-09、コード読み）: スライド窓は ViewerWindowKind.slide（サイドバー・ツールバー無し、サイドバーの右クリックから開く）で、サイトと README に「スライド」が 0 件。差分の比較基準は「このブランチの変更（既定）／スタック全体／作業中の変更」の 3 択（サイドバーヘッダーと表示メニュー）だが、サイトは既定値の説明だけ。PDF 内検索は PDFKit で実装済みだが、サイトの PDF 記述は「連続スクロール」のみ。TASK-519/520（流入ページ・QuickLook 訴求）とは役割が違い、既存の機能一覧への追記が中心。画像は撮り直しタスクで用意するので、それに依存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 features / landing にスライド窓・比較基準の切り替え・PDF 内検索の説明が入り、記載が現行実装（docs/dev/viewer-ui.md・file-type-display.md）と一致している
- [ ] #2 日英の両方で表示できる（既存の Localized の仕組みに乗っている）
- [ ] #3 ブックマークの独立メニューと Bookmark Editor、CSV の数値列の書式、ファイル行の ⌘クリックの開き分けについて、載せる／載せないを理由つきで決めて Notes に残す
<!-- AC:END -->
