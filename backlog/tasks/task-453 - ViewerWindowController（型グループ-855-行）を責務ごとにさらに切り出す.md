---
id: TASK-453
title: ViewerWindowController（型グループ 855 行）を責務ごとにさらに切り出す
status: To Do
assignee: []
created_date: '2026-08-11 14:24'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 100750
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-441 で 1255 → 852 行まで縮めた ViewerWindowController の型グループが、TASK-449（外部 URL の届け先を ReferenceActions へ寄せる修正）で 855 行へ戻った（scripts/check-type-group-size.sh の実測。ベースラインは scripts/type-group-baseline.txt:14 の 852 行）。集計対象の中で最大であり、TASK-428 のラチェットを最終的に撤去して単純な閾値強制へ畳む（TASK-428.5）ためには返済が要る。

型グループは 'ViewerWindowController.swift + 同ディレクトリの ViewerWindowController+*.swift' の合算なので、extension へ割っても減らない。責務を別の型へ切り出すこと。前例は TASK-441（ReferenceResolutionCoordinator / ReferenceMenuPresenter の切り出し）と TASK-442（SidebarNavigator から git status 関心を独立型へ）。

なお、直近の 3 行増（externalOpener の doc と referenceActions.openExternal の配線）は TASK-449 の修正に必要なもので、巻き戻す対象ではない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 候補となる責務の切り出し先を洗い出し、選んだ分割方針とその理由を Implementation Plan に書いている（extension への再配置ではなく別型への切り出しであること）
- [ ] #2 ViewerWindowController の型グループ合算が 852 行（TASK-441 到達点）以下になり、scripts/type-group-baseline.txt を更新している
- [ ] #3 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
- [ ] #4 xcodegen generate 済みで xcodebuild build が通る
<!-- AC:END -->
