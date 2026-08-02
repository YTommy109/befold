---
id: TASK-259
title: CLIRequestWireIntegrationTests が Distributed Notification の配送レースで flaky
status: Done
assignee: []
created_date: '2026-08-02 10:04'
updated_date: '2026-08-02 13:25'
labels:
  - test
dependencies: []
priority: medium
type: bug
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befoldCLITests/CLIRequestWireIntegrationTests.swift の「全オプション付きの要求が実際の Distributed Notification を通って復元できる」が、フルスイート実行（swift test）で約 5〜8 回に 1 回失敗する。失敗形は waitUntil { received.get() != nil } のタイムアウトで、通知が 1 度も配送されない。--filter で単体実行すると 6/6 成功するため、フルスイート並行実行時にのみ顕在化する。

推定原因: DistributedNotificationCenter.addObserver によるオブザーバ登録は distnoted への非同期登録であり、登録完了前に postNotificationName すると配送先が存在せず通知が捨てられる。テストは addObserver の直後に 1 回だけ post しているため、この窓に入ると永久に届かない（待つだけでは回復しない）。並行実行で distnoted の応答が遅れるほど窓が広がることとも整合する。同種の登録レースは TASK-85 でも扱われている（本番側は ACK 再送で回避済み）。

なお本件は TASK-186（サイドバー Git ステータス）の作業中に観測されたが、当該差分は CLI/通知経路に一切触れておらず（git diff origin/main で当該テスト・BefoldCLI ともに変更なし）、既存の不安定性である。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フルスイート（swift test）を 10 回連続実行して当該テストが 1 度も失敗しない
- [x] #2 配送されないまま待ち続ける形ではなく、届くまで post を再試行する形（BefoldTestSupport の waitUntilWithRetry 相当）になっている
- [x] #3 修正後も「実 DistributedNotificationCenter を通した往復を検証する」というテストの意図が保たれている（ワイヤ表現の encode/decode だけを検証する形に退化していない）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
既存の waitUntilWithRetry を使い、届くまで post を再試行する形へ変更（新しい状態や分岐は追加せず既存ヘルパーの流用のみ）。Sendable 制約のため userInfo を [String: String] へ写し、件数一致で欠落がないことを担保。実 DistributedNotificationCenter 往復の検証意図は維持。検証: swift test（フルスイート）10 回連続で全て成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIRequestWireIntegrationTests の単発 post + waitUntil を waitUntilWithRetry による post 再送へ変更し、distnoted のオブザーバ登録レースで通知が捨てられても回復するようにした。swift test を 10 回連続実行して全て成功。
<!-- SECTION:FINAL_SUMMARY:END -->
