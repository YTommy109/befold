---
id: TASK-45
title: apply() の early-return が loadFailed をリセットしない
status: To Do
assignee: []
created_date: '2026-07-17 05:09'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.apply() でハッシュと fileType が一致して早期リターンする際、loadFailed フラグがリセットされない。チャンク読込エラー後に同一内容でファイルが再保存されると、エラーバナーが永続しリトライ手段もなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 apply() の early-return パスで loadFailed が false にリセットされ、chunkSession が適切に処理される
- [ ] #2 チャンク読込エラー後に同一内容で再読込した際にエラーバナーが消えることをテストで確認
<!-- AC:END -->
