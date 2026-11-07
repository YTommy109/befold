---
id: TASK-916
title: 空タブの手前で Open Recent・ブックマークから開くと、別の窓のファイルが前面化されず重複する
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T11:43:00Z'
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
- [x] #1 手前が空タブのとき、別の窓で開いているファイルを Open Recent・ブックマークから開くと、既存の窓が前面に出て新しいタブが増えない
- [x] #2 その場合の空タブの扱い（残すか閉じるか）が決まり、docs/dev/viewer-ui.md に書かれている
- [x] #3 別の窓で開いている場合の自動テストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: Open Recent・ブックマーク（記憶済みのリスト）は、ファイルが既にどこかの窓で開いていればその窓を前面に出し、空タブは残す。Quick Open は手前のタブで開く規則なので、別の窓で開いていても空タブを置き換える（入口を openInActiveTab に分けた）。viewer-ui.md に記載。
code-review high: 起点を外すときに要求を .newTab のまま残していたため、空タブで同じ項目を続けて選ぶと重複した窓が開く不具合を検出して直した（repeatedRecentOpenDoesNotDuplicate が元の形で落ちる）。既存の窓を優先する判定を、閉じた起点の判定より前に移した。使われなくなった focusesContent 引数を消し、重複した説明を 1 つにした。既存の窓が前面に出たことそのものは、テストの窓がキーにならないので件数で測っている。
実測: 判定を外すと fileOpenElsewhereFollowsRoute が落ちる。swift test 2001 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
手前が空タブでも、Open Recent・ブックマークで別の窓のファイルを開くと既存の窓を前面に出すようにした。空タブは残す。Quick Open は手前のタブで開く規則のまま。
<!-- SECTION:FINAL_SUMMARY:END -->
