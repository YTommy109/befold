---
id: TASK-347
title: 差分の種別ゲートのテストが、無関係なファイルへの取得まで数えている
status: Done
assignee:
  - '@claude'
created_date: '2026-08-07 01:46'
updated_date: '2026-08-07 01:55'
labels:
  - test
  - flaky
dependencies: []
priority: high
type: bug
ordinal: 505500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

`ViewerWindowControllerDiffTests`「ファイル切替直後の取得契機でも切替先の種別でゲートする」（:241）が実行順に依存して失敗する。

実測（2026-08-07、同一マシン、単体実行）:
- origin/main: 5 回中 4 回失敗（callCount 1, 1, 2, 1）
- TASK-346 のブランチ: 5 回中 5 回失敗（callCount 2）
- 全体実行はこの失敗を隠す（ローカル 2 回とも 1182 件通過）が、CI の build-and-test では落ちた

## 原因（実測で確定）

**起票時に書いた「プロダクションのゲートが遅れて追従する store.fileType で判定している」は誤り。**`ViewerWindowController.swift:730` は既に `FileType(url: fileURL).supportsDiffDisplay` で URL から同期に判定しており、TASK-338 で対処済みだった。

RecordingDiffReader に要求 URL を出力させて実測したところ、数えられていた取得は 2 件とも **`note.swift`（切替元）** で、`table.csv`（切替先）への取得は 1 件も無かった。切替先のゲートは正しく効いている。

欠陥はテスト側にある。`#expect(reader.callCount == 0)` は取得の**総数**を測っており、切替前の `.swift` に対する**正当な取得**まで数えてしまう。その回数は契機の重なり方で変わるため、結論が実行順に左右される。TASK-346 で取得までの await のホップ数が減り、セットアップの 2 契機が合流しなくなったことで回数が 1 から 2 に増えた（合流しないこと自体は正しい。別の契機は別のツリーを読む必要がある）。

守りたいのは「切替先へ git を起こさないこと」であり、「git を一度も起こさないこと」ではない。測るものと守るものがずれていた（`/review-design` チェックリスト項目 7）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 当該テストが「切替先のファイルへ取得を要求していないこと」を測っている（取得の総数ではない）
- [x] #2 当該テストが単体実行 10 回で失敗しない
- [x] #3 URL 由来の種別ゲート（ViewerWindowController.swift:730）を store.fileType 由来へ戻すと当該テストが落ちる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RecordingDiffReader に要求 URL の記録（`requestedFiles`）を足す。件数だけでは「どのファイルに git を起こしたか」が分からない。
2. 当該テストのアサートを `reader.callCount == 0` から `reader.requestedFiles.contains(csv) == false` へ変える。
3. 単体実行 10 回で失敗ゼロを確認する。
4. URL 由来のゲートを `store.fileType` 由来へ戻すと落ちることを確認する（テストが検知能力を持っていることの担保）。
5. 全体実行と CI で確認する。

プロダクションコードは変更しない。調査の結果、ゲートは既に正しい（TASK-338）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-07 実測:

- 要求 URL を出力させたところ、数えられていた取得は 2 件とも `note.swift` で、`table.csv` への取得は 0 件だった。プロダクションのゲートは正しく効いており、起票時の見立て（ゲートが store.fileType 由来）は誤りだった。TASK-338 で既に URL 由来へ移されている（ViewerWindowController.swift:723-730 のコメントに経緯あり）。
- 修正後、単体実行 10 回 → pass=10 fail=0。
- 検知能力の確認: `supportsDiffDisplay` を `store.fileType.supportsDiffDisplay` へ戻すと 5 回中 5 回失敗。戻すと通る。
- 全体実行: 1182 tests passed（22.0 秒）。

プロダクションコードは 1 行も変更していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RecordingDiffReader に要求 URL の記録を足し、当該テストのアサートを「取得の総数がゼロ」から「切替先のファイルへ取得を要求していない」へ変えた。実測の結果、プロダクションの種別ゲートは TASK-338 で既に URL 由来になっており正しく効いていた（数えられていた取得は 2 件とも切替元の .swift）。欠陥はテストが守りたいものと違うものを測っていた点にあり、プロダクションコードは変更していない。単体実行 10 回で失敗ゼロ、ゲートを store.fileType 由来へ戻すと 5 回中 5 回落ちることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
