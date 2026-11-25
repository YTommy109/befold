---
id: TASK-930.2
title: (b) ファイルを開く経路を「意図 → 本文 → サイドバー」の順に揃える
status: To Do
assignee: []
created_date: '2026-11-25T00:12:51Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 4。入口ごとに、意図を書く・本文を読み込む・サイドバーを合わせる順序がばらばらで、開き直しや引き継ぎで本文がフォルダー一覧のまま残る経路がある（コード読解で見つけた候補。未実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォルダー一覧を表示中の窓で、すでに開いているファイルを CLI・Finder・Quick Open から開き直すと、本文にそのファイルが出る（同じ URL への切り替えでも意図を書く）
- [ ] #2 元の窓の一覧を引き継いで新しいタブ・窓を開いたとき、新しいファイルが引き継いだ一覧に無くても、本文にフォルダー一覧が重ならない
- [ ] #3 文書内リンク・隣のファイルへの移動・サイドバーのファイル選択・本文の一覧からのファイル選択が、同じ順序の経路を通る（経路を 1 本にまとめるか、順序を破れない形にする）
- [ ] #4 上の各経路について、PreviewTarget の遷移に .folder が現れないことをテストで確かめる
<!-- AC:END -->
