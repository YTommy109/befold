---
id: TASK-61
title: フォルダー選択時にプレビューエリアへフォルダー一覧を表示する
status: To Do
assignee: []
created_date: '2026-07-18 10:29'
updated_date: '2026-07-18 10:37'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-18-folder-preview-listing-design.md
  - docs/superpowers/plans/2026-07-18-folder-preview-listing.md
priority: medium
ordinal: 28500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーでフォルダーを選択しても、プレビューエリアは直前に開いていたファイルの内容を表示し続けており、フォルダーの中身を確認できない。設計は docs/superpowers/specs/2026-07-18-folder-preview-listing-design.md に、実装計画は docs/superpowers/plans/2026-07-18-folder-preview-listing.md にレビュー・承認済みで存在する。実装はこのプランに従って進める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーでフォルダーをシングルクリックで選択すると、プレビューエリアにそのフォルダー直下の一覧(フォルダー優先+名前順)が表示される
- [ ] #2 一覧の並び順・隠しファイル表示はサイドバーの現在の設定に従い、独自の固定値を持たない
- [ ] #3 一覧内の非対応ファイルの見た目・クリック時の扱いはサイドバーと同じ基準になる(除外・無効化はしない)
- [ ] #4 一覧内はシングルクリックで選択のみ、ダブルクリックでファイルを開く/サブフォルダーへ移動する
- [ ] #5 一覧内でのダブルクリックによる移動・オープンはサイドバー側の表示(選択ハイライト・カレントディレクトリ)にも反映される
- [ ] #6 フォルダーへダブルクリックで移動した際、最初のファイルを自動的に開く既存の挙動が廃止され、移動後は新しいフォルダーの一覧が表示される
- [ ] #7 戻る操作は既存の「..」行を使い、新規ナビゲーションUIは追加しない
- [ ] #8 zip アーカイブの中身表示は本タスクのスコープに含めない
<!-- AC:END -->
