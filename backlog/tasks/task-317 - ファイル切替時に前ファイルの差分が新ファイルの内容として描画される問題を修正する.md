---
id: TASK-317
title: ファイル切替時に前ファイルの差分が新ファイルの内容として描画される問題を修正する
status: To Do
assignee: []
created_date: '2026-08-05 16:06'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 501000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

ViewerWindowController+Diff.swift:29 の refreshDiff は、新しいファイルへ切り替えた際に store.diffText をクリアせず非同期フェッチを開始する。このため差分表示 ON の状態で変更ありの A.swift から B.swift へ切り替えると、onContentReloaded 発火後に新しい contentRevision と古い diffText（A の差分）の組で diffState が評価され、JS 側レンダラが B のソース表示を A の差分 hunk で置き換える。B の git diff が完了するまで誤った内容が表示される（通常はフラッシュ、大きい/コールドなリポジトリでは数秒続く）。

同根の箇所: viewer-main.js:1682（_renderSource が content 引数を無視して diff を優先する）、ViewerWindowController+Diff.swift:18（失敗 guard 経路のみ同期クリアされる）。フェッチ開始前に diffText をクリアするか、diffText にどのファイルの差分かを持たせて照合する形で直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 差分表示 ON で変更ありファイル A から B へ切り替えたとき、A の差分が B の内容として描画される瞬間がない
- [ ] #2 切替直後〜フェッチ完了までの間は B のソース（または空の差分状態）が表示される
- [ ] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->
