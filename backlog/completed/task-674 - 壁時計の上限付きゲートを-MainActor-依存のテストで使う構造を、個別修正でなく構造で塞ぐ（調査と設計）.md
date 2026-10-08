---
id: TASK-674
title: 壁時計の上限付きゲートを MainActor 依存のテストで使う構造を、個別修正でなく構造で塞ぐ（調査と設計）
status: Done
assignee:
  - '@claude'
created_date: '2026-10-06 06:06'
updated_date: '2026-10-06 06:54'
labels:
  - test
  - refactor
dependencies: []
references:
  - TASK-619
  - TASK-665
  - TASK-672
priority: medium
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-619（2026-09-13、ゲート予算 60 秒超過）、TASK-665（2026-09-29、15 秒超過）、TASK-672（2026-10-06、120 秒超過）は、同じ型の失敗が 3 週間に 3 回、毎回別のテストで出たもの。型は、「壁時計の上限付きの同期ゲート（BlockingGate.wait）を、MainActor の順番待ちに依存するテスト本体が開ける」で、全テストがほぼ同時に開始して @MainActor で直列化される全体実行（特に TSan）では、単独 0.015 秒のテストが 330〜460 秒かかり、待つ側の上限を混雑が超えるたびに次のテストが落ちる。.claude/CLAUDE.md の「同型のバグが 2 回目に出たら、個別修正をやめて構造で塞ぐ」に従い、3 回目の今、個別修正を続けず構造を決める。TASK-672 は SlowFileReader だけ上限なしにして対処したが、これは 3 件目の個別修正で、BlockingGate を上限付きで使う他の利用箇所（GitCommandFileIndexConcurrencyTests / ViewerWindowControllerDiffTests / GitStatusStoreTests。GitStatusStoreTests は TASK-619 で fixedBudget 300 を渡した）に同じ露出が残る（失敗の観測は無い）。選択肢の候補は、(A) 画像埋め込み等を本番側で async の注入点にして AsyncGate で待つ（TASK-665 と同じ形。同型を消せるが本番コードの継ぎ目の変更を伴う）、(B) 上限付き wait を MainActor 依存のフェイクで使うことを禁止する検査（scripts/check-*.sh）、(C) TSan ジョブを並行性に敏感なスイートへ絞る（混雑の根を減らすがカバレッジが減る）。いずれも効果は推定で未実測。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BlockingGate.wait を使う全箇所が棚卸しされ、それぞれについて「開ける側が MainActor の順番に依存するか」「上限の根拠（env / fixedBudget / 既定）」「本番側に async の注入点を作って AsyncGate へ移せるか」が実測またはコード参照で示されている
- [x] #2 選択肢 A / B / C のどれを採るか（併用を含む）が、検討した他の案を採らない理由とともに決まり、不可逆な判断なら ADR（backlog/decisions）に記録されている
- [x] #3 決めた構造を破ると落ちるもの（破れない構造、または落ちるテスト・検査）が、実装サブタスクの Acceptance Criteria に含まれている
- [x] #4 実装が必要なら、サブタスクに分割して起票され、サブタスクごとに /review-design が回されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BlockingGate.wait と同種の同期待機を全箇所棚卸しする（待つスレッド / 開ける側の await / 上限の根拠 / async 注入点の有無）
2. 選択肢 A / B / C を棚卸しの結果で評価し、単純化（上限が兼ねる役を分けて上限そのものを不要にできないか）を検討する
3. 採る構造の前提を一時パッチで実測する（誤発火の有無・退行の検出・開け忘れの見え方）。パッチはコミットしない
4. 決定を ADR に記録し、実装サブタスクを起票して /review-design を回す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
棚卸し（AC#1、2026-10-06。コード参照。待つスレッドは本番の呼び出し経路を辿って特定）:
フェイクが同期に塞ぐ箇所は 6 つ。待つスレッドは 6 箇所とも withBlockingWork の専用 Thread（BefoldKit/BlockingWork.swift）。フェイクが準拠するプロトコルは 6 箇所とも同期で、本番側に既存の async 注入点は 0 件。
1. GitStatusStoreTests の FakeReader.status（foldsConcurrentRequestsForSameRoot）: 経路は GitStatusStore.snapshot(forRepositoryAt:) の withBlockingWork。開ける側は @MainActor スイートのテスト本体で、open までに MainActor への復帰を含む await が 2 回（readerEntered.wait / secondRootResolved.wait）。上限は fixedBudget 300（TASK-619）。defer なし。**3 件と同じ型の露出が残る唯一の箇所**（TASK-672 の run は全体 363 秒）。AsyncGate へ移すには GitStatusReading.status の async 化が要る。
2. GitCommandFileIndexConcurrencyTests の BlockingRepository.trackedFiles（2 テスト）: テスト側が withBlockingWork で包む。スイートは nonisolated で、open までの await は waitUntil（協調プール上のポーリング）だけ。MainActor には依存しない。上限は env 既定 15。defer あり。async 化すると測定対象（NSLock のキー粒度と直列化）が消える。
3. ViewerWindowControllerDiffTests の SlowRootGitFileIndex.repositoryRoot（refreshDiffDoesNotBlockMainActorOnRootResolution）: 正常系は GitDiffLoader の withBlockingWork 上。hold から open までに await が無く、MainActor の順番に依存しない。上限は env 既定で、**退行の検出役**（MainActor 上で同期に解決すると開ける者がいないので上限で落ちる）。sidebarGit シーム（TASK-665）とは別経路で、AsyncGate へは移せない。
4. BlockingWorkTests: withBlockingWork を直接呼ぶ。nonisolated、open までは waitUntil。env 既定。同期に塞ぐこと自体が測定対象。
5. ViewerWindowManagerRecentRepositoriesTests の GatedGitFileIndex.repositoryRoot: waitOrRecordTimeout + DispatchSemaphore。経路は RecentRepositoryRecorder の withBlockingWork。openViewer から openGate までに await なし。env 既定。defer なしで、間の try #require が失敗すると解放されない。セマフォは 1 回の signal で 1 つしか通さない（TASK-427 の型）。
6. SlowFileReader.readData（ViewerRendererRenderRaceTests 2 件 + ViewerRendererContentUpdateIntegrationTests 1 件）: ViewerScriptDispatcher.embeddedContent の withBlockingWork 上。開ける側は MainActor の await 越し。上限なし（TASK-672 の waitUntilOpen）。3 テストとも defer あり。
対象外（逆向きの型。テスト本体が上限つきで待ち、合図する側は MainActor を通らない）: ViewerStoreLoadStartTests.StartSignal、FileWatcherSlowOpenTests、BefoldCLIIntegrationTests。BlockingGateTests はゲート自身のテスト。
発生した実行: TASK-619 は CI の build-and-test、TASK-665 は手元の並列 swift test、TASK-672 だけが thread-sanitizer（各タスクの Description）。選択肢 C は 3 件中 1 件にしか届かない。

決定（AC#2）: ADR 0012（docs/adr/0012-sync-gate-without-wall-clock-bound.md、backlog decision-13）。BlockingGate の待機から壁時計の上限を API ごと撤去し、塞ごうとしたスレッドがメインスレッドか協調プールなら塞がずに失敗を記録して戻る。A は「既存の async 注入点が 0 件・2 箇所はテストの意味が消える・新規テストを止められない」、B は「await の有無を grep で判定できない。API から消せばコンパイルで止まる」、C は「3 件中 2 件が TSan 以外」で採らない。理由の全文は ADR。
単純化の検討: 上限が兼ねていた 2 役（足止め / 退行の検出）のうち、検出役は「塞いではいけないスレッドで待った」ことそのものなので、スレッドの検査へ置き換えると上限が不要になる。待機 API は 1 本に減る（wait の fallback / fixedBudget と waitUntilOpen の 2 本立てが消える）。開け忘れ対策のスコープ付きゲートや自己解放は足さない（実測で、開け忘れは混雑に左右されず毎回同じ形で出る。CI で観測されたら .timeLimit と同じ定数の自己解放を足す、と ADR の再検討条件に書いた）。
決定を支える実測（一時パッチ。手元 macOS 27・10 コア。ログは .tmp/t674-spike*.log でリポジトリには含まれない。パッチは破棄済み）:
- キューラベル: 協調プール上は com.apple.root.<qos>.cooperative、Thread 上は com.apple.root.default-qos.overcommit、メインは com.apple.main-thread。プール幅 1 でも同じ。
- 上限なし + 検査の版で swift test --skip befoldCLITests: 通常 2001 テスト pass（36.2 秒）、LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 でも pass（43.7 秒）。検査の発火はスパイク用テストの 2 件（協調プール上・メインスレッド上）だけで、既存の待機への誤発火は 0 件。
- 退行の注入: ViewerDiffPresenter.refresh に index.repositoryRoot の同期呼び出しを足すと、refreshDiffDoesNotBlockMainActorOnRootResolution が 1.0 秒でテスト名つきで落ちた（従来は上限 15 秒待ち）。
- 開け忘れ: 結果を待たないテストは pass（専用 Thread が残るだけ）。結果を待つテストは .timeLimit（60 秒）がテスト名つきで記録するが run は終わらない（300 秒で外から kill）。
未確認: CI の macos-26 でのキューラベル。TSan 下での検査の挙動。BlockingWorkTests への退行注入。いずれも実装サブタスクの AC にした。
decision-13 の本文は空のまま（backlog decision の CLI は create / list だけで本文を書けず、フックが backlog/*.md の直接編集を止めるため）。本文は ADR 0012 にある。

訂正と追記（TASK-674.1 の /review-design で判明、2026-10-06）: 場所の判定を libdispatch のキューラベルから公開 API の withUnsafeCurrentTask + Thread.isMainThread へ替えた（非公開の命名への依存を避ける。チェック項目 1）。この版で実測を取り直した: swift test --skip befoldCLITests は通常（37.6 秒）・プール幅 1（42.7 秒）とも、既存の 1998 テストに検査の誤発火 0 件。検査は協調プール上のタスク・MainActor 上のテスト本体・メインキューのコールバックで発火し、withBlockingWork の専用 Thread 上では発火しなかった。退行の注入（ViewerDiffPresenter.refresh へ同期のルート解決）は 1.1 秒でテスト名つきの失敗。先の Notes の「2001 テスト」はスパイク用の 3 テストを含む数で、既存は 1998。スパイクの変更はすべて破棄済み（git status で確認）。サブタスクは TASK-674.1 の 1 件（API を消すと全呼び出し元が同時に移る必要があり、分けられない）。/review-design の結論は TASK-674.1 の Implementation Plan に反映した（AC#3 / AC#4）。

完了時の確認（2026-10-06）: このタスクは調査と設計だけで、Swift の変更は無い（git status は backlog と docs/adr のみ。スパイクは破棄済み）。そのため swiftformat / swift test / swiftlint ベースライン / xcodebuild は対象外。文書の検査は ADR 0012 に対して tanteki の lint（--type adr）、scripts/check-doc-citations.sh、markdownlint-cli2 がいずれも指摘 0 件。docs/dev/native-app-design.md への反映はこのタスクでは不要（現在の実装は変わっていない。withBlockingWork の節の追随は TASK-674.1 の AC#7 にした）。決めたことの担保: 「上限を持たない」は引数の無い API（TASK-674.1 AC#1）、「検査が効く」は検査を外すと落ちるテスト（同 AC#2）、棚卸しした箇所の移行は API の削除によるコンパイルエラー（同 AC#3）。担保を置かないと決めたもの（defer での解放、セマフォによる足止めの自作）は ADR の Consequences に理由と再検討条件を書いた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
同じ型の失敗 3 件（TASK-619 / 665 / 672）に対し、同期ゲート BlockingGate の待機から壁時計の上限を API ごと撤去し、閉じたゲートをメインスレッドか Swift Concurrency のタスクの上で待とうとしたら塞がずに失敗を記録する、という構造を決めた（ADR 0012 / decision-13）。棚卸しでは、同期に塞ぐ 6 箇所すべてが専用スレッド上で待っており、既存の async 注入点は 0 件、同じ型の露出が残るのは GitStatusStoreTests（fixedBudget 300）だった。A（AsyncGate へ移す）は注入点が無く 2 箇所でテストの意味が消えるため、B（検査スクリプト）は await の有無を grep で判定できないため、C（TSan を絞る）は 3 件中 2 件が TSan 以外で起きたため採らない。上限が兼ねていた 2 役のうち退行の検出は場所の検査で置き換わるので、待機 API は 1 本に減る。一時パッチでの実測: 既存 1998 テストに誤発火 0 件（通常・プール幅 1）、退行の注入は 1.1 秒でテスト名つきの失敗、開け忘れは混雑に左右されず毎回同じ形で出る。実装は TASK-674.1 に起票し、/review-design を回して判定方法をキューラベルから公開 API（withUnsafeCurrentTask）へ直した。CI の macos-26 と TSan 下での検査の挙動は未確認で、TASK-674.1 の AC にしてある。
<!-- SECTION:FINAL_SUMMARY:END -->
