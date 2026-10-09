---
id: TASK-696
title: Info.plist に LSApplicationCategoryType を追加する
status: To Do
assignee: []
created_date: '2026-10-09 13:29'
labels:
  - tech-debt
dependencies: []
priority: low
ordinal: 885000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/Info.plist` に `LSApplicationCategoryType` が無い(App Store 掲載調査 2026-10-09 で確認。project.yml 側にも無い)。Finder の「カテゴリ」表示などに使われ、将来 Mac App Store に出す場合は必須になる。1 行で済む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `LSApplicationCategoryType` が本体の Info.plist(生成後の値)に入っている。カテゴリは Developer Tools か Productivity のうち、配布サイトの説明に合う方を選び、理由を Notes に残す
- [ ] #2 Info.plist を検査する既存テストがあれば通る
<!-- AC:END -->
