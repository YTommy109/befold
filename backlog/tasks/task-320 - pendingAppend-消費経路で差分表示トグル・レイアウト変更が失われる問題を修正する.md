---
id: TASK-320
title: pendingAppend 消費経路で差分表示トグル・レイアウト変更が失われる問題を修正する
status: Done
assignee: []
created_date: '2026-08-05 16:07'
updated_date: '2026-08-05 17:16'
labels:
  - feature-gate
  - diff-view
dependencies: []
priority: medium
type: bug
ordinal: 504000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 のコードレビュー（/code-review high・CONFIRMED）で検出。

再描画要否の判定は RenderedStateMirror の全体比較（ViewerRenderer+ContentUpdate.swift:214 付近）に置き換えられ diffState も自動的に対象へ入ったが、その手前の pendingAppend 早期リターン経路（ViewerRenderer+ContentUpdate.swift:179-199）が使う canConsumePendingAppend（ViewerRenderer+RenderHelpers.swift:159-168）は diffState を比較していない。このため diffState が変わった updateContent サイクルが applyAppend として消費されると、setDiff / setDiffLayout が JS へ送られず rendered.diffState が古いまま残る。canConsumePendingAppend の showLineNumbers チェックがまさに同型の「トグルが 1 サイクル失われる」穴をガードしており、diffState だけ漏れている。

症状: truncated ファイルで差分表示中に、loadMoreLines のチャンクが pendingAppend に積まれたタイミングで「変更を表示」OFF や Cmd+Ctrl+Shift+J のレイアウト切替を行うと、画面は古い差分/レイアウトのまま、View メニューのチェックだけ新状態になる。次の無関係な再描画イベントまで訂正されない。

修正: canConsumePendingAppend の比較に diffState を追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 pendingAppend が積まれた状態で差分表示トグル・レイアウト切替を行っても、画面が新しい状態に更新される
- [x] #2 diffState 不変のときのチャンク追記は従来どおり append 経路を通る（全再描画に退化しない）
- [x] #3 回帰テストを追加し、修正を戻すと失敗することを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 単純化の検討（実装前）

指摘は「canConsumePendingAppend の比較に diffState を足す」だったが、それは列挙式の判定にもう 1 項目足す形で、TASK-315.3 が updateContent 側で「列挙だとミラーへフィールドを足したとき判定側の追加だけ漏れる」と書いて捨てた形そのもの。同じ穴が同じ理由でこちらに残っていたのが今回の bug なので、**兄弟箇所も同じ解法（ミラー全体比較）へ揃える**方針に変えた。

追記経路が JS へ送るのはチャンクと切り詰め状態だけ、という事実から判定を導いた:

> 追記が正しく更新できる 2 つ（contentRevision と truncation）を除いて、更新後の状態が描画済みと一致しているときだけ消費してよい

これによりミラーへ将来フィールドが増えても自動的に判定へ入る。

## 修正

- `PendingAppendCheck` 構造体を削除（function_parameter_count 対策の入れ物だったが不要になった）
- `canConsumePendingAppend(_:incoming:rendered:)` へ変更し、incoming ミラーの contentRevision と truncation を rendered のものへ揃えてから `==` で比較
- updateContent の `incoming` 構築を pendingAppend 判定より前へ移動し、2 つの判定が同じ値を使うようにした（判定が 2 箇所ある以上、片方だけ別の作り方をすると再び食い違う）

## 検証

- `swift test` 1149 green
- **テストが空振りしていないことを確認**: 比較から diffState を除外（`comparable.diffState = rendered.diffState`）すると、新規 2 ケース「差分トグルが同じサイクルに合体したら全文 render」「差分レイアウトの変更も全文 render」だけが落ちる（`(canConsume → true) == (testCase.expected → false)`）。戻して再度 green
- テストは 4 ケースのタプル配列から 7 ケースの構造体配列へ書き換えた（直近描画から 1 点だけ動かす形。差分の本文・レイアウト、ソース表示切替のケースを追加）
- swiftformat --lint: 0 件 / swiftlint: 変更 3 ファイルとも main とのベースライン差分ゼロ
- 全体実行で ViewerWindowControllerToolbarTests が 1 度落ちたが、単独・再実行では通るため既知の不安定さ（TASK-327 に追記）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
pendingAppend 消費可否の判定が diffState を見ておらず、チャンク追記と同じサイクルで起きた差分トグル・レイアウト変更が追記経路に吸収されて失われていた。項目を 1 つ足すのではなく、updateContent 側と同じミラー全体比較へ揃え（追記で更新できる contentRevision と truncation だけを除いて一致するか）、PendingAppendCheck を削除して incoming ミラーを 2 つの判定で共有する形にした。ミラーへフィールドが増えても自動的に判定へ入る。検証は swift test 1149 green と、比較から diffState を外すと新規 2 ケースだけが落ちることの実測、lint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
