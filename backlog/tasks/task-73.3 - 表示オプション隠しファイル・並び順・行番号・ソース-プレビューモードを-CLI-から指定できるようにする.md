---
id: TASK-73.3
title: 表示オプション(隠しファイル・並び順・行番号・ソース/プレビューモード)を CLI から指定できるようにする
status: To Do
assignee: []
created_date: '2026-07-19 09:11'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
起動時に以下の表示状態を CLI オプションで指定できるようにする。TASK-73.1 の
引数パーサー基盤に依存する。既存の設定ストア(HiddenFilesPreference など)を
再利用し、専用の内部状態を新設しない方針で単純化を検討すること。

- 隠しファイルの表示/非表示
- サイドバー/フォルダー一覧の並び順
- 行番号の表示/非表示
- ソースモード/プレビューモードのどちらで開くか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 --hidden-files / --no-hidden-files 相当のオプションで隠しファイル表示を制御できる
- [ ] #2 並び順を指定するオプションでサイドバー/フォルダー一覧の並び順を制御できる
- [ ] #3 --line-numbers / --no-line-numbers 相当のオプションで行番号表示を制御できる
- [ ] #4 --source / --preview 相当のオプションでソースモード/プレビューモードを指定して開ける
- [ ] #5 オプション未指定時は既存のデフォルト挙動・保存済み設定が維持される
<!-- AC:END -->
