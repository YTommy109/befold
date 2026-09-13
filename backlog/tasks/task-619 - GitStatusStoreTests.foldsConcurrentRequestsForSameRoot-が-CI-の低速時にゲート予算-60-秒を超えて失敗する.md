---
id: TASK-619
title: >-
  GitStatusStoreTests.foldsConcurrentRequestsForSameRoot が CI の低速時にゲート予算 60
  秒を超えて失敗する
status: To Do
assignee: []
created_date: '2026-09-13 08:10'
labels:
  - ci
  - test
dependencies: []
priority: medium
type: bug
ordinal: 809000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
実測（2026-09-13、PR #658 の build-and-test run 34697491161）: `GitStatusStoreTests.swift:73` の `FakeReader.status: 同期待機が 60.0 秒で上限に達した` が 2 回記録され、テスト自体はその後「129 秒経過後に通過」したがランは失敗になった。同じテストは直前の main の緑ラン（run 34695167155）でも「88 秒経過後に通過」で、予算（BEFOLD_TEST_TIMEOUT_SECONDS=60）に対して余裕が無い。失敗ランは全体が 137 秒（緑ランは 90 秒）と遅く、macOS ランナーの低速化で露出した。手元では 9 テスト 0.016 秒で通る。

構造: 1 本目の要求を `FakeReader.status` の `BlockingGate` で足止めし、2 本目のルート解決（`withBlockingWork` 経由）が完了するのを `AsyncGate` で待ってから解放する。2 本目がルート解決へ到達するには MainActor の順番が必要で、並列に走る GUI 系スイートが MainActor を長く占有すると、1 本目の足止め側（60 秒予算）が先に切れる。**同一ランで他スイートの「passed after」が 111〜137 秒**だったことから、MainActor の輻輳が 60 秒を超えていた。

候補: (a) この足止め側の予算を「ランナーの輻輳」ではなく「畳み込みの検証」に見合う長さへ切り離す（FakeReader の block.wait に別の上限を渡す） (b) 2 本目のルート解決が MainActor を経由しない形に組み替える (c) このスイートを serialized にせず、GUI スイートと同時に走らせない。再現は CI の遅いランでしか起きないため、まず (a) で予算切れの誤検知を止める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同じ構造の失敗（FakeReader.status の待機上限）が、MainActor を 60 秒以上塞ぐ他スイートと並走しても起きない（手元で MainActor を意図的に塞ぐテストを並走させて再現 → 対策後に通ることを実測）
- [ ] #2 畳み込みの検証（reader が 1 回だけ呼ばれる）は変えない
<!-- AC:END -->
