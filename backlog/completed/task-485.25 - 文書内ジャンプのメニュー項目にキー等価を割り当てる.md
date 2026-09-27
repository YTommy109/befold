---
id: TASK-485.25
title: 文書内ジャンプのショートカット（cmd+shift+F）を紹介サイトの表に載せる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-23 16:35'
updated_date: '2026-09-26 06:34'
labels:
  - jump
dependencies:
  - TASK-485.16
parent_task_id: TASK-485
ordinal: 799000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
キー等価の割り当て自体は TASK-485.28 で行った（cmd+shift+F。ジャンプ 3 種が排他なので 1 キー）。紹介サイトのショートカット表（site/src/lib/shortcuts.ts）は開発中機能のゲートを認識しないため、ゲート撤去（TASK-485.16）まで反映を待つ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 site/src/lib/shortcuts.ts と紹介サイトのショートカット表に反映されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
site/src/views/features.tsx の SHORTCUTS に ⇧⌘F（文書内ジャンプ）の行を ⌘F / ⌘G の直後に足した。site/test/shortcuts.test.ts の実装側一覧にあった『ゲート内なので表には載せない』というコメントを掲載済みの記述に直した。
検証: site の vitest 13 ファイル・440 件が通過、oxlint / oxfmt は指摘なし。キーを ⇧⌘J に変えると『表のショートカットが実装の割り当てに存在する』など 2 件が落ちることを確認した（表と実装の突き合わせが効いている）。
README の機能一覧への追記は AC の範囲外なので行っていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
紹介サイトのショートカット表に文書内ジャンプ（⇧⌘F）を載せた。表と実装の突き合わせテスト（site/test/shortcuts.test.ts）が通り、キーを変えると落ちることも確かめた。
<!-- SECTION:FINAL_SUMMARY:END -->
