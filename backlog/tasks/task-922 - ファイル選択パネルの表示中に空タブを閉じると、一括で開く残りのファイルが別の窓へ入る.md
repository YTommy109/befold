---
id: TASK-922
title: ファイル選択パネルの表示中に空タブを閉じると、一括で開く残りのファイルが別の窓へ入る
status: To Do
assignee: []
created_date: '2026-11-07T12:47:00Z'
labels:
  - tabs
  - ui
dependencies: []
priority: low
type: bug
ordinal: 888000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-917 の code-review high で挙がり、条件が重なる稀な経路として見送ったもの。空タブで ⌘O のパネルを開いたまま空タブを閉じ、複数のファイルを選ぶ。最初のファイルが既に別の窓 W で開いていると、閉じた起点は `ViewerWindowOpenPolicy.resolveOrigin` で起点なしの `.currentTab` になり、W が前面に出る。`DocumentOpener.openInTabs` はその W を次の起点にするので、残りのファイルが W のタブとして開く。利用者は W を選んでいない。TASK-917 以前はこの一括が丸ごと捨てられていた。裏付けはコード参照のみで、未再現。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 起点の空タブが閉じた一括オープンで、残りのファイルの開き先が決まり、docs/dev/viewer-ui.md に書かれている
- [ ] #2 最初のファイルが別の窓で開いているときの動作を自動テストで確認している
<!-- AC:END -->
