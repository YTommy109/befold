---
id: TASK-620.5
title: Bookmark Editor の「名前を変更」を「別名」の操作として表示し、別名を付けてもファイル名が分かるようにする
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-13 11:43'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 815000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
管理パネルのブックマーク行の右クリックメニューは `bookmarks.manager.renameAlias` で、表示は「名前を変更…」/「Rename…」、入力 alert のタイトルは「ブックマークの名前」/「Bookmark Name」になっている。実際に変わるのはブックマークの表示名（`BookmarkEntry.alias`）だけでファイルは改名されないのに、ファイル自体の改名と誤解される。TASK-536 の設計文書では「別名を変更…」とする想定だった（`docs/superpowers/specs/2026-09-12-bookmark-management-design.md`）。

加えて、別名を付けると行の 1 行目が `displayName`（別名 ?? ファイル名）に置き換わり、2 行目は親ディレクトリのパスなので、**ファイル名がどこにも出なくなる**。何のファイルのブックマークか分からない。

Bookmarks メニュー（`BookmarksMenuController`）も表示名 = 別名、右列 = 親ディレクトリで同じ構造を持つ。本タスクの対象はパネル。メニューも揃えるかは着手時にユーザーへ確認する。

l10n キーは意味が変わるので、キー名（`renameAlias`）の改名も検討する。`Localizable.xcstrings` はソートし直さない（CLAUDE.md）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 操作の表示が別名の設定であると分かる文言になっている（ja / en の両方。メニュー項目・alert タイトル・プレースホルダー）
- [ ] #2 別名を付けたブックマーク行に、別名とあわせて元のファイル名が表示される
- [ ] #3 別名の無いブックマーク行の表示が冗長にならない（ファイル名が 2 回出ない）
- [ ] #4 l10n の翻訳漏れが無い（/l10n-check）
<!-- AC:END -->
