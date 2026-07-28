---
id: TASK-193
title: コードフォントのベースサイズ注入を stable でゲートするか判断する
status: To Do
assignee: []
created_date: '2026-07-28 15:51'
labels: []
dependencies: []
ordinal: 276000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 codeFontSizePoints は常に注入され(既定 10pt≈12.3px)、stable でもソースビューのサイズがシステム/アクセシビリティ文字サイズに追従しなくなる(従来は calc(本文*0.75) で追従)。既定の見た目差は僅少(12.3 vs 12px)だが、stable でアクセシビリティ文字サイズ追従を保ちたい場合はサイズ注入を FeatureGate で囲うか、未設定時は size 変数を注入しない設計にする。要判断。opus 最終レビューの Minor 指摘由来。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 stable でのソースビュー サイズがアクセシビリティ文字サイズに追従すべきか方針決定し、必要なら実装する
<!-- AC:END -->
