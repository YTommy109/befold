---
id: TASK-916
title: 空タブの手前で Open Recent・ブックマークから開くと、別の窓のファイルが前面化されず重複する
status: To Do
assignee: []
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T08:36:00Z'
labels:
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowOpenPolicy.swift
documentation:
  - docs/dev/viewer-ui.md
priority: medium
type: bug
ordinal: 882000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。別の窓で既に開いているファイルを Open Recent・ブックマークから開くと、手前が文書タブなら既存の窓が前面に出るが、手前が空タブだと空タブの位置に重複したタブができる。手前のタブの種類で結果が変わる理由が利用者に無い。Quick Open とサイドバーは文書タブでも「操作中の窓で切り替える」規則（`ViewerWindowController.performFileSwitch`）なので、空タブでの重複は既存の規則と揃っており、この対象ではない。

裏付け（コード参照・実機未確認）: `DocumentOpener.openViewer(for:focusesContent:)` は手前が文書タブなら起点なしの `.currentTab` を渡し、`reusableController` はどの窓の既存も前面化する。手前が空タブだと `ViewerWindowOpenPolicy.effectiveDisposition` が `.newTab` へ読み替え、`reusableController` の `.newTab` は同じタブグループしか候補にしない。テストは同じタブグループの場合だけを見ている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 手前が空タブのとき、別の窓で開いているファイルを Open Recent・ブックマークから開くと、既存の窓が前面に出て新しいタブが増えない
- [ ] #2 その場合の空タブの扱い（残すか閉じるか）が決まり、docs/dev/viewer-ui.md に書かれている
- [ ] #3 別の窓で開いている場合の自動テストがある
<!-- AC:END -->
