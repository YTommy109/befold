---
id: TASK-911
title: 空タブからの Quick Open などでも空タブを置き換える
status: To Do
assignee: []
created_date: '2026-11-07T06:38:00Z'
labels:
  - tabs
  - ui
dependencies:
  - TASK-910
references:
  - BefoldApp/befold/App/QuickOpenCoordinator.swift
  - BefoldApp/befold/App/ActiveViewerProvider.swift
priority: medium
ordinal: 877000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
空タブで ⌘P からファイルを開くと、空タブが残ったまま別の窓が開く（2026-11-07 実機確認）。⌘O とドロップは空タブを置き換えるので、⌘T → ⌘P という自然な操作だけ結果が違う。`ActiveViewerProvider.fromMainWindow` が `ViewerWindowController` へキャストするため、空タブでは操作対象の窓が無い扱いになることが原因。Open Recent とブックマークも同様と思われるが未確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 空タブで Quick Open からファイルを開くと、その空タブが置き換わる
- [ ] #2 Open Recent とブックマークの空タブでの動作を確認し、置き換えるか現状のままかを決めて docs/dev/viewer-ui.md に記載している
- [ ] #3 空タブの ⌘O と Quick Open が候補や初期ディレクトリの基準にする文書が、タブグループの文書との関係も含めて決まっている
<!-- AC:END -->
