---
id: TASK-424
title: CI の build-and-test がテスト実行中に停止する（@MainActor 系スイートが完走しない）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 08:38'
updated_date: '2026-08-10 10:20'
labels:
  - ci
dependencies: []
priority: high
type: bug
ordinal: 504000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Actions の CI ワークフロー（.github/workflows/ci.yml）の build-and-test ジョブで、「テストを実行する」ステップ（swift test）が断続的に停止し、キャンセルされるまで数十分〜数時間 in_progress のまま進まなくなる。

実測（2026-08-10 時点）:
- 発生ラン: 2026-08-07 14:09（53 分でキャンセル）、2026-08-09 13:14（2 時間超でキャンセル）、2026-08-10 08:18（PR #460、25 分超で手動キャンセル）。いずれも build-and-test の swift test ステップ。
- 2026-08-09 のランのログでは、出力が 13:17:54 で完全に停止したあと一切進まない。未完了のまま残ったのは ViewerStore* / ViewerWindowController* / SidebarNavigator* / GitStatusReaderIntegrationTests など @MainActor 系のスイートが約 40 件。非 MainActor のスイート（パーサ系・CLI 系など）は完走している。
- 同じコミットをローカルで実行すると BEFOLD_TEST_TIMEOUT_SECONDS=60 で 1369 tests / 198 suites が 16 秒で全て通る。再実行すると CI も通ることがあり、再現性は低い。

疑い: どこかのテストが main actor をブロックしたまま待ちに入り、@MainActor のテストが総崩れで餓死している（BEFOLD_TEST_TIMEOUT_SECONDS の待機予算では抜けられない経路がある）。まず原因の切り分けが目的で、修正方針は調査後に決める。

副作用として、ハングしたランは macOS ランナーを最大 6 時間占有するため、切り分けと並行してジョブ側の時間上限も検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 停止時にどのテスト／どの待機がmain actor を保持しているかを、実測（ハング時のログ・スタック・再現手順のいずれか）で特定できている
- [x] #2 特定できた待機が、待機予算を超えたら停止ではなく失敗として報告されるようになっている（無限に待つ経路が残っていない）
- [x] #3 build-and-test ジョブに timeout-minutes が設定され、ハングしても数時間ランナーを占有しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 過去のハングログ（08-07 / 08-09）を突き合わせ、共通して停止したスイートを特定する。
2. ローカルで再現条件を作る（協調スレッドプールの幅を絞る）。
3. 停止したらプロセスのスタックを採取し、どの待機が保持しているかを確定する。
4. 特定した待機に上限を付け、超過を失敗として記録する共通ヘルパーへ寄せる。
5. 生の上限なし待機を swiftlint の custom rule で禁止し、破れたら落ちる形にする。
6. ジョブに timeout-minutes を設定する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因特定（実測）:
- ハング 2 件（2026-08-07 / 08-09）で共通して停止したスイートは 25 件。いずれも @MainActor のテストを含む。エージェント調査が筆頭候補に挙げた ViewerWindowControllerSourceModeTests は、両方のログで passed しており原因ではない（33.9 秒 / 42.0 秒）。
- LIBDISPATCH_COOPERATIVE_POOL_STRICT=1（協調プール幅 1）でフルスイートを実行すると再現。50 分間出力が止まったまま進まない状態を作れた。
- その状態で sample(1) を採取した結果、協調プールのスレッド 2 本が無期限 DispatchSemaphore.wait() で永久停止していた:
  - com.apple.root.default-qos.cooperative → GitCommandFileIndexConcurrencyTests.swift:45 BlockingRepository.trackedFiles
  - com.apple.root.utility-qos.cooperative → GitStatusStoreTests.swift:73 FakeReader.status
  メインスレッドは CFRunLoopRun で空回りしており、main actor の占有ではなく協調スレッドプールの枯渇（forward progress violation）だった。ローカル 10 コアでは埋まらず、CI の macOS ランナー 3〜4 コアで確率的に成立する、という発生パターンとも整合する。

修正:
- BefoldTestSupport/BlockingWait.swift に waitOrRecordTimeout を追加。BEFOLD_TEST_TIMEOUT_SECONDS 由来の予算で待ち、超過したら Issue.record して戻る。
- 置き換え 3 箇所: GitStatusStoreTests.swift:73 / GitCommandFileIndexConcurrencyTests.swift:45 / ViewerRendererContentUpdateIntegrationTests.swift:322（同型の 3 件目のため個別対処ではなく共通ヘルパーへ一本化）。
- GitCommandRunnerTests.swift:406 は対象外。協調プールではなく DispatchQueue.global のワーカーを意図的に飽和させるテストで、defer で投げた本数だけ signal するため回収が保証されている（lint の excluded に理由付きで記載）。
- swiftlint custom rule unbounded_semaphore_wait を追加し、テスト配下の生の wait() を error にする。await を伴う AsyncGate.wait() はスレッドを塞がないため対象外（否定先読みで除外）。self-test 済み: 生の wait() へ戻すと 1 件検知、戻すと 0 件。

検証:
- 通常環境: 1369 tests / 198 suites 全て pass（16.4 秒）。
- 再現条件（プール幅 1）: 修正前は 50 分以上停止して終わらない → 修正後は 135 秒で完走し exit 1。詰まった箇所がファイル:行付きで出る（停止から失敗へ変わったことの担保）。プール幅 1 は本番より厳しいストレス条件のため、そこで赤になること自体は想定内。
- swiftformat: 0 files require formatting。swiftlint: 変更ファイル起因の新規指摘なし（残る 1 件 type_name は既存）。

未対処（記録のみ）: GitTestRepo.swift:25 と GitCommandRunnerTests.swift:191 の process.waitUntilExit() は上限が無く .timeLimit でも中断できないが、今回のハングのスタックには現れていない。実測の裏付けが無い状態で触らない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CI で断続的に起きていたテスト停止の原因を、上限なしの DispatchSemaphore.wait() による協調スレッドプールの枯渇と特定した（LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 で再現し、sample(1) のスタックで GitStatusStoreTests.FakeReader.status と BlockingRepository.trackedFiles の 2 本が semaphore_wait_trap のまま停止していることを確認）。予算付きで待ち超過を Issue.record する waitOrRecordTimeout を BefoldTestSupport に用意して 3 箇所を置き換え、生の wait() は swiftlint の custom rule で禁止した。あわせて ci.yml の各ジョブに timeout-minutes（build-and-test 30 / js-test 15 / thread-sanitizer 60）を設定し、万一停止してもランナーを 6 時間占有しないようにした。検証: 通常環境で 1369 tests 全て pass、再現条件では修正前の無限停止が 135 秒で完走する失敗（ファイル:行つき）へ変わった。
<!-- SECTION:FINAL_SUMMARY:END -->
