---
id: TASK-672
title: >-
  ViewerRendererRenderRaceTests の SlowFileReader が thread-sanitizer ジョブでゲート待ち
  120 秒の上限に達して落ちる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-06 02:54'
updated_date: '2026-10-06 05:59'
labels:
  - bug
  - test
dependencies: []
references:
  - TASK-665
  - TASK-629
priority: medium
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-10-06、main push（PR #713 のマージコミット 0807c484）の CI run 37401520728 で thread-sanitizer ジョブだけが落ちた。`ViewerRendererRenderRaceTests.swift:251` で「SlowFileReader.readData: 同期待機が 120.0 秒で上限に達した（解放されないまま協調スレッドを塞いでいる）」が 1 件記録された（テスト名は «unknown» で、SlowFileReader を使う 3 テストのどれかは特定できていない）。プロセスは死んでおらず、総括行「Test run with 1997 tests in 329 suites failed ... with 1 issue」が出ている。DEADLYSIGNAL / SEGV は 0 件で、TASK-629（SEGV でプロセスごと落ちる）とは別の障害。同系統は TASK-665（並列時のゲート待ち上限超過。別テストで async の境界へ移して解消済み）。同じ run では全体が 363 秒かかり、多くのテストが 360 秒前後で完了しており、TSan 下の極端な混雑だった。同じ run の build-and-test（default / strict）は pass で、PR #713 は Swift に触れていない。未確認: 原因が混雑だけか（ゲートが塞ぐ協調スレッドが待ち先の進行を止めていないか）、再現率、TSan でしか出ないのか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 落ちたテストがどれかと、上限超過の条件（混雑だけか、塞いだ協調スレッドが待ち先の進行を止めているか）を実測で特定している
- [x] #2 ゲートの上限を延ばす形ではなく、待ちの構造（TASK-665 と同じく async の境界へ移す等）で直っている
- [ ] #3 swift test --sanitize=thread を同一ツリーで複数回まわし、当該テストが再発しないことを実測している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BlockingGate に waitUntilOpen()（壁時計の上限を持たない待機）を足す。doc に前提を書く: 専用 Thread 上でのみ使う（協調プールを塞ぐと TASK-424）、開ける側が必ず open() する。既定の wait（env 由来の上限）は変えず他のテストへ波及させない
2. SlowFileReader.readData を releaseGate.waitUntilOpen() に替える（絞り込み点。3 候補テストを一括で直す）
3. 閉じたゲートを作る 3 テストの本体で defer { gate.open() } を置き、キャンセル・早期抜けでも必ず解放する（open() は冪等）
4. BlockingGateTests に、waitUntilOpen が open() まで戻らず open() 後に戻る（上限なし）ことを測るテストを足す
5. 検証: swift test 全体、CPU 負荷 40 本（再現条件）で複数回。決定的な再現手段が無い（1/3）ので、「修正を戻すと落ちる」は示せない。代わりに同負荷で SlowFileReader.readData の issue が 0 件であること、残る失敗の種類（SEGV・WKWebView）を別物として記録する

設計レビューの結論（/review-design、2026-10-06）: (1) 判定の真実の源: 該当しない（データの形で判定していない）。(2) 不変条件: BlockingGate の doc は『同期ブロックに無期限を許すと協調プールを永久に塞ぐ』を理由に無期限を避けている。ここは embeddedContent → withBlockingWork（専用 Thread、BlockingWork.swift）→ RenderableContent.make → readData なのでプール外（コード参照）。waitUntilOpen は専用 Thread 限定と doc に明記する。(3) 消費経路: SlowFileReader の利用は RenderRace 2 + ContentUpdateIntegration 1 の計 3 テスト（rg 実測）。フェイク側で直し、3 テストに defer を置く。兄弟（未対応）: BlockingGate を env の上限で使う他のテスト（GitCommandFileIndexConcurrencyTests / ViewerWindowControllerDiff*Tests など）は同じ型の露出を持つが、失敗の観測は無い。GitStatusStoreTests は fixedBudget: 300 で別対処済み（TASK-619）。本タスクでは触らず、観測されたら別タスクにする。(4) 表示: 該当しない（テストのみ）。(5) 順序: defer の open() は本体の open() と冪等（BlockingGate.open は opened フラグ）。解放後に走る再描画は今も起きている形で新しい露出ではない。(6) 高頻度経路: 該当しない。(7) 測るもの: 外すのは「ゲートが N 秒で開く」という検査で、テストが守る競合の意味は変わらない。残る上限は .timeLimit（既定 10 分、CI に上書きなし。Waiting.swift の doc どおり run 全体の壁時計）。実測の最長は CI 363 秒・C40 461 秒で余裕は 140 秒以上。それを超える輻輳は名前付きの失敗（.timeLimit）として出る。(8) 世代管理: 該当しない。(9) 担保: 無期限が安全な条件は『開ける側の保証』。解放を忘れたテストは、待機側ではなく waitUntilYielding の 100000 回上限で『どのテストか名前付き』の失敗になる（推定。未実測）。API の挙動は BlockingGateTests で直接測る。(10) 型グループ: ViewerRendererRenderRaceTests は 256 行（check-type-group-size 実測）、追加は数行。BlockingGate にメソッド 1 つ。プロトコル準拠・クロージャ・stored property は増えない。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
測定（2026-10-06、手元 10 コア。全実験 BEFOLD_TEST_TIMEOUT_SECONDS=120 + --sanitize=thread。ログは .tmp/ の t672-* と t672b-*、リポジトリには含まれない）:
- 無負荷: スイート単体 0/20、全体（--skip befoldCLITests）0/3（123〜132 秒）。CI は 363 秒かかっており、混雑の再現ができていなかった。
- 協調プール幅 1（LIBDISPATCH_COOPERATIVE_POOL_STRICT=1）: スイート単体 0/10、全体 0/3。TASK-665 と同じく「協調スレッドが塞がれている」説は支持されない。
- CPU 負荷（yes 20 本）: 全体 0/1（229 秒）。1 回なので「出ない」とは言えない。
- CPU 負荷（yes 40 本）: 全体 3/3 で何らかの失敗。内訳は (1) ThreadSanitizer の SEGV（libsystem_malloc。166 秒で落ち、総括行なし。TASK-629 の署名に近いが別物かは未調査）、(2) ViewerRendererOneShotIntegrationTests の WKWebView エラー（別の失敗）、(3) TASK-672 の issue そのもの（ViewerRendererRenderRaceTests.swift:251、「同期待機が 120.0 秒で上限に達した」、Test «unknown»、462.993 秒、プロセス生存、スイート自体は pass）。
- 結論（実測）: 再現は 3 回中 1 回（C40-3）。全体が 400 秒前後まで伸びる混雑と結びつく。CI の 363 秒に近い条件。
- 未確認（推定）: 終了後の再描画が同じフェイクをもう一度呼び、誰も解放しない待機が上限に達した形（BlockingGate の doc にある TASK-427 の型）に見える。根拠は «unknown» への帰属とスイート自体が pass していること。確かめるには diffStateIsNotConfirmedBeforeRender 等でゲートを開く前にテストが抜ける経路を読み、ゲートを開く直前の主キュー遅延を測る。
- 未確認: 負荷 40 本は CI（コア数の少ないランナー）と構造が同じとは限らない。再現率を比べるなら同じ負荷で 10 回程度の追加が要る。CI のコア数と並列度は未確認（gh run view 37401520728 --log で見られる）。
- 着手の手がかり: AC#1 のうち「落ちたテストの特定」は未達（«unknown» のまま）。「協調スレッドが塞がれているか」は否定できた。

原因の特定（2026-10-06、CI run 37401520728 の thread-sanitizer ログとコード参照。AC#1 の「条件」は特定、「どのテストか」は 2 件まで絞った）:
- 実測（時刻）: スイートの 4 テストは 01:58:18.84 に同時開始。issue は 02:03:10.01（開始 + 291 秒）に記録され、4 テストの完了は 02:03:50〜02:04:24（開始 + 332〜362 秒）。つまり issue は**テストの実行中**に出ている。BlockingGate の doc（TASK-427）の「テスト終了後の再描画が同じフェイクを呼んだ」型ではない。C40-3 でも同じ順序（issue が 4086 行、4 テストの完了が 4445〜5052 行）。
- 実測（所要）: 同じ 4 テストは単独実行で合計 0.015 秒。CI では各 332〜362 秒、C40-3 では 430〜461 秒かかった。待っていたのは MainActor の順番（`waitUntilYielding` の Task.yield）で、スイート自体が極端な混雑の中にあった。
- 推定（上の時刻からの算術）: 上限が 120 秒（CI の env は BEFOLD_TEST_TIMEOUT_SECONDS=120、ログで確認）なので、readData の待機は開始 + 約 171 秒に始まり、291 秒までゲートが開かれなかった。ゲートを開くのはテスト本体（MainActor）で、`entered` を観測する `waitUntilYielding` を抜けてから `gate.open()` までは await が無い。よって「`entered` が立ってから、テストが MainActor の順番を得るまで」が 120 秒を超えた。
- コード参照: `Test «unknown»` になるのは、`SlowFileReader.readData` が `withBlockingWork` の専用 Thread（BefoldKit/BlockingWork.swift）で走り、Thread は Swift Testing のテスト文脈を引き継がないため。issue は常に «unknown» になる（TASK-427 型だけの目印ではない）。この Thread は協調プールの外なので、TASK-424 の「プール枯渇」とは別。実験 A/B（プール幅 1 で 0/13）とも整合する。
- 候補テスト（実測では未特定）: SlowFileReader に閉じたゲートを渡すのは diffStateIsNotConfirmedBeforeRender と staleImageEmbedDoesNotClobberNewerRender の 2 件。どちらも解放側が MainActor の await 越し。残り 2 件（directHTMLExit…、pendingDiffHoldsPreviousFrame…）は閉じたゲートを使わない。ラベルが共通の "SlowFileReader.readData" なので issue からは区別できない。
- 構造上の原因: 解放が MainActor の順番待ちに左右されるのに、待機側は壁時計の上限（env 由来 120 秒）を持つ。輻輳が 120 秒を超えると、テストが正しくても落ちる。TASK-619 の fixedBudget の doc と同じ型。TASK-665 は待ちを async の境界（AsyncGate）へ移して壁時計を不要にしたが、ここの readData は同期プロトコル（FileReading）なので同じ移し方はできない。
- 未確認: どちらのテストか。両者の差を測るには、ラベルをテストごとに分ける（例: "SlowFileReader.readData(diffState…)"）。

訂正（/review-design で判明）: 先の Notes の「候補テストは 2 件」は誤り。issue の発生元 :251 は共有フェイク SlowFileReader.readData の行で、このフェイクは ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS（同じ「テストが entered を待ってから gate.open()」構造）も使う。CI ログでも同テストは issue 時点（開始 + 291 秒）に実行中で 361 秒で完了している。よって候補は 3 件（RenderRace の diffStateIsNotConfirmedBeforeRender / staleImageEmbedDoesNotClobberNewerRender、ContentUpdateIntegration の abortedRenderDoesNotLeaveOptionsInJS）。3 件とも共有フェイクの待機が原因なので、フェイク側（絞り込み点）で直せば区別は要らない。

実装と検証（2026-10-06）: BlockingGate.waitUntilOpen()（上限なし）を足し、SlowFileReader.readData をそれに替え、閉じたゲートを作る 3 テストに defer { gate.open() } を置いた（RenderRace 2 + ContentUpdateIntegration 1）。BlockingGateTests に「open() まで戻らず、open() で戻る」を追加。通常実行は 9 件 pass、swiftformat --lint / swiftlint は新規指摘なし。
- 負荷下の実測（TSan、yes 40 本、BEFOLD_TEST_TIMEOUT_SECONDS=120、全体実行 6 回、ログは .tmp/t672c-C40-{1..6}.log）: (a) SlowFileReader.readData の「同期待機が」issue は 0/6、(b) SEGV は 0/6、(c) その他の失敗は 1/6、全 pass は 5/6。所要時間 439〜777 秒（CI の 363 秒、修正前 C40-3 の 463 秒と同程度かそれ以上の混雑）。
- 限界（実測）: 修正前は 1/3、修正後は 0/6。修正前の率が 1/3 のままなら 6 回で 0 件になる確率は約 9% で、有意差が取れる標本ではない。決定的な再現手段が無いので「修正を戻すと落ちる」は示せていない。
- 未解決（実測）: run3 で ViewerRendererContentUpdateIntegrationTests.abortedRenderDoesNotLeaveOptionsInJS が .timeLimit の 600 秒で落ちた（754 秒）。他のテストが約 445 秒で pass する中、このテストだけが終わらなかった。「同期待機が」issue は出ていない。実 WKWebView の待ち（waitForWebViewLoad / evaluateJavaScript）がある唯一のテストだが、どの await で止まったかは未確認。修正由来か既存の flaky かも未判定（修正前ツリーでの同条件の測定が無い）。別タスクへ切り出した。
- AC#1（落ちたテストの特定）は未達のまま: 候補 3 件（共有フェイクの issue のためテストへ帰属しない）。AC#3 は 0/6 までで、上の限界により再発しないことの実測とは言えない。
<!-- SECTION:NOTES:END -->
