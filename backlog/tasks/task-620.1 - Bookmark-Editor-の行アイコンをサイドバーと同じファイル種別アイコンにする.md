---
id: TASK-620.1
title: Bookmark Editor の行アイコンをサイドバーと同じファイル種別アイコンにする
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-13 11:42'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 811000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
管理パネルのブックマーク行は全行同じ SF Symbol `bookmark` を出しており、アイコンが情報を持っていない。サイドバーの `FileListEntryRow` はファイル種別のアイコンを出しているので、見た目と意味を揃えたい。

注意すべき制約: 行のコメントにあるとおり、`bookmark` にしたのは `NSWorkspace.icon(forFile:)` がディスク I/O を伴うため。管理パネルと Bookmarks メニューは「表示では stat しない」を約束している（応答しないマウント上のブックマークで待たされるため。`docs/dev/native-app-design.md` の `BookmarkManagerModel` / `BookmarksMenuController` の行）。サイドバーは列挙済みのローカルなエントリを描くので同じ API で問題にならないが、ブックマークは切断済みのボリューム上にもありうる。拡張子から `UTType` を引いてアイコンを得るなど、ファイルに触れない方法があるかを着手時に確かめる。ディレクトリのブックマーク（Finder からの D&D で追加できる）は拡張子だけでは種別が決まらない点も考慮する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ファイルのブックマーク行に、サイドバーで同じファイルに出るものと同じ種別のアイコンが出る
- [ ] #2 ディレクトリのブックマーク行にフォルダーのアイコンが出る
- [ ] #3 一覧の描画でブックマーク先へのファイルシステムアクセスが発生しない（約束を変える場合は、その判断と理由を native-app-design.md に記録する）
- [ ] #4 native-app-design.md の管理パネルの記述が実装に追随している
<!-- AC:END -->
