---
id: TASK-198
title: 配布サイト analytics ダッシュボードの時刻表示を JST に変える
status: To Do
assignee: []
created_date: '2026-07-30 04:28'
labels: []
dependencies: []
ordinal: 282000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/src/views/dashboard.tsx で event.ts を new Date().toISOString() で UTC 表示している（22行目・127行目のヘッダ・137行目）。日本のユーザー向け運用のため JST 表示に変更する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ダッシュボードの時刻列が JST（UTC+9）で表示される
- [ ] #2 見出しの表記が「時刻 (UTC)」から JST であることが分かる表記に更新されている
- [ ] #3 テストまたは目視確認で表示時刻が UTC+9 ずれていることを確認している
<!-- AC:END -->
