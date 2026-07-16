---
id: TASK-14
title: チャンク境界をまたぐブロックコメント・複数行文字列のハイライトが崩れる
status: To Do
assignee: []
created_date: '2026-07-16 00:54'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/195'
type: bug
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
appendChunk がチャンクごとに highlight.js を初期状態で実行するため、チャンク境界をまたぐブロックコメントや複数行文字列の継続部分が通常コードとして誤ハイライトされる。全量描画パスでは問題なく追記パスだけで起きる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 hljs の continuation 状態がチャンク間で引き継がれている
- [ ] #2 ブロックコメントがチャンク境界をまたいでも正しく着色される
<!-- AC:END -->
