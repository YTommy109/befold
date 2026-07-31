---
id: TASK-225
title: サイドバー一覧反映後の normalizedPathKey 一斉評価を列挙時の事前計算に置き換える
status: To Do
assignee: []
created_date: '2026-07-31 09:14'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator.swift の onApplied（MainActor）内で entries.contains { $0.url.normalizedPathKey == key } のような突き合わせが複数箇所（:132,:174,:186,:194,:216,:298）あり、normalizedPathKey は resolvingSymlinksInPath の syscall なのでエントリ数ぶんの stat が MainActor で走る。列挙自体はメイン外へ逃がしたのに突き合わせだけ残っている。FileListEntry に列挙時（メイン外）に解決済みの pathKey を持たせるか、突き合わせ用 Set を listEntriesAsync の戻り値に含める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 一覧反映後の pathKey 突き合わせで MainActor 上の syscall がエントリ数に比例しない
- [ ] #2 選択維持・ルート更新などの既存挙動が維持されている
<!-- AC:END -->
