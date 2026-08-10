---
id: TASK-427
title: テスト終了後まで残る SlowFileReader の待機が run 全体を落とすのを構造的に塞ぐ
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 12:26'
updated_date: '2026-08-10 14:24'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRendererContentUpdateIntegrationTests の SlowFileReader は DispatchSemaphore を 1 回だけ signal してゲートを開ける形になっている。テスト終了後に走った再描画が readData を再び呼ぶと、その待機は誰にも signal されず、TASK-424 で入れた waitOrRecordTimeout の 15 秒上限に達して Issue.record する。この記録はどのテストにも紐づかないため `Test «unknown» recorded an issue at ViewerRendererContentUpdateIntegrationTests.swift:322` として現れ、全スイートが pass していても run 全体が exit 1 で落ちる。実測: PR #468 の CI（run 31386949217 / job 93449413264）で 1389 tests・202 suites すべて pass、ViewerRendererContentUpdateIntegrationTests スイート自体も pass しながらこの 1 件で失敗した。同じ job の再実行は pass しており、タイミング依存のフレーク。ゲートを『1 回 signal で 1 つだけ通す』形から『開いたら以後は待たない』形（LockedBox<Bool> 等のフラグを readData の先頭で見る）へ変えると、余分な readData が何回来ても待たずに通るため塞がる。DispatchSemaphore を余分に signal して数合わせをする方式は、カウントが初期値とずれた状態で解放されると libdispatch がプロセスごと落とすため採らない（同ファイル 120-122 行のコメント参照）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 テスト本体がゲートを開けた後は、以降の readData が何回呼ばれても待機せずに通る
- [x] #2 テスト終了後に残った readData が waitOrRecordTimeout の上限に達して «unknown» の Issue を記録する経路が無くなる
- [x] #3 既存の 3 テスト（diffStateIsNotConfirmedBeforeRender / abortedRenderDoesNotLeaveOptionsInJS / staleImageEmbedDoesNotClobberNewerRender）が意図どおり中断を再現していることを、修正前に失敗する形で担保したまま保つ
- [x] #4 フルスイートを 3 回連続実行して pass する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: 既存の AsyncGate（BefoldTestSupport）が既に「open() したら以後の wait は素通り」のゲート意味論を持つ。readData は同期プロトコル実装なので async 版は使えないが、同じ意味論の同期版を用意すれば「1 回 signal で 1 つだけ通す」カウンタ方式そのものを捨てられる。DispatchSemaphore を残して数合わせする案（テスト末尾で signal を戻す）は採らない——初期値より減ったまま解放されると libdispatch がプロセスごと落ちるため、数合わせ自体が別のフレーク源になる。
2. BefoldTestSupport/BlockingWait.swift に NSCondition ベースの BlockingGate を追加する（open() で broadcast、wait は開いていれば即戻り、上限に達したら Issue.record）。タイムアウト記録は waitOrRecordTimeout と共通ヘルパーに寄せる。
3. ViewerRendererContentUpdateIntegrationTests の SlowFileReader.releaseGate を BlockingGate へ差し替え、gate.signal() を gate.open() にする。素通し用の DispatchSemaphore(value: 1) + 末尾 signal は BlockingGate(isOpen: true) に置き換え、カウント戻しのコメントごと削除する。
4. ゲートが依然として止めていることを、BlockingGate を常時 open にする変異で 3 テストが落ちることで確認する（AC #3）。
5. フルスイートを 3 回連続実行する（AC #4）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: BefoldTestSupport/BlockingWait.swift に NSCondition ベースの BlockingGate を追加し、SlowFileReader.releaseGate を DispatchSemaphore から差し替えた。open() は broadcast で待機者全員を解放し、開閉フラグを持つため後から来た wait は何回でも素通りする（AC #1 / #2）。素通しさせたい 1 回目の描画は BlockingGate(isOpen: true) で表し、DispatchSemaphore(value: 1) を消費してから signal で戻していたカウント合わせ（と、その理由を説明するコメント）を削除した。

単純化の検討: 既存の AsyncGate が同じ意味論の async 版を持っていたため、新しい概念は増やさず「同期版の AsyncGate」として揃えた。DispatchSemaphore を残して数合わせする案は採らない（初期値より減ったまま解放されると libdispatch がプロセスごと落ちるため、数合わせ自体が別のフレーク源になる）。

破れたら落ちるものを付けた（担保）: befoldTests/BlockingWaitTests.swift を新設し、(a) open() 済みのゲートは後続の wait を何回でも素通しする、(b) open() は待機中の全員を解放する、(c) isOpen: true は待たせない、の 3 件を測る。wait は Bool（開いて戻ったか / 上限で戻ったか）を返すようにし、テストは「開いて戻った数」だけを数える——上限到達で戻った分を数えると、1 つずつしか通さない実装でも数が揃ってテストは緑のまま «unknown» の Issue だけが残る（TASK-427 の壊れ方そのもの）。

実測（変異テスト）:
- BlockingGate.open() を『開閉フラグを立てず condition.signal() で 1 つだけ起こす』（＝1 回 signal 方式）へ変異させると、BlockingGateTests が 2 件失敗し、同時に «unknown» の Issue が記録されて run が落ちる。CI で観測された失敗の形をローカルで再現できている。
- AC #3 は、テスト側ではなく本番コード側を退行させて確認した（ゲートを開けっぱなしにする変異では 3 件とも緑のままで、中断の再現性を測れないため）:
  1. ミラー確定を embeddedContent の await より前へ出す（TASK-334 の退行）→ diffStateIsNotConfirmedBeforeRender が失敗（:141 の diffState 比較）
  2. 差分の読み出しと JS への送信を await より前へ出す（TASK-336 の退行）→ abortedRenderDoesNotLeaveOptionsInJS が失敗（:207 の JS 読み出し）
  3. embeddedContent 完了後の世代ガードを削除 → staleImageEmbedDoesNotClobberNewerRender が失敗（:262 の contentRevision 比較）
  いずれも確認後に本番コードは復元済み（git diff で 0 差分）。
- AC #4: フルスイート 3 回連続で pass（1392 tests / 203 suites、exit 0、«unknown» の Issue 0 件）。
- swiftformat は 0 files formatted（整形差分なし）、swiftlint は追加 2 ファイルとも新規警告なし（既存の type_name 1 件のみで、これは変更前から存在）。
- 新規ファイル追加のため xcodegen generate 実行済み。

残課題（このタスクのスコープ外）: 同じ『1 回 signal をゲート代わりに使う』形が GitStatusStoreTests.FakeReader.status と GitCommandFileIndexConcurrencyTests.BlockingRepository.trackedFiles にも残っている。想定より多く呼ばれると同じく «unknown» の Issue になるため、BlockingGate へ寄せる価値がある。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
テストのゲートを『1 回 signal で 1 つだけ通す』DispatchSemaphore から、開閉フラグを持つ BlockingGate（NSCondition + broadcast、BefoldTestSupport）へ置き換え、テスト終了後に走った余分な readData が待機して «unknown» の Issue を記録する経路を無くした。ゲートの性質は BlockingWaitTests で担保し、1 回 signal 方式へ戻す変異でテストが落ちること、既存 3 テストが本番コードの退行（TASK-334 / TASK-336 / 世代ガード削除）で落ちることを実測した。フルスイート 3 回連続 pass（1392 tests / 203 suites、«unknown» 0 件）。
<!-- SECTION:FINAL_SUMMARY:END -->
