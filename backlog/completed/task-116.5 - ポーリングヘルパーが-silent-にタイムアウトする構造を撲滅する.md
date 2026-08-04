---
id: TASK-116.5
title: ポーリングヘルパーが silent にタイムアウトする構造を撲滅する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:19'
updated_date: '2026-07-24 00:22'
labels:
  - test
  - ci
dependencies: []
parent_task_id: TASK-116
priority: high
ordinal: 30500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ブランチ以前から存在する構造的欠陥。テストが「10〜15 秒を丸ごと浪費した上でグリーンになる」ため、壊れた検証が壊れたまま通り続ける。

## 1. 全ポーリングヘルパーがタイムアウトを呼び出し側に伝えない

| ヘルパー | 定義 | 既定タイムアウト | 戻り値 |
|---|---|---|---|
| `waitUntil` | `BefoldApp/befoldTests/TestSupport.swift:91-100` | 10 秒 | Void |
| `waitUntilOnMainActor` | 同 :104-114 | 10 秒 | Void |
| `waitUntilWithRetry` | 同 :120-134 | 15 秒 | Void |
| `waitUntilWithRetryOnMainActor` | 同 :139-153 | 15 秒 | Void |
| `waitUntilYielding` | `BefoldApp/befoldTests/TestClock.swift:120-126` | maxYields 100,000 | Void |

いずれも `while` を抜けた後に何もせず return するだけで、`Issue.record` も `#expect` も無い。

## 2. 直後にアサーションが無く、丸ごと silent に浪費し得る箇所

- `BefoldApp/befoldTests/FileWatcherIntegrationTests.swift:86` — `waitUntil { count.get() > beforeDelete }` の直後にアサーションが無い。削除イベントが来なければ 10 秒浪費して素通りし、後続の検証は「削除が反映された前提」で走る
- 同 :27 / :80 / :132 / :183 / :231 — `confirmWatcherArmed`。内部(TestSupport.swift:179-184)の `waitUntilWithRetry` が arm 失敗を検知しないため 1 呼び出しあたり最大 15 秒を silent に消費。さらに :80 / :132 / :183 は戻り値を `_ =` で捨てており、arm 確認が成立したかを誰も見ていない
- `BefoldApp/befoldTests/ViewerStoreIntegrationTests.swift:39-44` — `waitUntilWithRetryOnMainActor` の直後にアサーションが無い

## 3. confirmWatcherArmed の静穏ループにデッドラインが無い

`BefoldApp/befoldTests/TestSupport.swift:185-191` の `while true` は、コールバックが `quiescePeriod`(既定 0.3 秒)ごとに 1 回でも入り続ける状況(CI 高負荷時の debounce 残、他テストの FS 操作)では永久に抜けない。`.timeLimit(.minutes(1))` が最後の砦になっているだけで、その場合 1 テストで 60 秒を焼く。

## 4. .timeLimit の付与範囲が狭い

`.timeLimit` が付いているのは `DebouncerTests` / `FileWatcherIntegrationTests` / `ViewerStoreIntegrationTests` の 3 ファイルのみ。非同期テストは 110 件ある。ポーリングを含むのに `.timeLimit` が無い例: `ViewerWindowControllerToolbarTests.swift:61,:84`、`ViewerStoreFileGoneTests.swift:106,:139,:179,:226,:313,:354`。

## 設計上の推奨

ヘルパー内部でタイムアウト時に `Issue.record(..., sourceLocation:)` を記録する形にすれば、既存の全呼び出し側を一切変更せずに silent green を撲滅できる(`sourceLocation: SourceLocation = #_sourceLocation` を引数に追加)。実装時にこの案と「Bool を返して呼び出し側に検証を強制する」案を比較検討すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 条件が成立しないままタイムアウトしたポーリングは、必ずテスト失敗として報告される
- [x] #2 confirmWatcherArmed の静穏待ちが有限時間で必ず終了する
- [x] #3 ポーリングを含む非同期テストにタイムアウト上限が設定されている
- [x] #4 既存の全呼び出し箇所が、タイムアウトを検知する形に移行済みである(戻り値を握り潰している箇所が残っていない)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldTestSupport/Waiting.swift に import Testing を追加し、全ポーリングヘルパーを「タイムアウト時に Issue.record してテストを失敗させる」形に変える。
   - 各ヘルパーに sourceLocation: SourceLocation = #_sourceLocation を追加し、失敗を呼び出し側の行に紐づける。
   - 戻り値を Bool(@discardableResult)にする。ヘルパー自身が失敗を記録するため、呼び出し側が戻り値を無視しても silent にはならない。
   - 設計判断: 「Bool を返して呼び出し側に #expect を強制する」案と比較した結果、Issue.record 方式を採る。既存 22 箇所を書き換えずに済むだけでなく、将来追加される呼び出し箇所でも自動的に検知できるため、穴が再発しない。
   - BefoldTestSupport への Testing 依存追加は、平のターゲットでも import できることをビルドで確認済み。GUI 本体(befold)は BefoldTestSupport に依存しないためアプリ側への影響はない。TASK-116.3 で coding_rule.md に書いた「依存は Foundation のみ」の記述は「GUI 本体・BefoldRenderKit を引き込まない」に改める。

2. TestClock.swift の waitUntilYielding も同様に Issue.record 化する(maxYields 到達 = 条件不成立)。

3. befoldTests/TestSupport.swift の confirmWatcherArmed の静穏ループ(while true)にデッドラインを設ける。到達時は Issue.record する。あわせて arm 確認自体の失敗も検知する。

4. ポーリングを含むのに .timeLimit が無いスイートに付与する(ViewerWindowControllerToolbarTests、ViewerStoreFileGoneTests ほか)。

5. 検証: swift test を実行し、これまで silent にタイムアウトしていた箇所が顕在化しないか確認する。顕在化した場合はそれが本物の不具合か待機時間不足かを切り分ける(このタスクの目的そのもの)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
設計判断: 「Bool を返して呼び出し側に #expect を強制する」案ではなく、ヘルパー自身が Issue.record する案を採用した。既存 22 箇所を書き換えずに済むだけでなく、将来追加される呼び出し箇所でも自動的に検知でき、穴が再発しないため。sourceLocation: SourceLocation = #_sourceLocation により失敗は呼び出し側の行に紐づく(実際に ViewerStoreFileGoneTests.swift:107 と特定できた)。BefoldTestSupport に Testing 依存が増えるが、平のターゲットでも import できることをビルドで確認済みで、GUI 本体は BefoldTestSupport に依存しないためアプリ側への影響はない。

★ この仕組みが即座に実欠陥を 1 件検出した(AC#1 の最良の実証):
ViewerStoreFileGoneTests.swift の staleLoadIsDiscarded が、名乗っている「追い越しによる破棄」を一度も検証していなかった。factory の判定が `cache.text.hasPrefix("slow")` だったが、NormalizedTextCache(normalizeFully: false) の遅延正規化により factory 呼び出し時点の cache.text は空。一時的な計測で `DIAG factory cache.text=[]` を実測して確定した。その結果、両方のファイルで MockChunkedReader(chunks: ["fast\n"]) が返り、(1) slowReader が一度も使われず entered が true にならないため waitUntilYielding が 10 万回 yield して約 11 秒を浪費、(2) #expect(store.content == "fast\n") はモックが常に "fast\n" を返すので自明に成立、という二重の空振りになっていた。

これが本タスク以前からの状態であることは、レビュー初期に取得した CI ログ(run 29992320125、変更前)で同テストが passed after 11.529 seconds と記録されていることで裏付けられる。

修理: 判別を呼び出し順(LockedBox のカウンタ)に変更した。同ファイルの loadMoreLinesDropsResultAfterReload が既に採っている isFirstFactoryCall と同じ流儀。11.529 秒 → 0.003 秒。

修理後のテストが本当に回帰を検出することをミューテーションで実証した: ViewerStore.performLoad の `generation == loadGeneration` ガードを外すと、store.content が "slow\n"、store.filePath が slow.csv になってテストが失敗する(2 issues)。修理前はこの変異を素通りさせていた。

検証:
- AC#1: 上記のとおり、実際に silent タイムアウトを検出して失敗させられることを実例で確認。
- AC#2: confirmWatcherArmed の静穏ループに quiescePeriod * 20 の期限を設け、到達時は Issue.record する。while true は解消。
- AC#3: ポーリングを含むのに .timeLimit が無かった ViewerStoreLoadRaceTests / ViewerStoreFileGoneTests / ViewerWindowControllerToolbarTests に .timeLimit(.minutes(1)) を付与。
- AC#4: ヘルパー自身が失敗を記録する方式のため、戻り値を無視している箇所があっても silent にはならない(@discardableResult は判定に使いたい場合のためだけ)。
- 全体: swift test が 593 tests / 77 suites を 14.105 秒で pass。SwiftFormat --lint は全ターゲットでクリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
全ポーリングヘルパー(waitUntil / waitUntilOnMainActor / waitUntilWithRetry / waitUntilWithRetryOnMainActor / waitUntilYielding)が Void を返し、条件が永久に false でも所定秒数(10〜15 秒)を丸ごと浪費した上でグリーンになる構造を解消した。

「Bool を返して呼び出し側に #expect を強制する」案と比較した上で、ヘルパー自身が Issue.record する方式を採用。既存 22 箇所の書き換えが不要なだけでなく、将来追加される呼び出し箇所でも自動的に検知でき穴が再発しない。sourceLocation の既定引数により失敗は呼び出し側の行に紐づく。あわせて confirmWatcherArmed の無限静穏ループに期限を設け、.timeLimit の無かった 3 スイートに付与した。

導入直後にこの仕組みが実欠陥を 1 件検出した。staleLoadIsDiscarded が名乗る「追い越しによる破棄」を一度も検証しておらず、約 11 秒を浪費したままグリーンだった(変更前の CI ログでも 11.529 秒と記録されており、以前からの状態であることを裏付けた)。原因は factory の判別に使う cache.text が遅延正規化のため呼び出し時点で空だったことで、一時計測により実測確定。判別を呼び出し順に変えて 0.003 秒に短縮し、修理後のテストが回帰を検出することを ViewerStore の generation ガードを外すミューテーションで実証した。

検証: swift test が 593 tests / 77 suites を 14.105 秒で pass。SwiftFormat --lint は全ターゲットでクリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
