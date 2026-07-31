---
id: TASK-232
title: viewer.js の showLineNumbers 既定解釈の不一致と body クラスリスト重複を是正する
status: To Do
assignee: []
created_date: '2026-07-31 09:15'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 390000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit/Resources/viewer.js で showLineNumbers 省略時の解釈が反転している: buildLineNumberRows (:311) は !== false で既定 true、renderCodeHtml (:335) は === true で既定 false。renderCsvSourceHtml (:508) は引数 1 個で wrapWithLineNumbers を呼び緩い判定に依存して行番号ありになっている。既定を === true 側（明示）に統一し、:508 は true を明示する。挙動が変わりうるため CSV ソース表示の行番号テストで固定してから触る。併せて viewer-main.js:1583/:1618 の body クラス一覧 2 箇所の手写しを定数 + ヘルパー化する（新 type 追加時の更新漏れで前の型のスタイルが残るバグを防ぐ）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 showLineNumbers 省略時の解釈が 1 つの規則に統一され、既存の各表示（コード/CSV ソース）の行番号有無が変わらないことがテストで固定されている
- [ ] #2 body クラスの付け替えが単一の定数リストとヘルパー経由になっている
<!-- AC:END -->
