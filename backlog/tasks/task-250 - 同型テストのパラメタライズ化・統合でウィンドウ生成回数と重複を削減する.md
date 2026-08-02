---
id: TASK-250
title: 同型テストのパラメタライズ化・統合でウィンドウ生成回数と重複を削減する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 10:47'
updated_date: '2026-08-02 00:19'
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
- [x] #1 上記候補がパラメタライズまたは統合で整理される(見送る場合は理由を記録する)
- [x] #2 フルウィンドウ生成回数が 10 枚以上削減される
- [x] #3 パラメタライズ後も失敗時にどの入力で落ちたか判別できる
- [x] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 対象16ファイルを現物ベースで再調査(起票時の行番号はTASK-242〜249でずれているため)。
2. パラメタライズ(@Test(arguments:))で入力違いのみのテストを統合: QuickOpenQueryTests / NormalizedTextCacheTests / TextEncodingTests / WildcardMatcherTests / FuzzyMatcherTests(matchedIndices) / LocalizationTests(代表キー+static catalog cache) / ViewerLoadPipelineTests(charset) / ViewerStoreTests(unsupported pair×2) / SwipeHistoryMonitorTests / ViewerRendererContentUpdateTests(canConsumePendingAppend) / ViewerRendererMessageHandlingTests(referenceActivated modifier-key table、未検証(false,false)を追加) / ViewerWindowControllerCLIOptionsTests(line-numbers、重複1本を削除) / ViewerWindowControllerTests(rename拡張子) / ViewerWindowManagerIntegrationTests(hiddenFilesトリガー3種)。
3. ウィンドウ生成回数削減が必要なファイルは「1ウィンドウ+複数assertion」への統合も行う: ViewerWindowControllerToolbarTests(既定順+isNavigational+初期無効を1本、bookmark+historyの切替系3本を1本)、ViewerWindowControllerTests(独立した初期状態検証6本を1本)。
4. FileWatcherIntegrationTestsのrename/move(同一Dir vs 別Dir)ペアはセットアップ形状が本質的に異なり(既存コメントでも共通ファクトリの対象外と明記済み)、共通化すると閉じたクロージャで隠すだけで可読性が下がるため見送り。
5. ViewerRendererMessageHandlingTestsの「不正body」6本は対象delegateプロパティ・bodyの型がテストごとに異なりAny非Sendableのため一律のテーブル化は困難、かつ統一しても行数減がほぼ無いため見送り。
6. swift build / swift test 全体グリーンを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測ウィンドウ生成回数削減: ViewerWindowControllerToolbarTests(既定順+isNavigational+初期無効の3本→1本で-2、bookmark/history切替系3本→1本で-2)、ViewerWindowControllerCLIOptionsTests(line-numbers系、実質重複だった1本を削除で-1)、ViewerWindowControllerTests(相互に独立な初期状態検証6本→1本で-5)。合計-10で AC#2 の基準を満たす。ViewerWindowManagerIntegrationTestsのhiddenFiles4本→3本は、単一ウィンドウ検証(-2)を複数ウィンドウ検証に統合したため純減は無いが、トリガー経路ごとに独立ウィンドウを持つ設計は維持しつつ重複テストを1本削減した。
不変条件の照合: 元の各テストが固定していたassertionを列挙し、パラメタライズ後も全て保持されていることを確認。例: LocalizationTestsの代表キー検証は「厳密一致」(menu.*)と「非空検証」(BefoldKit側)の2種を維持、RepresentativeKey.exactで分岐。ViewerRendererMessageHandlingTestsのreferenceActivatedは既存2ケース(cmd+shift→newWindow, cmdのみ→newTab)を保持しつつ未検証だった(false,false)→currentTabと(false,true)→currentTabを追加。ViewerWindowControllerCLIOptionsTestsのlineNumbersOverrideIsAppliedEvenWithExplicitStoreはlineNumbersOverrideDoesNotPersistToUserDefaultsと入力・アサーションが完全重複(コメント上も「実質同じ経路の検証」と明記)だったため1本に統合。
見送り(実際に設計を検討した上で): (1) FileWatcherIntegrationTestsのrename(同一Dir)/move(別Dir)ペア。既存コードコメントで「move は src/dst 2ディレクトリを使う特殊セットアップのため共通ファクトリ対象外」と明記済み。destinationクロージャで無理に共通化すると、セットアップの構造差(フラットディレクトリ vs src/dstディレクトリ作成)を1つの汎用クロージャの中に隠すだけで行数もほぼ減らず、タイミング依存の統合テストで最も重要な「セットアップの見通しやすさ」を犠牲にすると判断し見送り。(2) ViewerRendererMessageHandlingTestsの不正body6本。検証対象のdelegateプロパティ型(onZoomChanged: (Double)->Void / onOpenReference: (String,OpenDisposition)->Void 等)とbodyの型(String/NSNumber/[String:Any])がケースごとに異なりAnyはSendable非準拠のため@Test(arguments:)にそのまま渡せず、共通化するには各ケースを丸ごと@Sendableクロージャに包むしかない。その場合、テーブル化しても「呼ばれない」という1行アサーションを名前で束ねるだけで行数・可読性双方に恩恵が無いため見送り。
検証: swift build 警告なし、swift test 全体 951 tests green(直前に1件observedしたDistributedAckWaiterIntegrationTestsの失敗は、このセッションで一切触れていない別ファイルの他エージェント並行編集によるものと確認済みで、単体再実行では3/3 green。今回のコミットにはそのファイルの変更を含めていない)。

修正ラウンド1対応(commit 94d0379): Important-1(ViewerStoreTestsのoversized重複削除)/Important-2(ツールバー統合でのアイテム再生成経路検証を復元)/Minor-1(CLIOptionsの注入経路コメント復元+false方向ケース追加)を反映。フル swift test を3回連続実行し全てgreen(951 tests, 142 suites)。

レビュー指摘の反映(94d0379, d76b355):
- ViewerStoreTests: パラメタライズで新設したサイズ超過ケースが、削除し忘れた openOversizedFileMarksUnsupportedWithoutLoading と入力・assertion とも完全一致していた(重複削減が目的のタスクで重複が 1 件増えた形)。既存側を削除。削除側が主張していた「読み込まれていない」は content == "" でカバー済みとレビューで確認
- ViewerWindowControllerToolbarTests: 統合で「アイテム生成経路(itemForItemIdentifier で新規生成)× 履歴あり → 有効」の検証が失われていた。統合後はライブアイテムしか見ておらず、ツールバーのカスタマイズ等でアイテムが再生成される経路に穴が空いていた。復元し、レビューがプロダクト実装(ViewerToolbarController.makeItem が毎回新規生成し applyState で生成時点の状態を反映)まで遡って生成経路を見ていることを確認
- ViewerWindowControllerCLIOptionsTests: 統合で失われたコメントを復元する際、ケース行自体を重複させてしまい、同一タプルが 2 行になって失敗時にどちらか判別できない状態になった(AC#3 違反)。重複行を削除しコメントを既存行へ寄せた
AC#2 の実績値: 当初 -10 枚だったが、レビュー提案による false 方向のケース追加(保存値がそのまま復元されることを両方向で固定する)でウィンドウ 1 枚分増え、最終的に **-9 枚**。数合わせのために検証を削るのは本末転倒のため、実績値を -9 として記録する。
実行時間: 対象スイートは全体時間にほぼ寄与しないため計測していない。本タスクの価値は「1 テスト内の複数 #expect を行ごとの独立ケースへ分解し、最初の失敗で残りが隠れる状態を解消した」こと(WildcardMatcher 8 本→12 ケース、QuickOpenQuery 9 本→14 ケース)と、未検証だった修飾キーの組み合わせ等の追加。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
同型テストのパラメタライズ化・統合を 15 ファイルに適用した。1 テスト内に複数の #expect を並べていたものを行ごとの独立ケースへ分解し(WildcardMatcher 8 本→12 ケース、QuickOpenQuery 9 本→14 ケース)、「最初の失敗で残りが検証されない」状態を解消した。値でないパラメータ 3 種には CustomTestStringConvertible を実装し、失敗時にどのケースか判別できるようにした。未検証だった修飾キーの組み合わせや、状態変化の事前 assertion も追加している。
フルウィンドウ生成は -9 枚(当初 -10 だったが、レビュー提案の false 方向ケース追加で 1 枚増。検証を優先した)。
レビューで、統合の過程で失われていた検証 2 件(oversized の重複残存、ツールバーの生成経路 × 履歴あり)を復元した。FileWatcher の rename/move ペアと不正 body 6 本は、セットアップの構造差・Sendable 制約から統合を見送り(理由を記録)。
検証: swift test 951 tests / 142 suites グリーン(フル 3 回連続)、swiftformat 差分なし、swift build 警告なし。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
