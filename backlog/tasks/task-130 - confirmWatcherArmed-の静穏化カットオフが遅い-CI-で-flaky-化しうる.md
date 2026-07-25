---
id: TASK-130
title: confirmWatcherArmed の静穏化カットオフが遅い CI で flaky 化しうる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:23'
updated_date: '2026-07-25 07:20'
labels:
  - test
  - ci
dependencies: []
priority: medium
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で PLAUSIBLE 判定。befoldTests/TestSupport.swift:40 で静穏化待ちが無制限ループから quiescePeriod * 20(デフォルト 0.3s で 6 秒)の固定カットオフに変更され、超過時に Issue.record でテストを fail させる。
thread-sanitizer ジョブのような遅い CI(BEFOLD_TEST_TIMEOUT_SECONDS=120 に延長される環境)では、arm プローブ書き込み+デバウンスされたイベントが quiescePeriod 未満の間隔で 6 秒以上到着し続けることがあり、旧実装なら待って成功していたケースが赤くなる。カットオフが BEFOLD_TEST_TIMEOUT_SECONDS と連動しないのが根本原因。TASK-116.6(thread-sanitizer ジョブの慢性的失敗解消)と関連。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 カットオフが BEFOLD_TEST_TIMEOUT_SECONDS(またはテスト環境のスケール係数)と連動する
- [x] #2 thread-sanitizer 相当の遅延環境でも confirmWatcherArmed が誤 fail しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 独自のカットオフ定数を新設せず、既存の単一情報源 testTimeoutSeconds(fallback:) に委譲する(fallback は従来値 quiescePeriod * 20 を維持)
2. BEFOLD_TEST_TIMEOUT_SECONDS=120 で FileWatcherIntegrationTests を実行し、カットオフが連動することを確認
3. thread-sanitizer 相当として swift test --sanitize=thread で同スイートを実行し誤 fail しないことを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 独自のカットオフ定数を新設せず、既存の単一情報源 testTimeoutSeconds(fallback:) へ委譲する quiesceCutoffSeconds(quiescePeriod:) を befoldTests/TestSupport.swift に切り出し、confirmWatcherArmed はこれを使う。環境変数未設定時は従来どおり quiescePeriod * 20(既定 6 秒)。

テスト: befoldTests/QuiesceCutoffTests.swift を追加。
- 連動テスト: quiesceCutoffSeconds(0.3) == testTimeoutSeconds(fallback: 6)。固定値へ退行すると、BEFOLD_TEST_TIMEOUT_SECONDS を設定している CI ジョブ(通常 30 / TSan 120)で落ちる。
- フォールバックテスト: 環境変数未設定時のみ .enabled(if:) で実行し 6 秒であることを確認。

検証:
- swift test --filter QuiesceCutoffTests: 2 tests パス(ローカル、環境変数なし)。
- BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --filter 'QuiesceCutoffTests|FileWatcherIntegrationTests': 10 tests パス(フォールバックテストは前提不成立で自動スキップ)。
- BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --sanitize=thread --filter 'FileWatcherIntegrationTests|QuiesceCutoffTests'(CI の thread-sanitizer ジョブと同条件): 10 tests パス。この環境ではカットオフが 6 秒→120 秒へ連動する。
- swift test 全体 646 tests / 93 suites パス。

補足: ローカルマシンは CI の TSan ジョブほど遅くならないため、6 秒カットオフでの誤 fail をローカルで再現させた上での比較はできていない。AC#2 の根拠は『同条件での実行がグリーン』と『カットオフが予算どおり 120 秒へスケールすること(単体テストでピン留め)』の 2 点。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
confirmWatcherArmed の静穏化カットオフを固定値(quiescePeriod * 20)から既存の単一情報源 testTimeoutSeconds(BEFOLD_TEST_TIMEOUT_SECONDS)へ委譲し、CI 側で予算を延長した環境では打ち切りも自動追随するようにした。切り出した quiesceCutoffSeconds を QuiesceCutoffTests で連動・フォールバックの両面からピン留めし、TSan + 予算 120 秒の同条件実行と全体 646 tests のパスで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
