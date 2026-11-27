---
id: TASK-933
title: main の thread-sanitizer ジョブが、窓を作るテストの同時実行で遅くなり、テストの制限時間を超えて落ちる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-26T12:40:33Z'
updated_date: '2026-11-27T01:37:00Z'
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
- [x] #2 窓を作るテストの同時数(または同時に生きる窓の数)が所要時間を押し上げていることを、抑えた場合と抑えない場合の比較で確かめ、結果を Notes に残す
- [x] #3 対策が、今後窓を作るテストを足したときにも効く形になっている(個別のテストを --skip するのではない)
- [x] #4 制限時間(BEFOLD_TEST_TIME_LIMIT_MINUTES)やジョブの timeout を延ばすだけで済ませていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Swift Testing の並列幅上限 SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH が効くことをプローブで確かめる
2. TSan 本体実行を既定 / 上限 4 で交互に 3 回ずつ流し、所要時間を比べる(AC#2)
3. 効果があれば thread-sanitizer ジョブの env に上限を入れる(新しい窓テストにも自動で効く)
4. 上限が黙って外れたら落ちるガードテストを置く(変数名が toolchain 更新で変わる場合に備える)
5. main マージ後の thread-sanitizer 2 回連続成功で AC#1 を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 対策と比較(実測 / 2026-11-26、手元 10 コア)
- Swift Testing の並列幅上限 SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH が効くことをプローブで確認: 40 ケースの同時数は 既定 40 / =1 で 1 / =4 で 4。既定はコア数でなく無制限
- swift test --sanitize=thread --skip befoldCLITests --skip PDF を既定と =4 で交互に 3 回ずつ(--skip-build、逐次)。テスト実行時間: 既定 348 / 381 / 385 秒、=4 で 112.6 / 114.5 / 107.6 秒(約 3.4 倍速)
- 既定の 1 回目は 2 件失敗: FileWatcherSlowOpenTests.initReturnsWhileOpenIsBlocked と ViewerStoreIntegrationTests.deletingWatchedFileFiresOnFileGone(345 秒で失敗)。この回は swiftformat の実行と CPU が重なっていた。=4 の 3 回は全件成功
- .timeLimit が個々のテストの開始から測るので、打ち切りが消えただけかもしれない、という見方は当たらない。全体の実行時間そのものが縮んでいる
- 窓の枚数はこの比較では数えていない。同時に走るテストが 4 件以下になるので、窓を作るテストが同時に持つ窓も 4 件ぶんまでに収まる
- 対策: ci.yml の thread-sanitizer ジョブの env に SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH: 4 を置く。テストに手を入れないので、後から足す窓テストにも同じく効く
- 担保: ParallelizationWidthCapTests。変数が設定されたときだけ動き、同時に走るケースが上限を超えたら落ちる。テストが読む変数名を別の名前に差し替えて、フレームワークに上限が効いていない状態を作ると、16 件すべて失敗することを確認した(toolchain の更新で変数が無効になる場合の模擬)
- AC#1 は main への push で走るジョブでしか確かめられない(workflow_dispatch なし)。マージ後に 2 回続けて緑になったらチェックする

## 追記: CI と同じ 3 本の実測と、上限の範囲(2026-11-26)
- 訂正: 上の「窓を作るテストが同時に持つ窓も 4 件ぶんまでに収まる」は推論で、測っていない(未確認)。この比較は全テストの同時数を抑えたもので、窓を作るテストだけを抑えたのではない。確かめるには、5 秒ごとに NSApp.windows を数える一時プローブを上限ありで 1 回流し、ピークを比べる
- コミット済みのツリーで、上限 4 を付けて TSan の 3 本を流した: 本体 122 秒(テスト 109.8 秒、全件成功。ParallelizationWidthCapTests の 16 ケースも成功)/ PDF は 59 分で停止 / CLI 14 秒
- PDF の停止: sample では 147 スレッドが PDFKit の formFillingQueue と VNRecognizeDocumentsRequest のセマフォ待ちで、PDFSurfaceLayoutTests.survivesDocumentAccessOffTheMainThread の DispatchQueue.global().async が実行されないまま止まっていた。TASK-907 と同じ libdispatch ワーカーの枯渇
- 上限なしの PDF 16 秒 / CLI 12 秒(成功)。その後、上限ありの PDF をもう 3 回流すと 3 回とも成功(14〜16 秒)。上限ありで止まったのは 4 回中 1 回で、上限との因果は未確認
- PDF と CLI はもともと遅くないので、上限は本体の実行(1 本目のコマンド)にだけ付ける。ジョブ全体の env には置かない

PR #798 を作成した。残りは AC#1 のみ。着手条件: #798 をマージした後、main への push(または nightly の schedule)で走る thread-sanitizer ジョブが 2 回続けて緑になること。確かめたら AC#1 をチェックして Done にする

## 追記: 同時に生きる窓の枚数(実測 / 2026-11-27)
上の「未確認」を解消した。1 秒ごとに NSApp.windows を数える一時プローブ(コミットしていない)を入れ、TSan 本体実行を上限 4 と既定で 1 回ずつ流した。
- 上限 4: 窓のピークは全体 28 / 表示中 7、平均 19.5 枚。1 秒タイマーは 108 秒で 84 回発火した。テストは全件成功(108.0 秒)
- 既定: 窓のピークは全体 151 / 表示中 74、平均 57.4 枚。1 秒タイマーは 402 秒で 7 回しか発火していない(メインスレッドがほぼ空かない)。1 件失敗: 「drawsBackground の KVC が実 WebView の地の透過/不透過へ効く」が 393.5 秒で失敗(負荷下で実 WebView が詰まる TASK-675 の系統)
- 同時に走るテストを抑えると、生きている窓が約 1/5 になり、所要時間も約 1/3.7 になる。窓の数とメインスレッドの混み具合が所要時間を押し上げている、という見立てに合う
<!-- SECTION:NOTES:END -->
