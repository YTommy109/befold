---
id: TASK-250
title: 同型テストのパラメタライズ化・統合でウィンドウ生成回数と重複を削減する
status: To Do
assignee: []
created_date: '2026-08-01 10:47'
labels: []
dependencies: []
priority: low
type: task
ordinal: 452000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI レビューで見つかった @Test(arguments:) 化・テスト統合の候補。ウィンドウ系はフルウィンドウ構築が 10〜15 枚減る。
ウィンドウ枚数削減:
- ViewerWindowControllerToolbarTests.swift:37-133: 同一セットアップの 3 本(既定アイテム順 / isNavigational / 初期無効)を 1 本へ
- ViewerWindowManagerIntegrationTests.swift:27-106: hiddenFiles 4 本はトリガー(toggleHiddenFiles / delegate 経由)だけの差。パラメタライズまたは統合
- ViewerWindowControllerCLIOptionsTests.swift:90-157: 行番号 override 4 本を (saved, override, expectStore, expectDefaults) の表へ
- ViewerWindowControllerTests.swift:298-325: rename 2 本を (拡張子, 期待値) で
- FileWatcherIntegrationTests.swift:110-204: rename / move の同型ペア(約 45 行 x 2)を移動先クロージャでパラメタライズ
純ロジック:
- QuickOpenQueryTests.swift:6-57(classify 9 本)
- NormalizedTextCacheTests.swift:25-75 / TextEncodingTests.swift:7-43(BOM 系。DefaultFileReaderTests.swift:84-106 が手本)
- WildcardMatcherTests.swift:5-49 / FuzzyMatcherTests.swift:94-134(matchedIndices)
- LocalizationTests.swift:45-57(代表キー。カタログの static キャッシュも同時に)
- ViewerLoadPipelineTests.swift:216-275(charset 3 本)
- ViewerStoreTests.swift:127-231(unsupported の binary/oversized ペア 2 組。:71 に前例あり)
- SwipeHistoryMonitorTests.swift:18-65(左右スワイプ・非通知の鏡像)
- ViewerRendererContentUpdateTests.swift:139-218(canConsumePendingAppend 4 本)
- ViewerRendererMessageHandlingTests.swift:244-339(不正 body 6 本)と :34-66(修飾キー→disposition。未検証の (false,false,.currentTab) も表を埋めて追加)
失敗時にどの入力か判別できるよう CustomTestStringConvertible の流儀(規約参照)に従う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上記候補がパラメタライズまたは統合で整理される(見送る場合は理由を記録する)
- [ ] #2 フルウィンドウ生成回数が 10 枚以上削減される
- [ ] #3 パラメタライズ後も失敗時にどの入力で落ちたか判別できる
- [ ] #4 swift test が全てグリーン
<!-- AC:END -->
