---
id: TASK-485
title: 文書内の目印を検索窓と同じ UI で前後移動できるようにする
status: To Do
assignee: []
created_date: '2026-08-14 13:16'
labels: []
dependencies: []
priority: medium
type: feature
ordinal: 711000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

現在、文書内を前後移動できる UI は検索窓（find bar）だけで、これは
`viewer-src/find.js` の中で n/N 表示・前後移動・現在位置ハイライトを完結して持っている
（Swift は open/next/prev の 3 コマンドを投げるだけ。`BefoldKit/ViewerBridge.swift:33-35`）。

一方で、ユーザーが移動したい対象は検索語だけではない。

- ソースコード表示: 関数定義へのジャンプ
- 差分表示: 前後の変更ブロックへのジャンプ
- Markdown / HTML レンダリング: h2 / h3 見出しへのジャンプ

これらはいずれも「文書順に並んだ目印の列を作り、n/N を出し、前後へ動かし、
現在位置を目立たせてスクロールする」という同じ形をしている。検索と別々に作ると
UI もキーバインドも三重化するため、**列挙だけを対象ごとに差し替える共通基盤**として
実装する。

## 実現可否の評価（調査済み）

| 対象 | 可否 | 根拠 |
| --- | --- | --- |
| Markdown 見出し | ◎ | `markdown.js:81 assignHeadingIds` で h1-h6 に id 付与済み。`querySelectorAll("h2,h3")` で文書順に列挙できる |
| 差分の変更ブロック | ○ | インラインは `tr.diff-line.diff-add/diff-del`（`diff-html.js:132`）。ただし左右分割では tr でなく側セルにクラスが付く（:221-）。ハンク区切り `tr.diff-hunk` は `GitDiffReader` が `-U1000000` を使うためファイル全体で 1 個になりうる（`GitDiffReader.swift:101`）ので、ハンクではなく連続する add/del のグルーピングが必要 |
| ソースの関数定義 | △ | 行の DOM（`table.code-table` の `tr`、`code-html.js:128`）はあるが意味情報が無い。hljs のトークン span か行テキストの正規表現でヒューリスティックに拾う必要がある。さらに `StringChunkReader`（1000 行 / 1MB 単位）で未読み込みの範囲は DOM に存在しない |
| HTML レンダリングの見出し | 要判断 | `renderers.js:78` は iframe srcdoc に流し込むため親から直接列挙できない。same-origin なので `contentDocument` 経由は理屈上可能（`renderers.js:90` に前例あり）。スコープに含めるかを設計時に決める |

## 進め方

サブタスクに分割する。CLAUDE.md の規定に従い、**サブタスクごとに `/review-design` を 1 回回してから**実装に着手すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 共通のジャンプ基盤の上に、見出し・差分・関数定義の 3 種類が実装されている
- [ ] #2 検索窓と同じ形で「現在位置 / 総数」が表示され、前後移動ができる
- [ ] #3 段階読み込み（チャンク）中は、検索窓と同じく総数が確定していないことがユーザーに伝わる
- [ ] #4 対象が存在しない表示モードではメニュー項目・ショートカットが無効化される
<!-- AC:END -->
