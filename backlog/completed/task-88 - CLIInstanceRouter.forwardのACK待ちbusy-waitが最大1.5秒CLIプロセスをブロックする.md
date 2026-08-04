---
id: TASK-88
title: CLIInstanceRouter.forward()のACK待ちbusy-waitが最大1.5秒CLIプロセスをブロックする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 07:21'
updated_date: '2026-07-21 08:37'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/CLIInstanceRouter.swift
priority: low
type: chore
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
forward() は ACK 未受信時、1回の試行あたり ackTimeout(0.5秒)まで RunLoop を busy-wait し、これを maxAttempts(3回)繰り返す。宛先インスタンスが生存しているが ACK 送出が遅い/失われる状況では、CLI 呼び出し元プロセスのメインスレッドが最大 1.5 秒ブロックされる。
スクリプトやエディタ統合から `befold <path>` を呼び出す fire-and-forget 的な用途では、この待ち時間は体感上の遅延として表面化しうる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ACK消失・遅延時にCLIプロセスがブロックされる最大時間を短縮する対応方針(タイムアウト短縮/バックグラウンド化等)を検討し実装する、または現状を許容する場合はその理由を明記する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ACK待ち総時間(maxAttempts×ackTimeout=1.5秒)は、task-86で文書化した起動直後レース窓に対する安全マージンでもあるため、短縮するとtask-86の既知の限界(request未達のまま成功扱い)を悪化させるリスクがある。ユーザー承認により、現状値を維持しその理由をdocコメントで明記する方針で確定。
2. maxForwardAttempts/ackTimeoutの定義箇所に、この値がtask-86のレース窓との安全マージンであり、短縮するとtask-86のリスクが悪化する旨のdocコメントを追加する。
3. AC#1は「許容」の判断とその理由の明記により満たす。実装(挙動)変更は行わない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ユーザーに方針確認(現状許容 vs ackTimeout短縮)を実施し、「現状(0.5秒×3回)を許容し理由を明記」を選択いただいた。

検証: swift test --filter CLIInstanceRouterTests で5件green(挙動変更なし、doc追記のみ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
maxForwardAttempts/ackTimeout(総待ち時間1.5秒)の定義箇所に、この値がtask-86で文書化した起動直後レース窓に対する安全マージンでもあり、短縮するとtask-86の既知の限界(request未達のまま成功扱いされるケース)を悪化させるリスクがあることをdocコメントで明記した。ユーザーに方針確認し、体感速度より安全マージンを優先し現状値を維持する方針で確定。挙動変更なし、swift testで既存5件green。
<!-- SECTION:FINAL_SUMMARY:END -->
