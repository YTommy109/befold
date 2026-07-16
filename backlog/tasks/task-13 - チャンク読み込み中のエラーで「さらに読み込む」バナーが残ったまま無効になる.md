---
id: TASK-13
title: チャンク読み込み中のエラーで「さらに読み込む」バナーが残ったまま無効になる
status: To Do
assignee: []
created_date: '2026-07-16 00:54'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/194'
type: bug
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
チャンクセッション途中で readNextChunk がエラーを投げると、バナーが表示されたまま反応しなくなりエラーも通知されない。handleLoadMoreLines が nil を受けて早期 return し truncatedScript(false) が JS に送られないため。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 エラー時にバナーが消える、またはエラーメッセージが表示される
- [ ] #2 truncation 状態の変化が JS へ伝搬される
<!-- AC:END -->
