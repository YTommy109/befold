---
id: TASK-509
title: TSan ジョブで残っていた壁時計待機を loadTask の await へ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-17 04:34'
updated_date: '2026-08-17 05:16'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 739000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
thread-sanitizer ジョブ（push / schedule でのみ実行）が、コンテンツロードの着地を壁時計ポーリングで待つ 4 箇所で断続的に落ちている。

## 事実

- 失敗メッセージはすべて `waitUntilOnMainActor が 120.0 seconds 以内に条件を満たさなかった`。TSan の data race 報告は 0 件（run 31993974965 のログ全文を grep 済み）。
- 同じ 8 テストが 2026-08-15 の main 実行（run 31885189333）でも同じ形で落ちている。thread-sanitizer は push / schedule のみで走るため（.github/workflows/ci.yml:214）PR では検出できない。
- 失敗箇所は BefoldApp/befoldTests/ViewerWindowControllerDiffTests.swift:206 / 239 / 286 と ViewerWindowControllerDiffPendingTests.swift:120（preparePresentedMarkdown 内）。いずれも差分取得ではなく初回コンテンツロードの着地を待っている。ViewerWindowControllerDiffPendingTests.swift:58 の Expectation failed は、その待機がタイムアウトして前提が崩れた下流の症状。
- git のサブプロセスは起動していない（ViewerWindowControllerFixture が InMemoryFileReader / MockFileWatcher / テストダブルの gitFileIndex を注入）。ロジック上のハングは見つかっていない。
- waitUntilOnMainActor の締切は壁時計（BefoldTestSupport/Waiting.swift:124）。一方 swift test は 1603 テストをほぼ同時に開始しており（全テストが 04:21:04 に start、成功したテストも 185〜230 秒かかったと報告される）、120 秒の予算は操作の所要ではなくスイート全体の混雑時間を測っている。

## 同型の 2 回目である

backlog/completed/task-437 が同じ失敗メッセージ・同じジョブに対して「壁時計予算では上限を決められない」と結論し（予算を 10 → 60 → 120 と伸ばして 120 でも落ちた）、差分取得側だけを await task へ移行した。その AC#3 で今回の 3 箇所を「コンテンツロード確定を待つ別経路のため対象外」として明示的に残していた。CLAUDE.md の「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」に該当するため、予算をさらに伸ばす対処は採らない。

## 方針

待機そのものを消す。修正パターンは既にコードベースにあり、befoldTests/ViewerWindowControllerToolbarTests.swift:133-138 に「壁時計予算のポーリング(waitUntilOnMainActor)ではなく loadTask を await する」というコメント付きの実例がある（await controller.store.loadTask?.value）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerWindowControllerDiffTests.swift の 3 箇所と ViewerWindowControllerDiffPendingTests.swift の 1 箇所から、コンテンツロード着地を待つ waitUntilOnMainActor が消え、store.loadTask の await に置き換わっている
- [x] #2 befoldTests 全体を grep し、コンテンツロード着地を壁時計で待つ waitUntilOnMainActor が他に残っていないことを確認し、残す場合は理由を Implementation Notes に書く
- [x] #3 swift test がローカルで通る（失敗ゼロ、テスト名まで確認する）
- [x] #4 main へマージ後の thread-sanitizer ジョブが通ることを確認する（PR では走らないため、マージ後の run を必ず見る）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerWindowControllerDiffTests.swift の 4 箇所（206 / 239 / 255 / 286）と ViewerWindowControllerDiffPendingTests.swift の 1 箇所（120）で、コンテンツロード着地を待つ waitUntilOnMainActor を await store.loadTask?.value に置き換える。
2. 置き換えが空振り（loadTask が nil で素通り）していないことを見えるようにするため、await の直後に元の待機条件を #expect として明示する。
3. befoldTests 全体を grep し、コンテンツロード着地を壁時計で待つ箇所が他に残っていないことを確認する。
4. swift test / swiftformat / swiftlint を回す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

対象は 5 箇所（起票時に挙げた 4 箇所に加え、ViewerWindowControllerDiffTests.swift:255 の同型の待機も同じテスト内にあったため含めた）。いずれも await controller.store.loadTask?.value へ置き換えた。store.openFile → loadContent は MainActor 上で同期的に loadTask を代入し（ViewerStore+FileWatching.swift:20 / ViewerStore+Loading.swift:52）、状態の適用 apply() は その Task の中で行われる（ViewerStore+Loading.swift:60-73, 81-116）ため、await すれば着地が保証される。

置き換えが空振りしていないこと（loadTask が nil で await が素通りし、たまたま assertion が通っているだけ、という形）を見えるようにするため、await の直後に元の待機条件をそのまま #expect として残した。これが通ることが、await が実際に着地を待っている証拠になっている。

## 他に残る waitUntilOnMainActor（AC#2）

befoldTests 全体で 12 → 7 箇所に減った。残る 7 箇所はいずれもコンテンツロード着地ではない経路（git status の反映、サイドバー一覧の反映、ツールバーの色、repositoryRoot の解決、ViewerRenderer の解決中フラグ）を待っており、今回の失敗モードには該当しないため据え置いた。ViewerRendererContentUpdateIntegrationTests.swift:20-24 は逆に「時間ベースでは成立しない」ことが doc に明記済みで、既に yield ループへ移行している。

## 検証（実測）

- swift test: 1603 tests in 254 suites passed after 36.425 seconds（失敗 0、exit=0）
- 対象 2 スイート単体: 14 tests passed（置き換え後・#expect 追加後の 2 回とも）
- swiftformat（fix モード）: 対象ファイルに変更なし（0/16 files formatted）
- swiftlint: 全体 54 件で main のベースラインと同数、変更した 2 ファイルの指摘は 0 件

## AC#4 は未達（マージ後に確認が必要）

thread-sanitizer ジョブは push / schedule でのみ走るため（.github/workflows/ci.yml:214）、PR では検証できない。main へマージした後の run を必ず確認すること。過去 2 回（2026-08-15 の run 31885189333、2026-08-17 の run 31993974965）と同じ 8 テストが落ちないことを見る。

## AC#4 確認済み

マージ後の main の run [31996328512](https://github.com/YTommy109/befold/actions/runs/31996328512) で thread-sanitizer ジョブが 6m18s で成功した（前回までの失敗 8 件はゼロ）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TSan ジョブが waitUntilOnMainActor の壁時計 120 秒予算切れで断続的に落ちていた問題を、コンテンツロード着地を待つ 5 箇所を store.loadTask の await へ移すことで解消した。予算はスイート全体の混雑時間（成功したテストも 185〜230 秒と報告される）を測っており、伸ばしても解決しない（TASK-437 で 10 → 60 → 120 と伸ばして破れている）ため構造で塞いだ。await 直後に元の待機条件を #expect として残し、空振りしていないことを担保している。swift test 1603 件通過に加え、マージ後の main の run 31996328512 で thread-sanitizer ジョブの成功を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
