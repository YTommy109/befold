---
id: TASK-351
title: 再読込での git 状態取り直しテストが、割り当て前のタスクを await している
status: Done
assignee:
  - '@claude'
created_date: '2026-08-07 02:57'
updated_date: '2026-08-07 02:57'
labels:
  - test
  - flaky
dependencies: []
priority: high
type: bug
ordinal: 505100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`ViewerWindowControllerGitStatusTests`「表示中ファイルの再読込で git 状態を取り直す」（:62）が、TSan 付きの main CI（run 31142291812）で `reader.callCount → 2 > callsBeforeReload → 2` で失敗した。

原因: `controller.store.onContentReloaded?()` を叩いた直後に `await controller.sidebar.pendingGitStatusTask?.value` している。再読込の契機がまだタスクを差し込む前だと、この await は「今は無い（または前回の完了済み）」を待って即座に戻り、取り直しが起きる前に測ってしまう。負荷が高いほどこの窓が広がる。

タスクハンドルを待つのではなく、観測したい効果（取得回数の増加）が現れるまで待つべきだった。

再現状況: ローカルでは単体 5 回・TSan 全体実行 1 回（1182 件 67.7 秒通過）とも再現しない。CI のランナー負荷でのみ観測。

なお TASK-346 の変更で差分取得のタスク数が増えており（TASK-349）、メインアクターの混雑が増したことでこの既存の競合が顕在化した可能性がある（未確認。ローカルで再現しないため因果は示せていない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 テストがタスクハンドルではなく、取り直しが観測できたことを待っている
- [ ] #2 TSan 付きの CI で再発しない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-07: `onContentReloaded?()` の直後に `waitUntilOnMainActor { reader.callCount > callsBeforeReload }` を挟み、観測できる効果を待ってから `pendingGitStatusTask` の完了を待つ形にした。

検証: 単体実行 5 回で pass=5。ローカルでは修正前も通っていたため、この修正で落ちなくなったことはローカルでは示せない（CI のランナー負荷が要る）。AC#2 はマージ後の TSan ジョブで確認する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
タスクハンドルの await を、取り直しが観測できるまでの待機に置き換えた。再読込の契機がタスクを差し込む前に await すると即座に戻り、取り直し前に測ってしまう競合だった。
<!-- SECTION:FINAL_SUMMARY:END -->
