---
id: TASK-485.4
title: ソースコード表示で関数定義へジャンプできるようにする
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
ordinal: 715000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

4 つの対象のうち**最も不確実性が高い**。ソース表示の DOM は
`table.code-table` の `tr`（`viewer-src/code-html.js:128 buildLineNumberRows`）で、
行という単位はあるが「この行は関数定義である」という意味情報は持っていない。
hljs のハイライト結果（`highlightCode` :17、`reflowSpanBalancedLines` :35）から
`span.hljs-function` / `span.hljs-title` 等のトークンを拾うか、行テキストへ
言語別の正規表現をかけるかのどちらかになる。

さらに `StringChunkReader`（`BefoldKit/StringChunkReader.swift:38`、1000 行 / 1MB 単位）で
段階読み込みされるため、**未読み込み範囲の関数定義は DOM に存在しない**。
既存の検索も同じ制約を持ち、「表示範囲内」ラベルで明示している
（`find.js:239` / `ViewerBridge.truncatedScript` :213）。同じ方針を踏襲する。

## 論点（`/review-design` で扱うこと）

- **検出方式を決める。** hljs トークン方式は言語ごとの語彙差に弱く、正規表現方式は
  多言語分の規則を抱えることになる。どちらを採るか、対応言語を絞るかを先に決める
  （まず Swift / JS / TS / Python など数言語に限定し、非対応言語では
  この機能を無効化する、という縮小版も選択肢）
- **偽陽性の扱い。** 呼び出しと定義の区別、コメント・文字列内の一致
- 総数が「読み込み済み範囲の数」でしかないことを、どうユーザーに見せるか
- ジャンプ先の表示（関数名を出すか、n/N だけか）

## 注意

前段の 3 タスクより不確実性が高いため、**着手時に方式を決めてから実装する**。
方式の決定は不可逆な設計判断になりうるので、必要なら ADR を残すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 対応すると決めた言語で、関数定義へ前後移動できる
- [ ] #2 非対応言語では機能が無効であることが操作前に分かる（メニューが無効など）
- [ ] #3 読み込み済み範囲だけを数えていることがユーザーに伝わる
- [ ] #4 コメント・文字列内の紛らわしい行を定義と誤検出しないことをテストで示している
- [ ] #5 検出方式の選定理由が Implementation Notes または ADR に残っている
<!-- AC:END -->
