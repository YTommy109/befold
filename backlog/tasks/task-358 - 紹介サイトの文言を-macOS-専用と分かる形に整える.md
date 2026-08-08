---
id: TASK-358
title: 紹介サイトの文言を macOS 専用と分かる形に整える
status: To Do
assignee: []
created_date: '2026-08-08 04:49'
labels:
  - site
dependencies: []
priority: medium
ordinal: 617000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布 LP (site/src/views/landing.tsx) からダウンロードした Windows ユーザーがいた。ページ内には macOS 14 以降という記載や 'File Viewer for macOS' の <title> はあるが、ファーストビュー（h1・リード文・ダウンロードボタン周辺）に対象 OS が出ておらず、スクロールしないと Mac 専用と分からない。ダウンロード前に対象 OS が伝わるよう、ファーストビューに 'Mac ユーザーのための' 相当の文言を入れ、あわせて周辺のリード文・ボタンラベルを日英ともに整える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ファーストビュー（h1 直下のリード文またはキャッチコピー）に Mac / macOS 向けであることが日本語・英語の両方で明示される
- [ ] #2 ダウンロードボタンの近辺で、クリック前に macOS 専用（macOS 14 以降）だと分かる
- [ ] #3 既存の日英切り替え（lang 属性による出し分け）の方式を崩さず、追加文言も日英そろって用意されている
- [ ] #4 <title> / og:title / og:description と本文の文言に矛盾がない
<!-- AC:END -->
