---
id: TASK-485
title: 文書内の目印を検索窓と同じ UI で前後移動できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 13:16'
updated_date: '2026-09-26 06:35'
labels: []
milestone: m-6
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
- [x] #1 共通のジャンプ基盤の上に、見出し・差分・関数定義の 3 種類が実装されている
- [x] #2 検索窓と同じ形で「現在位置 / 総数」が表示され、前後移動ができる
- [x] #3 段階読み込み（チャンク）中は、検索窓と同じく総数が確定していないことがユーザーに伝わる
- [x] #4 ジャンプの目印が無い表示では ⇧⌘F が検索へ倒れ、ジャンプも検索もできない表示（フォルダー表示・HTML 直接ロード等）ではメニュー項目とショートカットが無効化される（TASK-485.28 / 485.31 で「無効化」から「検索へ倒す」へ設計を変えた）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 完了時の確認（2026-09-26）
サブタスク 12 件がすべて Done。stable ビルドでの露出は TASK-485.16 でゲートを撤去して行い、紹介サイトの表への掲載は TASK-485.25 で行った。

AC ごとの根拠:
- #1 viewer-src/jump-providers.ts に heading / changeBlock / functionDefinition の 3 プロバイダがあり、_mmdJump（jump.ts）の共通コントローラへ register している。
- #2 件数表示（mmd-jump-count の n/N）と前後移動・巡回は viewer-main-jump.test.ts『次へ・前へで循環する』ほかで担保。⌘G / ⇧⌘G でも前後に移動できる（TASK-485.34）。
- #3 段階読み込み中の「表示範囲内」ラベルは viewer-main-jump.test.ts『段階読み込み中は件数に表示範囲のラベルが付く』と viewer-main-jump-function.test.ts で担保。変更ブロックは常に全数が DOM にあるのでラベルを出さない（同『段階読み込み中でも表示範囲のラベルを出さない』）。
- #4 起票時の「対象が無ければ無効化」は、TASK-485.28 / 485.31 で「ジャンプが無ければ検索へ倒す」に変えたため、AC をその設計に合わせて書き直した。担保は ToggleBarCommandTests（検索へ倒れる）と ViewerMenuValidatorTests（.none で無効、canToggleJump を読む）。

Description にある『HTML レンダリングの見出し（iframe 内）』は対象外のまま（見出しジャンプは Markdown だけ / docs/dev/viewer-ui.md の目印の表）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
文書内の目印（見出し・差分の変更ブロック・関数定義）を、検索と同じ統合バーで前後に移動できるようにした。共通のジャンプ基盤の上に 3 種類のプロバイダを載せ、⇧⌘F で開閉し、Enter / ⇧Enter と ⌘G / ⇧⌘G で移動する。フィーチャーゲートを外して stable ビルドにも載せ、紹介サイトのショートカット表にも掲載した。
<!-- SECTION:FINAL_SUMMARY:END -->
