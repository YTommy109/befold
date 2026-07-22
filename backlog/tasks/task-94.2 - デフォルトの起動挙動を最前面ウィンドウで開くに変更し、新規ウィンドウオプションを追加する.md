---
id: TASK-94.2
title: デフォルトの起動挙動を最前面ウィンドウで開くに変更し、新規ウィンドウオプションを追加する
status: To Do
assignee: []
created_date: '2026-07-22 02:21'
labels: []
dependencies: []
parent_task_id: TASK-94
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 help の discussion には「ファイル/フォルダーを指定すると、それぞれ別ウィンドウで開きます。」とあるが、ユーザーが期待する既定の挙動は最前面のウィンドウで開くこと。
`befold <path>` (単一パス、複数パスの場合の扱いも合わせて要検討)実行時のデフォルト動作を、既存の最前面ウィンドウで開く(タブ/内容差し替えなど既存挙動に合わせる)ように変更し、明示的に新しいウィンドウで開きたい場合のみオプション(例: --new-window)で切り替えられるようにする。
対象: BefoldApp/befold/App/BefoldRootCommand.swift の OpenPathsCommand、および AppDelegate.launch(withInitialPaths:options:) 周りの起動経路。
複数パス指定時に全て別ウィンドウにするのか、最前面+残りを新規ウィンドウにするのか等の細部は実装時に既存のウィンドウ管理仕様(ViewerWindowManager)を調査した上で方針を決定し、実装ノートに記録すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パスを1つ指定して befold を実行すると、既存の最前面ウィンドウで開く(新規ウィンドウを都度作らない)
- [ ] #2 新規ウィンドウで開きたい場合に指定できるオプション(例: --new-window)が用意され、有効にすると新規ウィンドウで開く
- [ ] #3 複数パス指定時の挙動が定義され、テストで検証されている
- [ ] #4 変更後の挙動が --help の説明文に反映されている
- [ ] #5 既存のウィンドウ復元・セッション関連のテストが引き続き成功する
<!-- AC:END -->
