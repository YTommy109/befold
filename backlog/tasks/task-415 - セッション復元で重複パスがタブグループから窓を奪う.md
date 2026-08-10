---
id: TASK-415
title: セッション復元で重複パスがタブグループから窓を奪う
status: To Do
assignee: []
created_date: '2026-08-10 07:27'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 507100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SessionRestorer.restoreTabGroup（SessionRestorer.swift:203）は保存レイアウトの各パスを windowManager.window(forPath:) で引くが、この実装は controllers[path]?.first?.window（ViewerWindowManager.swift:418）で最初の 1 件しか返さない。同じパスが 2 つのタブグループに含まれる保存レイアウトだと、2 件目が復元済みの窓を再ターゲットしてしまう。

再現: README.md をタブグループ A の窓 1 とタブグループ B の窓 2 で開く（重複は設計上許容）。currentSessionLayout() は両グループに同じパスを記録する。再起動するとグループ A の復元で README.md の窓が作られる。続くグループ B の復元では openViewer が .currentTab の重複抑止（ViewerWindowManager.swift:231）で早期 return して窓を作らず、window(forPath:) がグループ A の窓を返し、attachAsTab(window, to: previousWindow, select: false) の addTabbedWindow がその生きている窓を A から B へ移す。結果、A はタブが 1 つ欠け B は 1 つ増える。終了と再起動のたびに再発する。

TASK-412（noteClosed の参照カウント欠落）と同じ「controllers が多重マップであることを呼び出し側が無視している」型。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同じパスが複数のタブグループに含まれる保存レイアウトを復元しても、既存の窓が別グループへ移動しない
- [ ] #2 重複パスの 2 件目は新しい窓として復元される（または明示的に読み飛ばす。どちらを採るか判断を Implementation Notes に残す）
- [ ] #3 終了と再起動を 2 回繰り返してもタブ構成が保存時と一致する
- [ ] #4 ユニットテストで担保する
<!-- AC:END -->
