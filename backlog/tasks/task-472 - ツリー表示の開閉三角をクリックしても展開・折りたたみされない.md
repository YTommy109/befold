---
id: TASK-472
title: ツリー表示の開閉三角をクリックしても展開・折りたたみされない
status: To Do
assignee: []
created_date: '2026-08-13 08:25'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 693000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのツリー表示(FeatureGate.isSidebarTreeEnabled 配下)で、フォルダー行の左に出る開閉三角(FileListEntryRow の disclosureIndicator, BefoldApp/befold/Viewer/FileListEntryRow.swift:42-)をクリックしても何も起きない。三角は Image を並べているだけで、タップを受け取る仕組みが無い。

Finder は開閉三角のシングルクリックでその場で展開・折りたたみを行い、行本体のクリック(選択)とは区別する。befold も同じ操作感に合わせたい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツリー表示でフォルダー行の開閉三角をシングルクリックすると、その場で展開・折りたたみが切り替わる
- [ ] #2 三角のクリックは行本体のクリック(選択・フォルダーへの移動)を発火させない
- [ ] #3 折りたたみ状態が .collapsed / .expanded / .loadingChildren / .expandedEmpty / .expandedFailed のいずれでも、クリック対象領域が三角の表示位置と一致している
- [ ] #4 展開・折りたたみのトグルを担う処理がユニットテストで ON/OFF 両方向について押さえられている
<!-- AC:END -->
