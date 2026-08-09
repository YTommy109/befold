---
id: TASK-390
title: スクロール位置の保存粒度を再検討する（複数ウィンドウで後勝ちになる）
status: To Do
assignee: []
created_date: '2026-08-09 10:13'
labels: []
dependencies:
  - TASK-382
priority: medium
type: bug
ordinal: 517000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0002 の「状態の所在」の基準（TASK-382 で追加）を当てた結果の逸脱。

スクロール位置は ScrollPositionStore が (パス, rendered|source) をキーにアプリ全体で共有し UserDefaults へ永続化する（BefoldApp/befold/App/ScrollPositionStore.swift:10-15,19-26,34-39）。同一ファイルを 2 つのウィンドウで開くと、両者が同じキーへ書き込む。

現状の緩和策は「書き込みを操作した 1 窓に限る」こと（ViewerWindowController.mirrorDisplayMode はスクロール位置を保存しない。理由は ViewerWindowController.swift:727-730 のコメントが自認）。しかしこれは同期の瞬間だけを守るもので、2 窓がそれぞれ独立にモード切替・ファイル切替を行えば同一キーへ順に上書きされ後勝ちになる。復元側（ViewerContentView.swift:41,95 → ViewerWebView.swift:53,89）は同じキーから読むため、別ウィンドウのスクロール位置が引き継がれうる。

論点: スクロール位置は本当に「文書の性質」か。ADR 0002 の基準に照らすと、同一ファイルを 2 窓で開いて別々の場所を読んでいるのは食い違いではなく正常な使い方に見える。そうであればこれは「窓の操作履歴」に属し、粒度は窓ごと・非永続（あるいは窓ごと × セッション復元のみ）が正しい。

設計で決めること:
- 窓ごとへ移すのか、(パス, モード) 単位の永続を維持したまま最後に閉じた窓の値を復元用に残すのか
- 変更する場合、既存キー ViewerScrollPositions.rendered / .source の扱い（CLAUDE.md「UserDefaults キーの廃止・改名」の節のチェックリストを通すこと）
- ウィンドウ復元（SessionStore）との関係

着手前に /review-design を回すこと（値の持ち方と粒度を変える変更のため）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一ファイルを 2 つのウィンドウで開いて別々の位置までスクロールしても、互いのスクロール位置を壊さない
- [ ] #2 決めた粒度が破れたら落ちるテストがある
- [ ] #3 保存キーを変更した場合、CLAUDE.md の移行チェックリスト（旧キーの読み手の洗い出し・移行の可否の明示・defer での削除・3 ケースのテスト）を満たしている
<!-- AC:END -->
