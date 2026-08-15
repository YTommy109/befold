---
id: TASK-485.2
title: Markdown レンダリング表示で h2 / h3 見出しを前後移動できるようにする
status: To Do
assignee: []
created_date: '2026-08-14 13:18'
updated_date: '2026-08-15 06:39'
labels: []
milestone: m-6
dependencies:
  - TASK-485.1
parent_task_id: TASK-485
priority: medium
type: feature
ordinal: 713000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

Markdown の見出しには既に id が振られている（`viewer-src/markdown.js:81 assignHeadingIds`、
slug 生成は :49 `slugifyHeading`、重複回避は :59 `uniqueHeadingSlug`）。
`#diagram-wrap.markdown-body` 配下を `querySelectorAll("h2, h3")` で走査すれば
文書順の見出し列がそのまま得られるため、**4 種類のうち最も実現が容易**。
共通基盤の最初の利用者としてここから着手する。

## 論点

- h2 と h3 を同じ列に混ぜるか、階層を表示に出すか（「2/7」だけで十分か、見出しテキストを出すか）
- 見出しへのスクロールは `scrollIntoView({block:"start"})` が自然だが、検索は
  `block:"center"` を使っている（`find.js:250`）。どちらに揃えるか
- h1 のみ / 見出しなしの文書での n/N 表示
- 対象は `#diagram-wrap` 配下のみ。iframe に隔離される HTML レンダリングは TASK-485.4 で扱う
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Markdown レンダリング表示で h2 / h3 を文書順に前後移動できる
- [ ] #2 現在位置と総数が検索窓と同じ形で表示される
- [ ] #3 見出しが 0 個の文書で操作しても壊れず、その旨が分かる
- [ ] #4 見出し列挙の純粋な部分（要素列 → 目印列）に JS のユニットテストがある
<!-- AC:END -->
