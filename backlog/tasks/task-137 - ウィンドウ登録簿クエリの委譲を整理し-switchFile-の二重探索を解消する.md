---
id: TASK-137
title: ウィンドウ登録簿クエリの委譲を整理し switchFile の二重探索を解消する
status: To Do
assignee: []
created_date: '2026-07-24 22:41'
labels:
  - refactor
  - structural
  - app
dependencies: []
priority: medium
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
controllers 辞書([String: ViewerWindowController], ViewerWindowManager)への問い合わせが SidebarNavigator.isFileOpenElsewhere → ViewerWindowController.isFileOpenElsewhere(単純転送)→ delegate.viewerWindow(_:isFileOpenInAnotherWindow:) → ViewerWindowManager.isOpenInAnotherWindow の 3 段パススルーを経る。ViewerWindowController は論理を足さず 2 つ目のプロトコル名で再公開するだけ。さらに switchFile は delegate.isFileOpenInAnotherWindow(newURL) の後 true なら delegate.focusWindowForFile(newURL) を呼び、manager 側では両方が existingOtherController で解決するため同じ辞書 lookup+!== ガードが 1 操作で二重に走る。ViewerWindowControllerDelegate(7メソッド)が登録簿の実装詳細を leak する chatty interface。構造レビュー(2026-07-25)で検出。TASK-116.13(VWM への controller 生成注入)とは別 seam。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 boolean 判定と focus を 1 つの delegate 呼び出し(例: existing target を optional で返す)へ統合し、switchFile の二重 lookup が解消している
- [ ] #2 SidebarNavigatorHost が登録簿クエリを直接転送し、ViewerWindowController の並行プロトコル名再宣言が不要になっている
- [ ] #3 swift build/test が通り、別ウィンドウで開いているファイルへのフォーカス挙動に回帰がない
<!-- AC:END -->
