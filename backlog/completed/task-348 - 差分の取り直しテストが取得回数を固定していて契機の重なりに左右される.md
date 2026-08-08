---
id: TASK-348
title: 差分の取り直しテストが取得回数を固定していて契機の重なりに左右される
status: Done
assignee:
  - '@claude'
created_date: '2026-08-07 02:37'
updated_date: '2026-08-07 02:38'
labels:
  - test
  - flaky
dependencies: []
priority: high
type: bug
ordinal: 505200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerWindowControllerDiffTests`「ソース表示へ切り替えたら差分を取り直す」（:284）が `#expect(reader.callCount == 1)` で取得回数を固定しており、契機の重なり方で結論が変わる。

TASK-346 のマージ後、main の build-and-test（run 31141164942）で失敗した。`reader.callCount → 2` == 1、かつ直前の `waitUntilOnMainActor { reader.callCount == 1 }` も予算切れ（0 → 2 へ飛んだ）。ローカルの単体実行 10 回では再現しない（全体実行の負荷が要る）。

原因: ソース表示への切替（ViewerWindowController.swift:677）と git 状態の反映（:521）はどちらも refreshDiff を呼ぶ。両者が同じターンに入れば合流して 1 回、別のターンに分かれれば別々の契機として 2 回になる。**契機ごとに読み直すのは仕様**（合流するのは同じ契機の兄弟要求だけ）。したがって取得回数はこの系の安定した性質ではなく、テストが固定してよい値ではない。

TASK-347 と同型（測るものと守るもののずれ）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 当該テストが「取り直しが起きたか」を測っている（回数を固定していない）
- [x] #2 レンダリング表示中は取得しない（0 件）ことの検証は維持されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-07: アサートを `reader.callCount == 1` の固定から `reader.callCount > 0`（取り直しが起きたか）へ変えた。レンダリング表示中の `#expect(reader.callCount == 0)` は維持している（こちらは「一度も起こさない」ことの検証で、契機の重なりに左右されない）。

検証: 単体実行 10 回で pass=10。全体実行 1182 件通過（21.1 秒）。ローカルでは修正前も 10/10 通っていたため、この修正で「落ちなくなった」ことはローカルでは示せない。CI の全体実行で確認する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
取得回数の固定をやめ、「取り直しが起きたか」で測る形に変えた。契機ごとに読み直すのは仕様であり、ソース表示への切替と git 状態の反映が別ターンに分かれれば 2 回になるため、回数はこの系の安定した性質ではない。
<!-- SECTION:FINAL_SUMMARY:END -->
