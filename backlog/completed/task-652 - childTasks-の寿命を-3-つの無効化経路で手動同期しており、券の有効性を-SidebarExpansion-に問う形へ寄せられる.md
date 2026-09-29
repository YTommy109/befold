---
id: TASK-652
title: childTasks の寿命を 3 つの無効化経路で手動同期しており、券の有効性を SidebarExpansion に問う形へ寄せられる
status: Done
assignee: []
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 09:38'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarExpansion.swift
priority: low
ordinal: 852000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27）の指摘。TASK-644 で「走行中の有効な取得だけを持つ」を不変条件にしたが、その維持はまだ `collapseFolder` / `reloadExpandedChildren` / `invalidateExpansion` の 3 経路と `loadChildren` の上書きで**手で**行っている（`SidebarTreePresenter.swift` の `childTasks` の doc がその 4 経路を列挙している）。このブランチでは「expansion と寿命を揃えるべき並走状態」の破れが 2 度出ている（dfeaf408 lastReveal / 9995a2b4 childTasks）。`.claude/CLAUDE.md`「同型のバグが 2 回目に出たら構造で塞ぐ … 判定の置き場所を変える」。

## 現状（検証済み）

- `SidebarExpansion.apply` は `generations[token.key] == token.generation, epoch == token.epoch` で有効性を判定している。同じ判定を外から問う API は無い。
- 券を無効にする経路が増えるたびに `childTasks` 側の掃除を書き足す必要があり、書き忘れると無効化済みの取得を `awaitSettled` が待ってハングする（TASK-644 と同じ失敗）。

## 方向

`childTasks` を `[String: (token, task)]` にし、`SidebarExpansion.isCurrent(_ token:)` を足す（`apply` 内のガードを 1 箇所へ切り出して共有）。`awaitSettled` は非 current の券を飛ばし、掃除は着地経路だけに残す。3 つの手動掃除は撤去する。TASK-644 のテスト（畳んだ配下の券が残ってもハングしない）はそのまま通ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `SidebarExpansion` に券の有効性を問う API があり、`apply` の判定と同じ実装を共有している
- [x] #2 `collapseFolder` / `reloadExpandedChildren` / `invalidateExpansion` から `childTasks` の手動掃除が消えている
- [x] #3 TASK-644 のハング再現テストが引き続き通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarExpansion.isCurrent(_ token:) を足し、apply のガードをそれ経由にする（判定 1 箇所）。ExpansionToken を Equatable にする（(generation, epoch) は invalidateAll で generation が 0 に戻っても epoch が進むので一意）。
2. childTasks を [String: (token: ExpansionToken, task: Task)] にする。
3. 掃除は着地経路だけ: 取得が返ったら、エントリの券が自分と同じなら外す（apply の受理とは無関係に。捨てられた取得も自分のエントリを片付ける）。その後 apply が受理したら組み直しを予約。
4. awaitSettled / pendingChildKeys は isCurrent な券だけを見る（無効化済みで止まったままの取得を待たない）。
5. collapseFolder / reloadExpandedChildren / invalidateExpansion から childTasks の掃除を撤去。
単純化の検討: 起票どおりの形が最小。childTasks 自体を消す案は awaitSettled に待つ対象が要るため不可。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design（2026-09-27）: 不変条件が「childTasks は有効な取得だけ」→「走行中の取得を持ち、読み手（awaitSettled / pendingChildKeys）が isCurrent で絞る」へ変わる。無効化済みのエントリは着地で自分を外すので、その担保として『捨てた取得が着地したら childTasks の実エントリが 0 になる』テストを足す（pendingChildKeys は isCurrent で絞るため測れない。実エントリ数の読み取り窓を別に置く）。他の項目は該当なし（判定は券の世代・epoch＝事実、fileprivate で外から再実装できない。高頻度経路なし。SidebarTreePresenter 378 行で増減ほぼなし）。

- 実装: SidebarExpansion.isCurrent を足し apply のガードをそれ経由に。ExpansionToken を Equatable に。childTasks は (token, task) を持ち、着地時に券が自分と同じなら外す（受理の有無に関わらず）。awaitSettled / pendingChildKeys は isCurrent で絞る。collapseFolder / reloadExpandedChildren / invalidateExpansion の掃除を撤去。
- 単純化: collapse の戻り値（捨てたキー）は唯一の読み手 collapseFolder が使わなくなったので削除。
- 検証: swift test --filter 'Sidebar|FileList|ViewerWindow' 594 件 pass（TASK-644 の collapsingParentDropsDescendantTasks 含む）。着地での片付けを受理後へ戻す変異で新しい retainedChildTaskCount の期待が落ちることを確認。swiftlint（変更 3 ファイル）0 件。
- 仕様文書: docs/dev に childTasks の記述は無く、振る舞いも変えていないので更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
券の有効性判定を SidebarExpansion.isCurrent に一本化し、childTasks の掃除を着地経路だけにした。無効化の 3 経路は childTasks を触らなくなり、awaitSettled は isCurrent な取得だけを待つ。無効化済みの取得が着地で自分を片付けるテストを追加（変異で落ちることを確認）。
<!-- SECTION:FINAL_SUMMARY:END -->
