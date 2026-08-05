---
id: TASK-317
title: ファイル切替時に前ファイルの差分が新ファイルの内容として描画される問題を修正する
status: Done
assignee: []
created_date: '2026-08-05 16:06'
updated_date: '2026-08-05 16:38'
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
- [x] #1 差分表示 ON で変更ありファイル A から B へ切り替えたとき、A の差分が B の内容として描画される瞬間がない
- [x] #2 切替直後〜フェッチ完了までの間は B のソース（または空の差分状態）が表示される
- [x] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討（実装前）

指摘は refreshDiff（ViewerWindowController+Diff.swift:29）だったが、そこでクリアすると**同一ファイルの保存のたびに差分が消えて再表示される**ちらつきになる。切替とリロードを区別する新しい状態（直近の差分がどのファイルのものか）を足す案も検討したが、状態を増やさずに済む絞り込み点があった。

表示対象が変わる唯一の入口は `ViewerStore.openFile`（呼び出しは ViewerWindowController.swift:285 の初期表示と :455 の performFileSwitch の 2 箇所のみ）。差分は表示中ファイルに紐づく値なので、**store 自身が openFile で捨てる**のが最小で、切替経路を増やしても自動的に守られる。保存時の refreshDiff は経路が違うためちらつかない。

## 修正

ViewerStore.openFile の先頭で `diffText = nil`。あわせて diffText の doc コメントへ不変条件を書いた（値は常に現在のファイルの差分。着地時の URL 一致確認だけでは切替直後の残留を防げない = 開始時の無効化と着地時の確認は別物）。

## 検証

- `swift test` 1148 tests green（新規 1 件: 別ファイルを開くと前のファイルの差分を捨てる）
- **テストが空振りしていないことを確認**: `diffText = nil` を外すと当該テストだけが落ちる（`Expectation failed: (store.diffText → "@@ -1 +1 @@…")`）。戻して再度 green
- swiftformat --lint: 0 件
- swiftlint: origin/main を git archive で展開して同一 2 ファイルを測り、違反の種類・ファイルはベースラインと同一（File Length / Opening Brace / Type Body Length の 5 件。行数カウントのみ増）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ファイル切替時に前のファイルの差分が新しいファイルの内容として描画される問題を、表示対象が変わる唯一の入口である ViewerStore.openFile で diffText を捨てる形で修正した。指摘箇所（refreshDiff）でクリアすると同一ファイルの保存ごとにちらつくため、切替経路だけを通る絞り込み点を選び、新しい状態は足していない。着地時の URL 一致確認は既にあり、開始時の無効化と合わせて世代管理が両方向そろった。検証は swift test 1148 green（新規 1 件）と、クリアを外すと当該テストだけが落ちることの実測、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
