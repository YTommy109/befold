---
id: TASK-248
title: 巨大テストフィクスチャを縮小・static 共有し TSan ジョブを短縮する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-01 10:46'
updated_date: '2026-08-02 03:35'
labels: []
dependencies: []
priority: low
type: task
ordinal: 452500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TSan 計装下では文字列生成・走査が数倍に膨らむため、巨大フィクスチャの縮小は thread-sanitizer ジョブ(現状 3〜4.5 分、main push + nightly)に特に効く。
- NormalizedTextCacheLazyGrowthTests.swift:17, 31, 49: 約 4.5MB の文字列(makeLines(400_000))を 3 テストで毎回生成。閾値 normalizationWindowBytes = 2MiB に対し約 2 倍の過剰供給。static let で 1 回生成に共有し、2MiB 窓を確実に超える最小限(目安 220_000 行)へ縮小。:33 のガード(> 4MiB)も閾値に揃える。:59 の maxChunkBytes * 5 も * 2 程度で検証可能
- StringChunkReaderTests.swift:127-135 unbalancedQuoteLargeCSVIsChunked: rowCount 300_000(約 300 チャンク)は「復帰すれば多数チャンク/失敗すれば少数チャンク」の二値判別に 6 倍過剰。50_000 に縮小しアサーションのマージン(40 倍)を維持。同ファイルの他の 1〜3MB 級フィクスチャ(:147, :166, :227, :267)は maxChunkBytes 境界検証に本質的に必要なので現状維持
- TextEncodingTests.swift:52-53 detectEncodingCostDoesNotScaleWithDataSize: small 5,000 行 / large 100,000 行(約 9MB)の Shift_JIS 変換。検証は比率(20 倍)と small ≫ sniffLength(8KB)だけなので 1,000 行 / 20,000 行で足りる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 対象フィクスチャのサイズ根拠がコメント化される(実測でCI時間短縮効果がないため縮小はしない)
- [x] #2 繰り返し生成が static 共有で 1 回化される
- [x] #3 各テストの検証マージン(ガード条件)が維持される
- [x] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ユーザー判断により衛生目的に限定(サイズ縮小は行わない)。実測で CI 時間短縮効果がないことは Notes 済み
2. NormalizedTextCacheLazyGrowthTests: makeLines(400_000) の 3 回生成を static let で 1 回化し、サイズの根拠(2MiB 窓を超える必要がある等)をコメント化
3. StringChunkReaderTests / TextEncodingTests: 各巨大フィクスチャのサイズ根拠をコメント化(縮小はしない)
4. AC を実態に合わせて調整し swift test で検証
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前の実測により、本タスクの前提(巨大フィクスチャの生成コストが CI 時間に効く)が誤りであることが判明した。実施は非推奨。
実測(2026-08-01、test/improve_test ブランチ):
- 対象 3 スイートの単独実行: NormalizedTextCacheLazyGrowthTests 0.156s / StringChunkReaderTests 0.150s / TextEncodingTests 0.304s(合計 0.61s)
- 同 3 スイートの TSan 実行: 合計 1.124s(37 tests)
- フィクスチャを半減しても削減は 0.5 秒未満で測定誤差の範囲
起票時は「TSan 計装下では数倍に膨らむため thread-sanitizer ジョブ(3〜4.5 分)に効く」と見積もったが、TSan ジョブの所要は計装ビルドが支配的で、テスト実行部分は 1 秒程度しか占めない(今回の計測でもテスト実行 1.12 秒に対し総所要 26 秒がビルド)。
また全体の律速は GitCommandRunnerResourceLeakTests(13.07s)で、次の床は ViewerStoreIntegrationTests(11.09s)。対象 3 スイートはいずれもクリティカルパスから遠い。
このプロジェクトの backlog には won-t do に相当するステータスが無いため To Do のまま残すが、優先度を Low に下げ、実施しない判断を推奨する。実施する場合は「時間短縮」ではなく「フィクスチャサイズの根拠をコメント化する」衛生目的に限定すること。

実施(2026-08-02): ユーザー判断により衛生目的に限定して実施。サイズ縮小は行わず、根拠のコメント化と static 共有のみ。
- NormalizedTextCacheLazyGrowthTests: makeLines を static 化し largeText(400_000 行)を static let で 1 回生成に共有。3 テストが共有する。singleChunkRead... のガードが fileSize > 4MiB と書かれていたが、コメントが述べる実際の不変条件(normalizationWindowBytes 2MiB を超える)と食い違っていたため 2MiB に揃えた
- ensureNormalizedStopsAtByteTarget の maxChunkBytes*5、incrementalGrowth...HugeSingleLine の *3+12345 に根拠コメントを追加
- StringChunkReaderTests: 根拠未記載だった noNewlineHugeSingleLineIsChunked と forcedSplitRespectsMultibyteCharacterBoundary にコメントを追加。unbalancedQuoteLargeCSVIsChunked と TextEncodingTests は既に十分な根拠コメントがあり変更不要
検証: swift test フル 3 回連続グリーン(948 tests / 142 suites、約 15 秒)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
巨大テストフィクスチャのサイズ根拠をコメント化し、NormalizedTextCacheLazyGrowthTests の 400,000 行フィクスチャを static let 共有で 1 回生成に変更した。前回実測で CI 時間短縮効果がないと判明していたためサイズ縮小は行わず衛生目的に限定した(ユーザー判断)。あわせてコメントとガード条件の食い違い(4MiB vs 2MiB)を実際の不変条件に合わせた。swift test フル 3 回連続グリーンで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
