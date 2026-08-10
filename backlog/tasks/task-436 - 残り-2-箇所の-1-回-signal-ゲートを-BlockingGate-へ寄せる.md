---
id: TASK-436
title: 残り 2 箇所の 1 回 signal ゲートを BlockingGate へ寄せる
status: To Do
assignee: []
created_date: '2026-08-10 14:27'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 114500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-427 で SlowFileReader のゲートを DispatchSemaphore の 1 回 signal から開閉フラグ方式の BlockingGate（BefoldTestSupport/BlockingWait.swift）へ置き換えたが、同じ形が 2 箇所残っている: GitStatusStoreTests.FakeReader.status（block: DispatchSemaphore、GitStatusStoreTests.swift:73 で waitOrRecordTimeout）と GitCommandFileIndexConcurrencyTests.BlockingRepository.trackedFiles（releaseBlockedEnumeration、同ファイル:45）。どちらも『テストが signal する回数より多くフェイクが呼ばれる』と、余分な待機が誰にも解放されないまま上限に達して Issue.record する。テストが既に終わっていればその記録はどのテストにも紐づかず «unknown» として現れ、全スイート pass のまま run 全体が exit 1 で落ちる（TASK-427 で実際に起きた形）。終わっていない場合でも、畳み込みの退行（reader が 2 回呼ばれる等）が callCount のアサーション失敗ではなく 15 秒の待機と «unknown» として出るため、原因が読み取れない。BlockingGate へ寄せると、余分な呼び出しは待たずに通り、退行は本来のアサーション失敗として現れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitStatusStoreTests.FakeReader の block が BlockingGate になり、release.signal() 相当が open() に置き換わっている
- [ ] #2 GitCommandFileIndexConcurrencyTests.BlockingRepository.releaseBlockedEnumeration が BlockingGate になっている
- [ ] #3 各テストが本来検証している性質（同一ルートへの畳み込み・in-flight 管理）を、置き換え前と同じく退行時に失敗する形で保っていることを、本番コードを退行させる変異で確認する
- [ ] #4 フルスイートが pass し、«unknown» の Issue が 0 件である
<!-- AC:END -->
