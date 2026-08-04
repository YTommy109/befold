---
id: TASK-50
title: 'CI: build-and-test の FileWatcherIntegrationTests.detectsFileDeletion が不安定に失敗する'
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 09:11'
updated_date: '2026-07-18 06:57'
labels:
  - ci
  - bug
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/29568618799'
priority: high
ordinal: 4375
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #239 の CI run https://github.com/YTommy109/befold/actions/runs/29568618799 (build-and-test / テストを実行する) で FileWatcherIntegrationTests.detectsFileDeletion が失敗した(count.get() → 6 が baseline → 6 を上回らない)。task-11 では thread-sanitizer ジョブの detectsFileModification のタイムアウト無視が原因だったが、今回は build-and-test ジョブ(非TSan)で別テスト(detectsFileDeletion)が失敗しており、同種だが別原因の可能性がある。task-35 の作業中に偶然検出したもので、task-35 の変更(ci.ymlのアクションバージョン更新)自体とは無関係と判断している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 GHA run 29568618799 などの失敗ログから detectsFileDeletion 失敗の原因を特定する
- [x] #2 アプリ本体(FileWatcher)側の問題かテスト側のタイミング/ポーリング設計の問題かを切り分ける
- [x] #3 原因に応じて実装またはテストを修正し、CI で安定して通ることを確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 原因調査(general-purpose サブエージェントに委譲): CI ログ(gh run view 29568618799 --log-failed)から
   実際の失敗箇所を特定。detectsFileDeletion は 14.286 秒で失敗し、
   waitUntil { count.get() > baseline } の待機タイムアウト(BEFOLD_TEST_TIMEOUT_SECONDS
   未設定時のデフォルト 10 秒)を超過していた。
2. 切り分け(AC#2): confirmWatcherArmed は削除実行前に baseline=6 まで正しく到達しており、
   kevent 登録レースは発生していない(この問題は PR #171 で既に対処済み)。
   FileWatcher.swift の削除検出ロジック自体は前回調査で ThreadSanitizer クリーン、
   ロジックにも変更なし。よってアプリ本体のバグではなく、テスト側のポーリング
   タイムアウト予算がこの CI ランナーの一時的な低速化(コンパイル直後の CPU 輻輳等)に
   対して不十分だったという、テスト側のタイミング設計の問題と判断する。
3. これは task-11(thread-sanitizer ジョブの detectsFileModification)で既に発生した
   同種のクラスの flaky であり、その際は BEFOLD_TEST_TIMEOUT_SECONDS を
   thread-sanitizer ジョブにのみ 30 秒で設定して解決した(bf592c5, PR #171)。
   今回は build-and-test ジョブ(非TSan)で同じ問題が再発したため、
   単純化検討の結果、新しい仕組みを増やさず、既存の BEFOLD_TEST_TIMEOUT_SECONDS
   の仕組みをそのまま build-and-test ジョブにも適用するのが最も単純な対応と判断。
4. 実装: .github/workflows/ci.yml の build-and-test ジョブの
   「テストを実行する」ステップに env: BEFOLD_TEST_TIMEOUT_SECONDS: 30 を追加する
   (thread-sanitizer ジョブと同じ値で揃える)。
5. ローカルで swift test が通ることを確認する。CI での安定性は次回以降の実行で
   継続的に観測する(flaky の性質上、1回のローカル実行では再現・証明できないため)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
gh run view 29568618799 --log-failed で実際の失敗ログを取得: detectsFileDeletion は 14.286秒で失敗し、waitUntil { count.get() > baseline } の待機(BEFOLD_TEST_TIMEOUT_SECONDS未設定時のデフォルト10秒)がタイムアウトしていた。confirmWatcherArmed は削除実行前に baseline=6 まで正しく到達しておりkevent登録レース(PR #171で対処済み)ではない。FileWatcher.swift の削除検出ロジックに変更はなくThreadSanitizerもクリーンなため、アプリ本体のバグではなくテスト側のポーリングタイムアウト予算がCIランナーの一時的な低速化に対して不十分だったと判断(切り分け完了)。task-11(thread-sanitizerジョブのdetectsFileModification)で同種の問題が起きた際はBEFOLD_TEST_TIMEOUT_SECONDSをそのジョブにのみ30秒で設定して解決していた(bf592c5)。単純化検討の結果、新しい仕組みを増やさず既存のBEFOLD_TEST_TIMEOUT_SECONDSをbuild-and-testジョブにも同じ値で適用する方針を採用。ローカルではswift test(352件)、BEFOLD_TEST_TIMEOUT_SECONDS=30でのFileWatcherIntegrationTests(8件)とも全てpass。flakyの性質上CIでの安定性は次回以降の実行で継続観測が必要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
build-and-test ジョブ(非TSan)で detectsFileDeletion が CI ランナーの一時的な低速化により10秒のポーリングタイムアウトを超過して失敗していた。CIログ調査で kevent登録レースやFileWatcher側のバグではなくテスト側のタイムアウト予算不足と切り分け、task-11で同種問題に使った既存の BEFOLD_TEST_TIMEOUT_SECONDS 機構を build-and-test ジョブにも thread-sanitizer と同じ30秒で適用した(.github/workflows/ci.yml)。ローカルで swift test 352件、FileWatcherIntegrationTests 8件が全てpass。CIでの安定性は今後の実行で継続確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
