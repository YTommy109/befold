---
id: TASK-398
title: ADR 0002 の記述を fix/window-live-state の実装へ追随させる
status: To Do
assignee: []
created_date: '2026-08-09 13:34'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 651000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の CONFIRMED 指摘 2 件。docs/adr/0002-presentation-state-and-capabilities.md が実装と矛盾・陳腐化している。

1. **規則 1 の契機一覧が実装と矛盾（242 行付近、210-211 行にも同じ一覧）**: ADR は「保存値を読むのは（オープン・ファイル切替・リネーム）」とするが、実装はリネームで意図的に読まず（beginPresentingDocument の doc「リネームでも呼ばない」、TASK-369）、逆に **モード切替** では ADR 0002 規則 1 を根拠として読んでいる（setDisplayMode:732 付近）。このままだと将来の実装者が ADR に従ってリネーム時の保存値読みを復活させる（TASK-369 の再発）か、モード切替の復元を規則違反として撤去しかねない。正しい一覧は「オープン・ファイル切替・モード切替」。

2. **「現状との差（2026-08-09 時点）」節が陳腐化（206、267-272、336-337 行付近）**: mirrorDisplayMode とデリゲート通知の撤去・ライブ値優先は同ブランチで完了済みなのに、ADR は「実装をこの節へ合わせる作業は TASK-388」「実装があとから追いつく形になる」と未完了として記述している。

markdownlint と scripts/check-doc-symbols.sh を通すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 規則 1 の契機一覧が実装（オープン・ファイル切替・モード切替。リネームは含まない）と一致している
- [ ] #2 「現状との差」節が TASK-388 完了後の実態を反映している
<!-- AC:END -->
