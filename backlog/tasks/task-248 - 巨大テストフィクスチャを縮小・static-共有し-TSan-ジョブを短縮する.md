---
id: TASK-248
title: 巨大テストフィクスチャを縮小・static 共有し TSan ジョブを短縮する
status: To Do
assignee: []
created_date: '2026-08-01 10:46'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 450000
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
- [ ] #1 対象フィクスチャが検証に必要な最小サイズへ縮小され、サイズの根拠がコメント化される
- [ ] #2 繰り返し生成が static 共有で 1 回化される
- [ ] #3 各テストの検証マージン(ガード条件)が維持される
- [ ] #4 swift test(通常 + TSan)が全てグリーン
<!-- AC:END -->
