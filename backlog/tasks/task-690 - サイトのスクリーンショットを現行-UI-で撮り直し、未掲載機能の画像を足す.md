---
id: TASK-690
title: サイトのスクリーンショットを現行 UI で撮り直し、未掲載機能の画像を足す
status: To Do
assignee: []
created_date: '2026-10-09 07:32'
updated_date: '2026-10-09 07:38'
labels: []
milestone: m-12
dependencies: []
priority: medium
type: task
ordinal: 879000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ランディングのカルーセル（site/src/views/landing.tsx の SCREENSHOTS、site/public/images/screenshot-1〜8.png）は撮影が古い。実測（git log）: 1〜6 は 2026-07-29/30、7・8（Git）は 08-16、4（CSV）だけ 08-27 に差し替え。撮影後に検索バーとジャンプバーの統合（08-21）、サイドバーヘッダーの整理（08-13）、ブックマークのトップレベルメニュー化（09-12）、比較基準の切り替え UI（10-08/09）など UI を変える feat が多数入った。screenshot-3 と 8 を実際に見て、ツールバー・サイドバーが旧状態であることを確認済み（他の画像は未確認）。TASK-484.5 は git 画像の追加だけで、既存画像の更新は担わなかった。スライド窓・比較基準・PDF 検索はサイト未掲載で、紹介文を足す TASK 側が使う画像もここで撮る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 画像 1 枚ごとに現行 UI との差（ツールバー・サイドバー・ラベル）を表にし、撮り直す対象と据え置く対象を理由つきで Notes に残す
- [ ] #2 撮り直す対象が現行 UI で撮影され、alt 文言とキャプションが画像の内容と一致している
- [ ] #3 スライド窓・比較基準の切り替え・PDF 内検索を示す画像が追加され、サイトの紹介文から使える状態になっている
- [ ] #4 画像の差し替えで OGP（site/public/images/ogp.png）に影響が出ないことを確認している
<!-- AC:END -->
