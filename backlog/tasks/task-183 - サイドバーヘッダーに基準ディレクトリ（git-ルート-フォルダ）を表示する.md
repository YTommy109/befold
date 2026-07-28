---
id: TASK-183
title: サイドバーヘッダーに基準ディレクトリ（git ルート/フォルダ）を表示する
status: To Do
assignee: []
created_date: '2026-07-28 13:54'
updated_date: '2026-07-28 13:55'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-base-directory-indicator-design.md
ordinal: 263000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
相対パスのコピーと Quick Open がどのフォルダを基準にしているかをサイドバー上部に常時表示し、ユーザーが挙動を予測できるようにする。基準は既存の resolveGitRoot（gitFileIndex.repositoryRoot）と同じ gitRoot ?? workspaceRoot 規則で決定し、git ルート時と非 git フォールバック時をアイコンで区別する。情報表示のみ（クリック操作はスコープ外）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバー（FileListView）ヘッダー最上部に、アイコン＋基準フォルダ名の 1 行インジケータが表示される
- [ ] #2 git 管理下のファイルでは git ルートのフォルダ名と git を想起させるアイコンが表示される
- [ ] #3 git 管理外のファイルでは workspaceRoot のフォルダ名と通常フォルダアイコンが表示される
- [ ] #4 ツールチップに基準ディレクトリのフルパスと「Git リポジトリ／通常フォルダ」の区別が表示される
- [ ] #5 ツールチップ文言は Localizable.xcstrings に追加され翻訳漏れがない
- [ ] #6 基準ディレクトリの名前・種別・パスを算出する純粋ロジックが BefoldKit にあり、git あり/なし・ボリューム直下のエッジを含むユニットテストで検証されている
<!-- AC:END -->
