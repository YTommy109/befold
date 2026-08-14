---
id: TASK-480.2
title: SidebarDisplayPreference を窓ごとのインスタンスへ移し、初期値供給を分離する
status: To Do
assignee: []
created_date: '2026-08-14 08:01'
labels: []
dependencies:
  - TASK-480.1
parent_task_id: TASK-480
priority: high
type: task
ordinal: 90200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在 SidebarDisplayPreference は全ウィンドウで 1 インスタンスを共有し(型の doc コメントに明記)、UserDefaults へ直接読み書きしている。これを窓ごとに 1 インスタンス持つ形へ変え、UserDefaults への読み書きは「新規ウィンドウ生成時に初期値を読む」「値の変更時に最新値として書き戻す」の 2 点に限定する。

既存キー(ShowHiddenFiles / ShowChangedFilesOnly / SidebarLayoutMode / SidebarSortOrder)は意味を変えずそのまま初期値として使うため、値の移行処理そのものは不要になる見込みだが、キーの意味が「全ウィンドウの現在値」から「新規ウィンドウの初期値」へ変わる。CLAUDE.md の UserDefaults キー節に従い、読み手の変化を洗って結論を Implementation Notes に残すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 SidebarDisplayPreference が窓ごとに 1 インスタンス生成される
- [ ] #2 既存の UserDefaults キー 4 つが新規ウィンドウの初期値として読まれる
- [ ] #3 いずれかの値を変更したウィンドウが、その値を UserDefaults へ書き戻す
- [ ] #4 既存キーの読み手の変化を洗い、移行の要否を明示的に決めた結論が Implementation Notes に記録されている
- [ ] #5 窓ごとに独立していることを担保するテストがある(2 窓を作り一方だけ変更しても他方が変わらない)
<!-- AC:END -->
