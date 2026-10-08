---
id: TASK-674.1
title: BlockingGate の待機を「上限なし + スレッド種別の検査」の 1 本にする
status: Done
assignee:
  - '@claude'
created_date: '2026-10-06 06:47'
updated_date: '2026-10-06 07:22'
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
- [x] #1 BlockingGate の待機 API は waitUntilOpen の 1 つで、秒数を引数に取らず、BEFOLD_TEST_TIMEOUT_SECONDS も参照しない（fallback / fixedBudget と、上限付き・上限なしの 2 本立てが消えている）
- [x] #2 閉じたゲートをメインスレッドまたは Swift Concurrency のタスクの上で待つと、塞がずに即座に Issue を記録して戻る。BlockingGateTests が協調プール上のタスク・タスクの外のメインスレッド・withBlockingWork の専用スレッドの 3 ケースと待機の拒否を測り、検査を条件ごとに外すと落ちることを実測している
- [x] #3 棚卸しの 6 箇所が新しい待機へ移っている: GitStatusStoreTests（fixedBudget 300 を撤去し defer で解放）、GitCommandFileIndexConcurrencyTests、ViewerWindowControllerDiffTests、BlockingWorkTests、SlowFileReader、ViewerWindowManagerRecentRepositoriesTests（DispatchSemaphore をやめ、try #require の失敗でも解放される）
- [x] #4 退行の検出役の 2 テストが、退行を注入すると上限を待たずにテスト名つきで落ちることを実測し Notes に記録している（ViewerWindowControllerDiffTests: refresh へルート解決の同期呼び出しを足す / BlockingWorkTests: withBlockingWork を協調プール上の実行へ差し替える）
- [x] #5 GitStatusStoreTests.foldsConcurrentRequestsForSameRoot を、MainActor を数秒塞ぐ使い捨てテストと並走させ、(a) 変更前のツリーで fixedBudget をその秒数より短くすると FakeReader.status の上限超過が出る (b) 変更後は出ない、を対で実測している（使い捨てテストはコミットしない）
- [x] #6 swift test の全体実行が、通常・LIBDISPATCH_COOPERATIVE_POOL_STRICT=1・--sanitize=thread の 3 通りで、場所の検査の誤発火 0 件で通る
- [x] #7 BlockingWait.swift の doc コメントと docs/dev/native-app-design.md の withBlockingWork の節が新しい規約に追随し、waitOrRecordTimeout の doc が「テスト本体側の待機用」であることを述べている
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装（2026-10-06）: BlockingGate の待機を waitUntilOpen(sourceLocation:) の 1 本にした。上限なし。閉じたゲートを BlockingGate.blockingHazard()（Thread.isMainThread / withUnsafeCurrentTask）が nil でない場所で待とうとしたら、Issue.record して false を返す。開いたゲートは検査せず素通しする。wait(_:fallback:fixedBudget:) は削除した。6 箇所を移し、GitStatusStoreTests と ViewerWindowManagerRecentRepositoriesTests に defer の解放を足した（後者は DispatchSemaphore をやめた）。本番コードの変更は無い。
計画からの変更: (1) API 名は wait ではなく既存の waitUntilOpen にした。.swiftlint.yml の独自ルール unbounded_semaphore_wait が、テスト内の引数なし .wait() を弾くため（このファイルはフックで保護されており、明示の指示なしに編集できない）。ルールは生の DispatchSemaphore.wait() を弾く役のまま残る。ただしルールの文言は「waitOrRecordTimeout を使う」のままで、足止めを書きたい人を上限つきの待機へ案内してしまう。文言の修正はユーザーの判断に委ねる（未対応）。(2) 場所の判定を blockingHazard() として待機から切り出した。待機そのものでメインスレッドの条件を測ると、検査が外れた退行でメインスレッドが塞がり、失敗ではなくハングになるため。(3) 重複するテスト waitUntilOpenReturnsOnlyAfterOpen は消した（openReleasesAllPendingWaiters が同じ性質を 3 本の待機で測っている）。
実測（手元 macOS 27・10 コア。ログは .tmp/t6741-*.log でリポジトリには含まれない）:
- AC#2 検査を外すと落ちる（BlockingGateTests、変異ごとに元へ戻した）: メインスレッドの条件を外す → mainThreadOutsideTaskIsHazardous が 0.001 秒で失敗。タスクの条件を外す → taskOnCooperativePoolIsHazardous が失敗し、closedGateRefusesToBlockInsideTask も 10.0 秒で失敗。待機から検査の呼び出しを外す → closedGateRefusesToBlockInsideTask が 10.0 秒で失敗。3 つともテスト名つき・有限時間。
- AC#4 退行の注入: ViewerDiffPresenter.refresh へ同期のルート解決を足す → refreshDiffDoesNotBlockMainActorOnRootResolution が 1.07 秒で失敗（文言「塞いではいけない場所（メインスレッド）」）。withBlockingWork を Task 上の実行へ差し替える → startsEveryCallEvenWhenMoreThanPoolWidthAreBlocked が 0.05 秒で失敗（検査の Issue 40 件 = コア数 10 × 4）。注入は git checkout で戻した。
- AC#5 MainActor を塞ぐ使い捨てテスト（8 本が 0.5 秒ずつ交互に塞ぐ）との並走: 変更前のツリーで fixedBudget を 2 秒にすると 3/3 回「FakeReader.status: 同期待機が 2.0 秒で上限に達した」が出て、reader.callCount == 1 も落ちた（上限で足止めが外れ、畳み込みの検証自体が崩れる）。変更後は 3/3 回 pass（32.2 秒）。最初に試した「2 秒 × 8 本を連続で塞ぐ」形は足止めの区間と重ならず再現しなかった（3/3 回 pass）ので、交互に譲る形へ直した。使い捨てテストは削除済み。
- AC#6 全体実行（swift test --skip befoldCLITests）: 通常 2002 テスト・329 スイート pass（38.1 秒）、LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 で pass（42.3 秒）、--sanitize=thread + BEFOLD_TEST_TIMEOUT_SECONDS=120 で pass（137.0 秒）。3 通りとも検査の発火は closedGateRefusesToBlockInsideTask の既知 1 件だけ。befoldCLITests は 72 件 pass。
- その他: swiftformat --lint は全ターゲットで 0 件。swiftlint は origin/main と 45 件対 45 件で差分ゼロ（新規なし・解消なし）。check-type-group-size --check は閾値以内。xcodebuild build -scheme befold は BUILD SUCCEEDED。check-doc-citations / markdownlint は指摘 0 件。
- responsibility-reviewer は回していない（型・プロトコル準拠・stored property・注入クロージャを増やしていない。BlockingGate のメソッドは wait / waitUntilOpen の 2 本が waitUntilOpen / blockingHazard の 2 本になった）。
未確認: CI の macos-26 での挙動（push 後の build-and-test と thread-sanitizer が最初の確認になる）。TSan は手元の無負荷 1 回で、TASK-672 の混雑（run 全体 363 秒）は再現していない。ただし上限そのものが無いので、混雑で「同期待機が」の Issue が出る経路は残っていない（BlockingWait.swift で testTimeoutSeconds を読むのは waitOrRecordTimeout だけ）。
docs/dev/native-app-design.md: withBlockingWork の節に、BlockingGate の検査を 3 つ目の担保として足し、上限を持たない理由と ADR 0012 へのリンクを書いた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BlockingGate の待機を waitUntilOpen の 1 本にし、壁時計の上限を API ごと撤去した（ADR 0012）。閉じたゲートをメインスレッドか Swift Concurrency のタスクの上で待とうとすると、塞がずに失敗を記録して戻る。棚卸しの 6 箇所を移し、同じ型の露出が残っていた GitStatusStoreTests の固定 300 秒も消えた。本番コードは変えていない。検証: 全体実行は通常・プール幅 1・TSan の 3 通りで 2002 テスト pass（検査の誤発火 0 件）。MainActor を塞ぐテストとの並走で、変更前（上限 2 秒に短縮）は 3/3 回失敗、変更後は 3/3 回 pass。退行の注入 2 件はテスト名つきで 1.07 秒・0.05 秒で失敗。検査の条件を 1 つずつ外す変異 3 件はすべて有限時間で失敗。swiftlint は main と差分ゼロ。API 名は計画の wait ではなく waitUntilOpen にした（既存の lint ルール unbounded_semaphore_wait が引数なしの .wait() を弾くため）。CI の macos-26 での挙動は push 後の実行が最初の確認になる。
<!-- SECTION:FINAL_SUMMARY:END -->
