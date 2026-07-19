---
id: TASK-74
title: サイドバーの開閉状態をウィンドウ単位に記憶する
status: To Do
assignee: []
created_date: '2026-07-19 11:53'
labels: []
dependencies: []
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状サイドバー(ファイルツリー)の開閉状態はウィンドウ単位で記憶されていない。
ウィンドウごとに開閉状態を保持し、新規ウィンドウを開いたときのデフォルトは
「ユーザーが最後に操作したサイドバー開閉状態」かつ「最後にアクティブだった
ウィンドウの設定」を引き継ぐ。

参考: 既存の永続化パターンとして SessionStore
(App/SessionStore.swift、noteActivated/savedActivePath でアクティブウィンドウの
記録を UserDefaults に永続化している)や PerFileStateStore
(App/PerFileStateStore.swift、ファイル単位の状態記憶)がある。新規ウィンドウの
デフォルト値解決は「最後にアクティブだったウィンドウ」の状態を参照する点で
SessionStore の noteActivated の仕組みと関連する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 各ウィンドウでサイドバーの開閉状態を個別に切り替えられ、切り替えた状態がそのウィンドウに保持される
- [ ] #2 既存ウィンドウのサイドバー開閉状態はアプリ再起動後も復元される
- [ ] #3 新規ウィンドウを開いたとき、サイドバーの初期開閉状態は最後にアクティブだったウィンドウの状態を引き継ぐ
- [ ] #4 起動直後などアクティブウィンドウの記録がない場合はユーザーが最後に操作した開閉状態にフォールバックする
- [ ] #5 他ウィンドウのサイドバー開閉状態を変更しても、既存の他ウィンドウの表示状態には影響しない
<!-- AC:END -->
