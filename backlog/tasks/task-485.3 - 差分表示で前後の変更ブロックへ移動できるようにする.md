---
id: TASK-485.3
title: 差分表示で前後の変更ブロックへ移動できるようにする
status: To Do
assignee: []
created_date: '2026-08-14 13:18'
updated_date: '2026-08-17 09:27'
labels: []
milestone: m-6
dependencies:
  - TASK-485.1
parent_task_id: TASK-485
priority: medium
type: feature
ordinal: 714000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

差分表示は行ごとに `tr.diff-line.diff-add / .diff-del / .diff-context` を持つ
（`viewer-src/diff-html.js:132 diffRow`）。連続する add/del をひとまとまりの
「変更ブロック」として畳めば、前後移動の対象列が作れる。

## 実装上の落とし穴（調査済み）

- **ハンク単位では使えない。** `tr.diff-hunk` の区切り行（:147）は存在するが、
  `GitDiffReader` が `-U1000000` を使うためファイル全体が 1 ハンクになりうる
  （`BefoldKit/GitDiffReader.swift:101` のコメント）。さらに先頭ハンクには
  区切り行を置かない（:162-163）。**連続する変更行のグルーピングで数えること。**
- **左右分割（`renderSideBySideDiffHtml` :221）では `tr` に diff-add/diff-del が付かない。**
  クラスは側セル `td.diff-side.diff-add/.diff-del` に付く。インラインと分割で
  列挙のセレクタが変わるため、レイアウト切り替え（`ViewerDiffBridge.setDiffLayout` :27）
  のたびに列を作り直す必要がある。
- 差分表示中は `appendChunk` が DOM 追記をスキップする（`render.js:176`）ため、
  ソース表示と違って部分読み込みの考慮は不要（要確認）。

## 論点

- 分割表示で左右どちらを基準に数えるか（両側で対応する行を 1 ブロックとみなす）
- 変更ブロックのハイライト表現。行単位のハイライト CSS は現状無い
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 インライン差分で、前後の変更ブロックへ移動できる
- [ ] #2 左右分割差分でも同じ数・同じ順序で移動できる
- [ ] #3 レイアウトを切り替えても現在位置が保たれる、または明示的に先頭へ戻る（どちらかを決めて実装する）
- [ ] #4 ファイル全体が 1 ハンクになる差分でも、変更ブロック数が正しく数えられる
- [ ] #5 連続変更行のグルーピングに JS のユニットテストがある
- [ ] #6 行（tr）のハイライトが border-collapse 下でも四辺とも描かれることを、スナップショットで確認している（TASK-485.1 の実測では tr への outline は上下辺しか出なかった。JumpTarget.highlight は複数要素を取れるので、行ではなく各セルへ当てる等の対処を選ぶこと）
<!-- AC:END -->
