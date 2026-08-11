---
id: TASK-437
title: refreshesDiffWhenGitStatusApplied が CI で待機上限に達して落ちるのを直す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 14:42'
updated_date: '2026-08-11 04:58'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 103500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowControllerDiffTests の「git 状態が反映されたら差分も取り直す」（refreshesDiffWhenGitStatusApplied、ViewerWindowControllerDiffTests.swift:164）が CI で待機上限に達して落ちる。gitStatusDidApply() 後の差分取得は detached の utility タスクを経由するため、全スイート並列実行では協調スレッドの空き待ちになる。テスト側は既に既定 10 秒では足りず timeout: testTimeout(fallback: 60) まで伸ばしてあるが、それでも足りていない。

実測（2 例、いずれも別コミット・別ジョブ）:
- main: run 31388117702 / thread-sanitizer ジョブ（BEFOLD_TEST_TIMEOUT_SECONDS=120）。『waitUntilOnMainActor が 120.0 seconds 以内に条件を満たさなかった』でこの 1 件だけ失敗し、1389 tests / 202 suites の run が exit 1。
- PR #472: run 31398484119 / build-and-test ジョブ（同 60）。同じ箇所・同じメッセージで 60 秒に達して失敗。

予算を伸ばす方向はすでに 2 段（10→60→120）踏んでおり、120 秒でも落ちているため上限引き上げでは解決しない。取得経路（detached utility タスク）をテストから待てる形にする、優先度を上げる、あるいはテスト側で取得完了を観測可能な同期点に変える、といった構造側の対処を検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CI の build-and-test と thread-sanitizer の双方で refreshesDiffWhenGitStatusApplied が待機上限に達しないこと（連続 3 回の CI 実行で確認する）
- [x] #2 対処が『待機予算を伸ばす』だけになっていないこと。取得経路またはテストの同期点を変えた理由を Implementation Notes に残す
- [x] #3 同じ経路に依存する他のテスト（ViewerWindowControllerDiffTests の他ケース）も同じ形で待っているなら併せて直す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 原因: refreshDiff() が反映を fire-and-forget の Task で行うため、テストから取得完了を待つ手段が store.diffText のポーリングしか無い。予算(10→60→120秒)を伸ばす対処はここまで 2 段踏んで失敗している。
2. 単純化の検討: GitDiffLoader.diff は既に Task を返しており、GitDiffLoaderTests はそれを await して決定的に測っている。コントローラ側だけが Task を捨てているのが非対称。新しい状態や通知機構を足さず、既に存在する Task を保持して露出するだけで同期点になる。
3. ViewerWindowController に diffRefreshTask: Task<Void, Never>? を持たせ、refreshDiff() が生成した反映タスクを代入する。
4. ViewerWindowControllerDiffTests の diff 取得を待つ 2 ケース(refreshesDiffWhenGitStatusApplied / refreshesDiffWhenSwitchingToDiffMode)を await controller.diffRefreshTask?.value へ置換し、待機予算を撤廃する。
5. スイートへ testTimeLimit() を付け、万一のハングは予算ではなくスイート打ち切りで止める(ViewerWindowManagerDiffTests と揃える)。
6. swift test で該当スイート・全体を確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: refreshDiff() が作る「取得結果を store へ書き戻すタスク」を ViewerWindowController.diffRefreshTask に保持し、テストはそれを await する形へ変えた。

なぜ予算を伸ばす方向を採らなかったか(AC#2): 完了の観測点は書き戻しタスクにしか無く、それを捨てていたため待つ側は store.diffText のポーリングしか手が無かった。取得が Task.detached(priority: .utility) を通る以上、全スイート並列実行での待ち時間は負荷次第で伸び、壁時計の予算では原理的に上限を決められない(10→60→120 秒と伸ばして 120 でも落ちた)。GitDiffLoader.diff は既に Task を返しており GitDiffLoaderTests はそれを await して決定的に測っていたので、非対称だったコントローラ側を同じ形へ揃えるだけで済んだ(新しい状態・通知機構は足していない)。

副次: 取得を起こさなかった契機(guard の早期 return)では diffRefreshTask を nil にする。古い取得の完了を「この契機の完了」と取り違えないため。
併せて ViewerWindowControllerDiffTests へ testTimeLimit() を付け、ハングはテスト側の予算ではなくスイート打ち切りで止める(ViewerWindowManagerDiffTests と同じ扱い)。

AC#3 の確認: 同経路(diff 取得の完了)を待っていたのは refreshesDiffWhenGitStatusApplied と refreshesDiffWhenSwitchingToDiffMode の 2 件で、両方を await へ置換した。同ファイルの他の waitUntilOnMainActor(:203/:236/:252)はコンテンツロード確定(store.fileType / filePath)を待つ別経路のため対象外。ViewerWindowManagerDiffTests は壁時計予算を持たない waitForDeliveryOnMainActor で待っており、今回の失敗モードには当たらない。

検証: swift test 全体を 3 回連続実行し、いずれも 1399 tests / 205 suites すべて成功(exit 0)。変更 3 ファイルの swiftlint 違反 0 件。

AC#1 の検証状況:
- CI build-and-test: PR #476 で 3 回連続 pass（run 31456906265 の attempt 1/2/3、4m59s / 5m10s / 3m07s）。
- CI thread-sanitizer: PR では起動しない（.github/workflows/ci.yml:139 で main への push と nightly に限定）。よってマージ前に CI 上の 3 回連続は取れない。
- 代わりにローカルで CI 相当（swift test --sanitize=thread、BEFOLD_TEST_TIMEOUT_SECONDS=120）を実行した。全体実行で対象 2 件とも成功し、所要は 63.3 秒 / 63.4 秒。ThreadSanitizer の競合警告 0 件。この 63 秒という実測が本件の失敗モードそのもので、旧来のポーリング待ち（fallback 60 秒）は予算の境界上で走っていたことになる。
- 同じくローカル TSan で対象スイートのみに絞った実行を 3 回連続で成功（各 1.18 秒）。
- ローカル TSan の全体実行は完走できない。ViewerRendererContentUpdateIntegrationTests / ViewerRendererOneShotIntegrationTests / ViewerRendererZoomIntegrationTests の 3 スイート（いずれも WKWebView を実際に動かす）がハングし、1399 件中 1395 件・205 スイート中 202 スイートまで進んだところで止まる。本変更が触る経路ではなく、TSan 無しの全体実行 3 回ではこれらも含め全件成功しているため、ローカル TSan 環境側の問題と判断した。CI の thread-sanitizer ジョブでの確認はマージ後の main push に委ねる。

AC#1 確定（マージ後の main CI: run 31459217057 を 3 回実行）:
- 3 回とも build-and-test / thread-sanitizer の双方が success。
- thread-sanitizer ジョブで対象テストが実際に走ったことをログで確認した。所要は 108.4 秒 → 191.7 秒（実行によって大きく振れる）。全体は 3 回とも 1399 tests / 205 suites 成功。
- この所要時間が本件の核心。旧来のポーリング待ちは CI の TSan 予算 120 秒で測っていたため、108 秒の実行は残り 12 秒、191 秒の実行は確実に予算切れになる。待機予算を伸ばす方向では解決しないことが実測で裏づけられた（AC#2 の根拠でもある）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
refreshDiff() が作る「取得結果を store.diffText へ書き戻すタスク」を ViewerWindowController.diffRefreshTask に保持し、テストは store.diffText のポーリングではなくそのタスクを await する形へ変えた。取得が Task.detached(priority: .utility) を通る以上、全スイート並列実行での所要は負荷次第で伸び、壁時計の予算では上限を決められない（10→60→120 秒と伸ばして 120 でも落ちていた）。GitDiffLoader.diff は既に Task を返しており GitDiffLoaderTests はそれを await して決定的に測っていたため、非対称だったコントローラ側を揃えるだけで済み、新しい状態や通知機構は足していない。併せて、取得を起こさなかった契機では diffRefreshTask を nil にし、スイートへ testTimeLimit() を付けてハングはスイート打ち切りで止める形にした。検証: マージ後の main CI（run 31459217057）を 3 回実行し、build-and-test / thread-sanitizer とも 3 回連続で success。TSan ジョブ内で対象テストは 108.4〜191.7 秒かかって成功しており、旧来の 120 秒予算では落ちる実行が実際に含まれる。
<!-- SECTION:FINAL_SUMMARY:END -->
