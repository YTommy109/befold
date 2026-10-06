---
id: TASK-674.1
title: BlockingGate の待機を「上限なし + スレッド種別の検査」の 1 本にする
status: To Do
assignee: []
created_date: '2026-10-06 06:47'
updated_date: '2026-10-06 06:53'
labels:
  - test
  - refactor
dependencies: []
references:
  - TASK-619
  - TASK-665
  - TASK-672
documentation:
  - docs/adr/0012-sync-gate-without-wall-clock-bound.md
parent_task_id: TASK-674
priority: medium
ordinal: 860000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0012（docs/adr/0012-sync-gate-without-wall-clock-bound.md）の実装。同期ゲート BlockingGate（BefoldApp/BefoldTestSupport/BlockingWait.swift）の待機から壁時計の上限を API ごと撤去し、閉じたゲートをメインスレッドか協調スレッドプールで待とうとしたら、塞がずに Issue を記録して戻る形にする。上限付きの wait(_:fallback:fixedBudget:) と上限なしの waitUntilOpen() の 2 本立てを 1 本にまとめ、TASK-674 の棚卸しで挙げた 6 箇所を移す。発端は TASK-619 / TASK-665 / TASK-672（壁時計の上限が MainActor の順番待ちを測り、正しいテストが混雑で落ちる型が 3 回）。同じ型の露出が残るのは GitStatusStoreTests（fixedBudget 300）。本番コードは変えない（テスト支援とテストだけ）。前提の実測は TASK-674 の Notes にある（一時パッチで全体 2001 テスト pass・誤発火 0 件、退行注入で 1.0 秒・テスト名つきの失敗）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BlockingGate の待機 API は 1 つで、秒数を引数に取らず、BEFOLD_TEST_TIMEOUT_SECONDS も参照しない（fallback / fixedBudget と、上限付き・上限なしの 2 本立てが消えている）
- [ ] #2 閉じたゲートをメインスレッドまたは Swift Concurrency のタスクの上で待つと、塞がずに即座に Issue を記録して戻る。BlockingGateTests が協調プール上のタスク・MainActor 上・専用スレッド上の 3 ケースを測り、検査を外すと落ちることを実測している
- [ ] #3 棚卸しの 6 箇所が新しい待機へ移っている: GitStatusStoreTests（fixedBudget 300 を撤去し defer で解放）、GitCommandFileIndexConcurrencyTests、ViewerWindowControllerDiffTests、BlockingWorkTests、SlowFileReader、ViewerWindowManagerRecentRepositoriesTests（DispatchSemaphore をやめ、try #require の失敗でも解放される）
- [ ] #4 退行の検出役の 2 テストが、退行を注入すると上限を待たずにテスト名つきで落ちることを実測し Notes に記録している（ViewerWindowControllerDiffTests: refresh へルート解決の同期呼び出しを足す / BlockingWorkTests: withBlockingWork を協調プール上の実行へ差し替える）
- [ ] #5 GitStatusStoreTests.foldsConcurrentRequestsForSameRoot を、MainActor を数秒塞ぐ使い捨てテストと並走させ、(a) 変更前のツリーで fixedBudget をその秒数より短くすると FakeReader.status の上限超過が出る (b) 変更後は出ない、を対で実測している（使い捨てテストはコミットしない）
- [ ] #6 swift test の全体実行が、通常・LIBDISPATCH_COOPERATIVE_POOL_STRICT=1・--sanitize=thread の 3 通りで、場所の検査の誤発火 0 件で通る
- [ ] #7 BlockingWait.swift の doc コメントと docs/dev/native-app-design.md の withBlockingWork の節が新しい規約に追随し、waitOrRecordTimeout の doc が「テスト本体側の待機用」であることを述べている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BlockingGate（BefoldTestSupport/BlockingWait.swift）の待機を wait(sourceLocation:) -> Bool の 1 本にする。上限なし。**閉じていて塞ぐことになるときだけ**場所を検査し、Thread.isMainThread または withUnsafeCurrentTask { $0 != nil } なら Issue.record（何が悪いかと、withBlockingWork へ逃がすことを文言に入れる）して false を返す。開いたゲートは検査せず素通しする。wait(_:fallback:fixedBudget:) と waitUntilOpen() は消す。ラベル引数は落とす（Issue は呼び出し位置の sourceLocation で特定できる）。
2. 棚卸しの 6 箇所を移す。GitStatusStoreTests は fixedBudget を撤去して defer { release.open() } を置く。ViewerWindowManagerRecentRepositoriesTests は DispatchSemaphore を BlockingGate に替え、openViewer の直後に defer で解放する。
3. BlockingGateTests に検査のテストを足す（協調プール上のタスク / MainActor 上 / 専用スレッド上）。プール上のケースは「誰も開けないのに戻る」ことで塞いでいないことも測る。タスク文脈の外で記録された Issue は withKnownIssue に入らない（スパイクで実測）ので、タスク外のケースを測るなら戻り値で見る。
4. doc を追随させる。BlockingWait.swift（上限の理由を述べた doc を「上限を持たない理由 + 検査」へ）、docs/dev/native-app-design.md の withBlockingWork の節、テスト側のコメント（ViewerWindowControllerDiffTests の「待機が上限に達して失敗が記録される」、GitStatusStoreTests の fixedBudget の説明、ViewerRendererRenderRaceTests の waitUntilOpen の説明、FileWatcherSlowOpenTests の「上限のない wait は…使わない(BlockingWait.swift)」）。rg 'BlockingGate|fixedBudget|waitUntilOpen|waitOrRecordTimeout|同期待機' で列挙して確かめる。waitOrRecordTimeout は残し（呼び出し元は BefoldCLIIntegrationTests と FileWatcherSlowOpenTests のテスト本体側 2 箇所になる）、doc を「テスト本体側の待機用」に直す。
5. 検証は AC#4〜#6 のとおり。swiftformat（fix）→ /swiftlint-baseline。新規ファイルは無いので xcodegen は不要。

設計レビューの結論（/review-design、2026-10-06）:
(1) 判定の真実の源: 当初案はスレッド種別を libdispatch のキューラベル（文字列の末尾 .cooperative）で判定していた。非公開の命名という「形」への依存なので、公開 API の withUnsafeCurrentTask（タスクの上で走っているという事実）へ替えた。実測: タスク上（MainActor.run・TaskGroup の子・タスクから呼ばれた同期関数）で真、Thread・DispatchQueue.global・メインキューのコールバックで偽。メインキューのコールバックは Thread.isMainThread で拾う。ADR 0012 も直した。
(2) 不変条件: 「同期ブロックに無期限を許すと協調プールを永久に塞ぐ」（BlockingWait.swift の doc、TASK-424）とは衝突しない。上限で守る代わりに、タスクの上では塞がない。TASK-427 の性質（開閉フラグで全員を通す）は変えない。native-app-design.md の「プール幅 1 のレッグで塞げば決定的に落ちる」も残る（ゲート経由なら全レッグで即落ちる）。
(3) 消費経路: wait は 5 箇所（GitStatusStoreTests / GitCommandFileIndexConcurrencyTests / ViewerWindowControllerDiffTests / BlockingWorkTests / BlockingWaitTests）、waitUntilOpen は 2 箇所（ViewerRendererRenderRaceTests の SlowFileReader / BlockingWaitTests）、waitOrRecordTimeout は 3 箇所（rg 実測）。API を消すので移し漏れはコンパイルで止まる。兄弟（同期に上限つきで待つ他の箇所）は TASK-674 の Notes に棚卸し済みで、テスト本体側の待機 3 箇所は型が違うので触らない。
(4) 表示: 新しい失敗（塞ぐのを拒んだ）の文言を用意する。上限超過の文言（recordBlockingWaitTimeout）は waitOrRecordTimeout 用に残る。
(5) 順序: 開け忘れの見え方が変わる（従来は上限で戻り «unknown» の Issue、今後は戻らない）。実測は TASK-674 の Notes と ADR の Consequences。追加する defer の open() は冪等。RecentRepositories はセマフォ（1 回 1 つ）からフラグ（開けたら全員）へ変わるが、テストは didResumeGatedLookup を待つだけで通過回数に依存しない（コード参照。実装時に確かめる）。検査は閉じているときだけ行うので、開いたゲートを持つフェイクの既存の呼び出しには影響しない（スパイクの全体実行で誤発火 0 件）。
(6) 高頻度経路: 該当しない（テスト支援のみ。検査は待機 1 回につき 2 つの O(1) 呼び出し）。
(7) 測るもの: 検査のテストは「Issue が出る」だけでなく「塞がずに戻る」ことを測る（守りたいのはプールを塞がないこと）。当初の AC#5（BEFOLD_TEST_TIMEOUT_SECONDS=0.3 で 0 件）は、テスト本体側の waitUntil も同じ env で縮むため原因を切り分けられず、変更前に出ることも保証できない。MainActor を塞ぐ使い捨てテストとの並走（TASK-619 の再現方法）で対にして測る形へ差し替えた。
(8) 世代管理: 該当しない（ゲートは閉→開の一方向で、差し替わる表示状態を持たない）。
(9) 担保: 「上限を持たない」は引数が無いことで破れない（AC#1）。「検査が効く」は AC#2 のテスト。「defer で解放する」は担保を置かない——実測で、開け忘れは混雑に左右されず毎回同じ形（テスト名つきの .timeLimit）で出るため。CI で観測されたら自己解放を足す（ADR の再検討条件）。フェイクがセマフォで上限つきの足止めを自作することも止めない（ADR に引き受けたリスクとして記載）。
(10) 型グループ: 実測（check-type-group-size）で BlockingWait 127 行 / BlockingWaitTests 97 行 / GitStatusStoreTests 245 行 / ViewerWindowManagerRecentRepositoriesTests 342 行 / BlockingWorkTests 45 行。BlockingGate はメソッドが 3 → 2 に減り、stored property・プロトコル準拠・注入クロージャは増えない。BlockingWaitTests は +30 行程度の見積もり。
<!-- SECTION:PLAN:END -->
