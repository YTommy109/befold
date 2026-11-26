---
id: TASK-933
title: main の thread-sanitizer ジョブが、窓を作るテストの同時実行で遅くなり、テストの制限時間を超えて落ちる
status: To Do
assignee: []
created_date: '2026-11-26T12:40:33Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/actions/runs/45782956193
  - https://github.com/YTommy109/befold/actions/runs/45810455354
priority: high
type: bug
ordinal: 874000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #796(ADR 0013)のマージ以降、main への push で走る CI の thread-sanitizer ジョブが 2 回続けて落ちた(c9f281f7 / 6405f3a6)。ThreadSanitizer がデータ競合を報告したのではない。テスト全体が遅くなり、メインアクターで順番を待つテストが 1 件あたりの制限時間(BEFOLD_TEST_TIME_LIMIT_MINUTES=20)を超えて落ちた(36 件 / 43 件)。このジョブは PR では走らない(push と schedule のみ)ので、PR の CI は緑のままだった。

## 調査結果(実測 / 2026-11-26)

### CI の所要時間(--skip befoldCLITests --skip PDF の本体)
- 古いイメージ(macos-26-arm64 20261102.0473)・#796 前: 469 秒(11/16)
- 新しいイメージ(20261117.0516)・#796 前(88e11ae9、schedule 実行): 718 秒
- 新しいイメージ・#796 後: 1258 秒 / 1277 秒(どちらも失敗)
- ThreadSanitizer なしの build-and-test (default) は 154 秒 → 161 秒でほぼ変わらない
イメージの更新で約 1.5 倍遅くなり、そこへ #796 の分が上乗せされて制限を超えた。Xcode は両方とも 26.6。

### 手元(swift test --sanitize=thread --skip befoldCLITests --skip PDF)
- #796 前(88e11ae9): 253 秒 / HEAD: 355 秒(user CPU 261 → 354 秒)
- HEAD から #796 で足した 4 スイート(ViewerWindowFileOpenPresentationTests / ViewerWindowHistoryPresentationTests / ViewerWindowReopenPresentationTests / DocumentOpenerFolderTests、29 件)を --skip すると 237 秒に戻る
- ところが、その 4 スイートだけを --no-parallel で流すと合計 16 秒。単体の重さでは増分を説明できない

### 同時に生きている窓の数(一時プローブ。5 秒ごとに NSApp.windows を数えた)
- 4 スイートあり: 最大 149 枚(表示中 72)、平均 81.8。推移 149 → 107 → 85 → 47 → 21
- 4 スイートなし: 最大 107 枚(表示中 68)、平均 61.7
- 5 秒ごとのタイマーが 349 秒で 5 回しか発火しなかった。メインスレッドがほぼ空いていない
- 窓の閉じ忘れは無い: 各テストの後片付け直後に数えると、表示中・全体とも 0 だった

### 重い処理(sample で採取)
メインスレッドは窓をタブとして加える処理(ViewerTabGrouping.attachAsTab → NSWindow _addTabbedWindow → _syncInactiveTabWindowSizesToWindow → CA::Transaction::flush → NSDisplayCycleFlush)で、ツールバーを含むビュー階層のレイアウトを回していた。描き直しはレイアウト待ちの窓すべてを対象にするので、同時に生きている窓が多いほど 1 回あたりが重くなる。

## 見立て
Swift Testing はテストを並行に始めるため、窓を作るテストの多くが実行の初めに一斉に窓を開き、await の間も開いたまま保つ。AppKit の描き直しやタブの付け替えは、生きている窓の数に比例して重くなる。結果として全体のコストが窓の数に対して線形より速く増える。#796 の 4 スイートは、サイドバー・ツールバー・WebView を持つ実物の窓を 29 件ぶん足したため、新しいイメージの ThreadSanitizer 下で制限を超えた。

未確認: 窓の同時数を抑えたときに所要時間が戻るか(因果の確認)。手元の所要時間は 1 回ごとのばらつきが大きく(4 スイートなしで 237 秒と 293 秒)、1 回の比較で効果を確定させないこと。

## 関連
- TASK-675(全体実行 + CPU 負荷下で、実 WKWebView のロード完了が来ない)は、同じく負荷下で窓・WebView が詰まる系統
- 手元の ThreadSanitizer 全件実行で、実ファイル監視を使う統合テストが回ごとに別々に落ちた(ViewerStoreIntegrationTests.deletingWatchedFileFiresOnFileGone / reflectsFileEditAfterDebounce、FileWatcherSlowOpenTests.initReturnsWhileOpenIsBlocked)。負荷による flaky と見ているが、この件との関係は未確認
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 main の push で走る thread-sanitizer ジョブが、制限時間超過なしで通る(2 回以上続けて)
- [ ] #2 窓を作るテストの同時数(または同時に生きる窓の数)が所要時間を押し上げていることを、抑えた場合と抑えない場合の比較で確かめ、結果を Notes に残す
- [ ] #3 対策が、今後窓を作るテストを足したときにも効く形になっている(個別のテストを --skip するのではない)
- [ ] #4 制限時間(BEFOLD_TEST_TIME_LIMIT_MINUTES)やジョブの timeout を延ばすだけで済ませていない
<!-- AC:END -->
