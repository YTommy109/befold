---
id: TASK-436
title: 残り 2 箇所の 1 回 signal ゲートを BlockingGate へ寄せる
status: Done
assignee: []
created_date: '2026-08-10 14:27'
updated_date: '2026-08-13 08:00'
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
- [x] #1 GitStatusStoreTests.FakeReader の block が BlockingGate になり、release.signal() 相当が open() に置き換わっている
- [x] #2 GitCommandFileIndexConcurrencyTests.BlockingRepository.releaseBlockedEnumeration が BlockingGate になっている
- [x] #3 各テストが本来検証している性質（同一ルートへの畳み込み・in-flight 管理）を、置き換え前と同じく退行時に失敗する形で保っていることを、本番コードを退行させる変異で確認する
- [x] #4 フルスイートが pass し、«unknown» の Issue が 0 件である
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
GitStatusStoreTests.FakeReader.block と GitCommandFileIndexConcurrencyTests.BlockingRepository.releaseBlockedEnumeration を BlockingGate へ置換（signal→open、waitOrRecordTimeout→gate.wait）。変異による退行確認（実測）: (1) GitStatusStore.swift:126 の in-flight 早期 return を削除 → foldsConcurrentRequestsForSameRoot が 0.001 秒で「(reader.callCount → 2) == 1」のアサーション失敗（待機ではなく本来の失敗として出る）。(2) KeyedLock.withLock のキーを定数化（ロック粒度をリポジトリ横断へ退行）→ slowEnumerationDoesNotBlockOtherRepositories が失敗。(3) KeyedLock.withLock のロック取得を除去 → concurrentCallsForSameRootEnumerateOnce が「同一ルートの列挙が重複して走っている」で失敗。いずれも変異を戻して pass を確認。フルスイート: 1483 tests / 235 suites すべて pass、«unknown» の Issue 0 件。swiftlint 該当 2 ファイル 0 件、swiftformat 0/230 files require formatting。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
残り 2 箇所の 1 回 signal ゲート（FakeReader.block / BlockingRepository.releaseBlockedEnumeration）を BlockingGate へ置き換えた。余分な呼び出しは待たずに通るため «unknown» Issue による run 全体の失敗が起きなくなり、退行は本来のアサーション失敗として現れる。3 種の本番コード変異で各テストが失敗することを実測、フルスイート 1483 tests pass・«unknown» 0 件で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
