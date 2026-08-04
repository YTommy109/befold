---
id: TASK-116.7
title: 固定 sleep・過大フィクスチャ・実時間性能アサーションを整理する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:19'
updated_date: '2026-07-24 00:43'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 30700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テスト実行時間に無条件で乗るコストと、共有ランナー上で本質的にフレーキーな検証を取り除く。

## 1. DebouncerTests の無条件 1.8 秒

`BefoldApp/befoldTests/DebouncerTests.swift` の :19(0.5s) / :38(0.5s) / :55(0.3s) / :76(0.5s) が固定 `Task.sleep`。Debouncer の delay は 0.1 秒なので、成功していても毎回 0.5 秒待つ。

coding_rule.md:623 の「『発火する』の検証は固定 sleep ではなく `waitUntil` で条件成立を待つ」に明確に違反。`firesAfterDelay`(:8) / `coalescesRapidCalls`(:24) / `reschedulesAfterCancel`(:61) の 3 つは肯定的検証なので `LockedBox` + `waitUntil` に置換でき、約 1.3 秒短縮できる。

`cancelPreventsExecution`(:43)の 0.3s だけは否定的検証なので固定待ちが妥当。ただし delay 0.1s に対して 3 倍とする根拠のコメントが無く、coding_rule.md:625-627 の「待機時間の根拠をコメントに書く」を満たしていない。

## 2. 過大なフィクスチャ

`BefoldApp/befoldTests/NormalizedTextCacheLazyGrowthTests.swift:32` の `makeLines(2_000_000)` は約 22MB の文字列を 200 万回の補間 + join で構築する、単一で最も重いテスト。しかし検証内容は `first.text.utf8.count < fileSize / 4`(:45)だけで、チャンクは約 1000 行(約 9KB)。**サイズが load-bearing でない**ため 20 万行でも同じ結論が出る。コメント :28-31 の「20MB 超が代表サイズ」という主張も実際には検証に効いていない。

## 3. 実時間の性能アサーション

`BefoldApp/befoldTests/TextEncodingTests.swift:45-58` `detectEncodingStaysFastForLargeLegacyData` は 5MB の Shift_JIS を生成した上で `#expect(elapsed < .seconds(3))` を課す。共有 CI ランナー・TSan ジョブでは本質的にフレーキーで、失敗時は 3 秒を必ず消費する。性能回帰の検知が目的なら「線形性の検証(小/大 2 サイズの比が上限以下)」への置換、または環境変数によるスキップを検討すること。

## 4. 理由の無い .serialized

`BefoldApp/befoldTests/StringChunkReaderTests.swift:5` に `@Suite(.serialized)` が付いているが理由コメントが無い。他の 2 つの `.serialized` スイート(`FileWatcherIntegrationTests.swift:5-10`、`ViewerStoreIntegrationTests.swift:5-7`)は理由を明記しており不統一。18 テスト(うち複数が MB 級フィクスチャ)を直列化しているため、不要なら並列化で短縮できる。

## 参考: 既存の良い設計

`BefoldApp/befoldTests/TestClock.swift` + `ViewerStoreFileGoneTests.swift:9-38` の `AsyncGate` によるグレース期間テストは、仮想クロックで実時間ゼロを達成している模範例。FileWatcher / ViewerStore の統合テストもこの方式に寄せられないか、あわせて検討する価値がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Debouncer の肯定的検証が固定 sleep ではなく条件待ちで書かれている
- [x] #2 否定的検証として残す固定待ちには、待機時間の根拠がコメントされている
- [x] #3 テストフィクスチャのサイズが、検証内容に対して過大でない
- [x] #4 共有ランナー上でフレーキーになる実時間の性能アサーションが残っていない
- [x] #5 すべての .serialized スイートに直列化の理由が記載されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DebouncerTests: 肯定的検証 3 本(firesAfterDelay / coalescesRapidCalls / reschedulesAfterCancel)の固定 sleep を LockedBox + waitUntil の条件待ちに置換した。confirmation は規約どおり維持し、待ち方だけを変えている。coalescesRapidCalls は「1 回で止まる」ことまで見ないと合一の検証が成立しないため、初回発火を条件待ちしたあと静穏待ちを入れて #expect(fireCount == 1) を追加した(従来は confirmation の expectedCount 任せで、固定 sleep 中に追加発火が無いことを暗黙に期待していた)。否定的検証の cancelPreventsExecution は条件待ちにできないため固定待ちを残し、delay の 3 倍という根拠を settlePeriod として名前付き定数＋コメントで明示した。実測: 従来は 0.5+0.5+0.3+0.5=1.8 秒の固定待ちだったが、firesAfterDelay 0.161s / reschedulesAfterCancel 0.161s / cancelPreventsExecution 0.320s / coalescesRapidCalls 0.474s、スイート全体 0.475 秒。

NormalizedTextCacheLazyGrowthTests: singleChunkReadKeepsNormalizedRangeMuchSmallerThanFileSize のフィクスチャを 2,000,000 行から 400,000 行へ縮小した。縮小前に一時計測で実測したところ fileSize=22,888,890 / chunk=7,890 バイトで、チャンクサイズは linesPerChunk 行分で決まりファイルサイズに比例しない(サイズは検証に効いていない)ことを確認した。あわせてアサーションを fileSize/4 の相対比較から 64KB の絶対値へ変更した。相対比較はフィクスチャを大きくするほど条件が緩くなり検証の意味が薄れるため。normalizationWindowBytes(2MiB)を十分超える条件は 400,000 行(約 4.4MB)でも満たす。実測 0.171 秒。

TextEncodingTests: detectEncodingStaysFastForLargeLegacyData の #expect(elapsed < .seconds(3)) を廃止し、detectEncodingCostDoesNotScaleWithDataSize に置き換えた。絶対値は共有 CI ランナーや TSan 計装下のマシン速度に左右されてフレーキーになるうえ、全走査への退行も 3 秒未満なら見逃す。同一マシン上で small(5,000 行)と large(100,000 行、20 倍)を計測し、elapsedLarge < elapsedSmall * 5 + 50ms を検証する形にした。全走査していれば概ね 20 倍になるため線形走査を検出できる。3 回連続実行で 0.282 / 0.296 / 0.285 秒と安定。

StringChunkReaderTests: 理由コメントの無かった @Suite(.serialized) を除去した。共有可変状態(static var / nonisolated(unsafe))も実ファイル I/O も無い純粋なメモリ内テストで、直列化の根拠が無いため。3 回連続実行で 18 tests が 0.249 / 0.244 / 0.245 秒と安定して pass することを確認した。残る 2 つの .serialized スイート(FileWatcherIntegrationTests / ViewerStoreIntegrationTests)は既に理由が明記されている。

全体検証: swift test が 593 tests / 77 suites を 16.851 秒で pass。SwiftFormat --lint は全ターゲットでクリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
固定 sleep・過大フィクスチャ・実時間の絶対値アサーション・根拠の無い直列化を整理した。

Debouncer の肯定的検証 3 本を条件待ちに変え、合一テストには「1 回で止まる」ことの明示的な検証を追加。否定的検証に残した固定待ちには delay の 3 倍という根拠を名前付き定数で示した(1.8 秒の固定待ち → スイート全体 0.475 秒)。

NormalizedTextCache の最重量フィクスチャは、一時計測でチャンクサイズがファイルサイズに比例しない(22.9MB でもチャンク 7,890 バイト)ことを実測した上で 2,000,000 行 → 400,000 行に縮小し、緩くなりがちな相対比較を絶対値に変更した。

TextEncoding の「3 秒以内」という絶対値は、マシン速度でフレーキーになるうえ全走査への退行を 3 秒未満なら見逃すため、同一マシン上の 20 倍データとの相対比較に置き換えて線形走査を検出できるようにした(3 回連続実行で安定)。

StringChunkReaderTests の根拠不明な .serialized は、共有可変状態も実 I/O も無いことを確認して除去し、3 回連続実行で安定を確認した。

検証: swift test が 593 tests / 77 suites を 16.851 秒で pass、SwiftFormat --lint クリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
