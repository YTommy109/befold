---
id: TASK-358
title: 紹介サイトの文言を macOS 専用と分かる形に整える
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 04:49'
updated_date: '2026-08-08 05:32'
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
- [x] #1 ファーストビュー（h1 直下のリード文またはキャッチコピー）に Mac / macOS 向けであることが日本語・英語の両方で明示される
- [x] #2 ダウンロードボタンの近辺で、クリック前に macOS 専用（macOS 14 以降）だと分かる
- [x] #3 既存の日英切り替え（lang 属性による出し分け）の方式を崩さず、追加文言も日英そろって用意されている
- [x] #4 <title> / og:title / og:description と本文の文言に矛盾がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. hero のリード文（日英）に Mac / macOS 向けであることを入れる
2. ダウンロードボタン直下に macOS 14 (Sonoma) 以降が必要である旨の注記を日英で追加し、style.css に .hero-note を足す
3. title / og と本文の整合を確認する
4. test/public.test.ts に日英双方の Mac 明示を検証するテストを追加し vitest / tsc を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
hero のリード文を日英とも Mac 専用と分かる文言に変え（Mac 専用 / Mac-only）、ボタンラベルを「Mac 版をダウンロード」/「Download for Mac」に、ボタン直下へ .hero-note で macOS 14 (Sonoma) 以降の注記を追加した。日英の出し分けは既存の lang 属性 + hidden 方式をそのまま使用。title / og は元から macOS 明記のため変更不要。検証: site で npx vitest run（57 passed、うち新規『対象 OS の明示』2 件）、npx tsc --noEmit エラーなし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布 LP のファーストビューに Mac 専用であることを日英で明示し、ダウンロードボタン直下に macOS 14 以降の動作要件を追加した。既存の lang 出し分け方式は変更していない。vitest（新規 2 件を含む 57 件 pass）と tsc で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
