---
id: TASK-354
title: TSan の CI で ViewerWindowManagerDiffTests の 3 件が待機タイムアウトする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-07 14:14'
updated_date: '2026-08-07 15:01'
labels:
  - test
  - flaky
  - ci
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/actions/runs/31173231496'
priority: high
type: bug
ordinal: 613000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状

main の CI（run 31173231496, v1.12.2 の bump コミット, 2026-08-07 11:18）の thread-sanitizer ジョブで、`ViewerWindowManagerDiffTests` の 3 件が同時に失敗した。

```text
✘ "片方のウィンドウのトグルが全ウィンドウの差分に届く"       :58   133.668s
✘ "ウィンドウを閉じても他窓の差分取得に影響しない"           :187  133.808s
✘ "同じファイルを 2 窓で開いても git diff は 1 回に合流する"  :138  146.326s
```

3 件とも失敗行は `waitUntilOnMainActor(timeout: testTimeout(fallback: 60))` の呼び出し（`ViewerWindowManagerDiffTests.swift:58` / `:138` / `:187`）で、**回数の不一致ではなく待機のタイムアウト**。

## TASK-346 との違い

TASK-346 の失敗は `Expectation failed: (reader.callCount → 3) == (before + 1 → 2)` という回数の算術で、合流が壁時計の重なりに依存していたことが原因だった。これは構造修正で解消し、その後の main CI 3 回（run 31145812149 / 31152119577 / 31158346419）で thread-sanitizer は成功している。本件は失敗の形が違うため別タスクとする。

## 手がかり（未確認の仮説を含む）

- 全体実行が 150.9 秒なのに個々の待機が 133〜146 秒 — つまり**このスイートの差分がテスト実行のほぼ全期間にわたって着地していない**。CI は `BEFOLD_TEST_TIMEOUT_SECONDS=120` を設定済み（ci.yml:93）で、その予算を使い切っている。
- TASK-327 の実測「full suite 実行中はメインアクターが 5.1〜8.3 秒到達不能、失敗回は 15 秒予算内に一度も到達しなかった」の延長線にある可能性が高い。ただし 120 秒を使い切るのは飢餓の程度として大きく、**差分が本当に着地していない（取得が起きていない／結果が書き戻されていない）可能性を先に潰すこと**。
- 未確認: 直前のマージ（PR #433 の `fix(gate): 差分の比較基準をサイドバーのバッジと揃える` = 723c385、PR #434 = 3f4449d）との関係。#433 / #434 の CI では thread-sanitizer は成功しているため、単発の遅さか、bump コミットで初めて条件が揃ったかは切り分けが必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 3 件が待機タイムアウトする原因を、飢餓か着地漏れかまで切り分けて実測で特定している
- [x] #2 thread-sanitizer 付きの実行で 3 件が 10 回連続して失敗しない
- [x] #3 待機の判定が壁時計の予算切れに左右されにくい形になっている（予算を伸ばすだけの対処にしない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldTestSupport/Waiting.swift に `waitForMainActorDelivery` の `@MainActor` 版
   (`waitForDeliveryOnMainActor`)を足す。壁時計予算を持たず、上限はスイートの
   `.timeLimit` に委ねる点は既存版と同じ。`@Observable` ストアを条件から参照するため
   `@Sendable` にできないのが分ける理由(`waitUntil` / `waitUntilOnMainActor` と同じ形)。
2. ViewerWindowManagerDiffTests を `@Suite(testTimeLimit())` にし、4 箇所の
   `waitUntilOnMainActor(timeout: testTimeout(fallback: 60))` を 1 の待機へ置き換える。
   予算を伸ばすのではなく、待機から壁時計予算を外して上限をスイートのハング検出へ移す。
3. WaitingTests に新ヘルパーのキャンセル離脱テストを足す(既存の
   `waitForMainActorDeliveryReturnsOnCancellation` と同型)。予算を持たない待機は
   キャンセルを見ないとホットスピンするため、ここが担保。
4. TSan 付き full suite を 10 回連続で回し、3 件が落ちないことを確認する(AC#2)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測による切り分け(飢餓か着地漏れか)

結論: **飢餓**。着地漏れではない。あわせて、起票時の前提「個々の待機が 133〜146 秒かかっている」は**誤り**だった。

### 実測

環境: ローカル(10 コア)、`BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --sanitize=thread`。

1. スイート単独実行(`--filter ViewerWindowManagerDiffTests`): 6 件すべて **1.296〜1.451 秒**で成功。全体 1.452 秒。
2. full suite 実行: 同じ 6 件が **38.5〜42.0 秒**。全体は 42.817 秒。
3. ただし、**await を 1 つも含まない同スイートの 3 件**も同じ値だった。
   - 「差分表示設定を共有する」38.542s / 「差分の取得元を共有する」38.536s / 「差分表示を OFF にすると本文が捨てられる」38.544s
4. full suite 1367 件のうち **625 件**が 30 秒超を報告(全体 42.8 秒の実行で)。

つまり swift-testing が報告する所要時間は「そのテスト自身の作業時間」ではなく
**テスト開始から終了までの壁時計**であり、全テストが一斉に開始されて `@MainActor` で
直列化されるため、ほぼ全件が実行全体の長さを報告する。CI の 133.668s / 133.808s /
146.326s も同じ性質の値で、「待機が 133 秒かかった」ことを意味しない。

### 除外した仮説

- **detached utility の優先度飢餓**: `GitDiffLoader.swift:97` の
  `Task.detached(priority: .utility)` を `.userInitiated` へ上げて full suite を再実行
  → 36.255 / 36.280 / 38.041 秒(全体 39.118 秒)で**変化なし**。原因ではない。実験後に revert 済み。
- **着地漏れ(取得が起きない／書き戻されない)**: 同じコードでローカルは全件成功し、
  単独実行では 1.4 秒で着地する。着地しない経路ではない。

### 真因

`waitUntilOnMainActor` の壁時計期限は**テスト開始時点から**進む。一方テスト本体の
実行はメインアクター上で実行全体の後ろへ積まれる。したがって予算 120 秒は
「操作にかかった時間」ではなく「順番待ちの時間」を測っており、実行全体が 150.9 秒
かかった CI では、順番が後ろに来たテストが操作の成否と無関係に予算切れになる。
予算を伸ばす対処は実行全体の長さとの追いかけっこにしかならない。

これは Waiting.swift:162-179 に記録済みの TASK-327 / TASK-335 と同型で、そこでの
結論は「`@MainActor` 配送を待つ箇所は壁時計予算を持たず、上限はスイートの
`.timeLimit` に委ねる」。`ViewerWindowManagerDiffTests` は `@Suite` 素のままで
`testTimeLimit()` を持たず、この方針が適用されていない唯一の取り残しだった
(同方針を適用済みの姉妹スイート: ViewerWindowControllerToolbarTests /
ViewerWindowControllerGitStatusTests ほか計 16 スイート)。

## 修正と検証

### 修正

1. `BefoldTestSupport/Waiting.swift`: `waitForMainActorDelivery` の `@MainActor` 版
   `waitForDeliveryOnMainActor` を追加。壁時計予算を持たず、上限はスイートの `.timeLimit`。
2. `ViewerWindowManagerDiffTests`: `@Suite(testTimeLimit())` を付与し、4 箇所の
   `waitUntilOnMainActor(timeout: testTimeout(fallback: 60))` を 1 の待機へ置換。
3. `WaitingTests`: 予算なし待機のキャンセル離脱テストを追加。

### 途中で自分が同型の欠陥を作り込んだ(記録)

3 の新規テストを `#expect(await waitUntil(timeout: .seconds(5)) { finished.get() })` で
書いたところ、TSan 付き full suite 10 回中 1 回落ちた(WaitingTests.swift:61)。原因は
本タスクで直している欠陥そのもの — 予算 5 秒が「戻ってくるまでの時間」ではなく
「メインアクターの順番待ちの時間」を測っていた。タスクを直接 `await` する形へ変更。
同型だった既存 2 件(`waitForMainActorDeliveryReturnsOnCancellation` /
`waitUntilWithRetryReturnsOnCancellation`)も同時に `await task.value` + `#expect` へ揃えた。

### 検証(実測)

- `BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --sanitize=thread` を **10 回連続**で実行し、
  全 10 回とも 1192 tests / 176 suites が成功(36.5〜41.0 秒)。失敗 0 件。
- 修正前の同条件 10 回では 1 回失敗していた(上記の作り込み分)。
- swiftformat: 変更 3 ファイルとも整形差分なし。
- swiftlint: 変更 3 ファイルに指摘なし。

### 残る前提(未解消)

`.timeLimit` 自身も壁時計であり、テスト開始からの経過で測られる。現状 `testTimeLimit()` は
予算の 2 倍(TSan CI では 240 秒)を上限にしており、実行全体 150.9 秒に対して余裕がある。
実行全体が 240 秒を超えるほど伸びた場合は、この上限の導き方(実行時間との比ではなく定数倍)
を見直す必要がある。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
待機タイムアウトの原因は飢餓で、着地漏れではなかった。あわせて起票時の前提「個々の待機が 133〜146 秒かかっている」が誤りであることを実測で示した — swift-testing が報告するテスト所要時間はテスト開始からの壁時計であり、全テストが一斉開始・メインアクターで直列化される full suite ではほぼ全件が実行全体の長さを報告する(TSan 全体実行 42.8 秒で 1367 件中 625 件が 30 秒超を報告。await を含まない同スイートのテストも 38.5 秒)。スイート単独なら 6 件すべて 1.3〜1.5 秒で終わる。detached タスクの優先度(.utility → .userInitiated)は無関係であることも実測で除外した。

真因は `waitUntilOnMainActor` の壁時計予算がテスト開始時点から進むこと。予算は操作にかかった時間ではなく順番待ちの時間を測っており、実行全体が 150.9 秒かかった CI では順番が後ろのテストが操作の成否と無関係に予算切れになる。予算を伸ばす対処は実行全体の長さとの追いかけっこにしかならない。

対処は TASK-327 / TASK-335 で確立済みの方針(Waiting.swift に記録、16 スイートが適用済み)を、唯一の取り残しだったこのスイートへ適用したもの: 待機から壁時計予算を外し、上限をスイートの `.timeLimit` へ移した。`waitForMainActorDelivery` の `@MainActor` 版 `waitForDeliveryOnMainActor` を追加し、`@Suite(testTimeLimit())` を付与、4 箇所の待機を置換。予算なし待機がホットスピンしない担保として WaitingTests にキャンセル離脱テストを追加した。

検証: `BEFOLD_TEST_TIMEOUT_SECONDS=120 swift test --sanitize=thread` を 10 回連続実行し、全 10 回とも 1192 tests / 176 suites 成功(失敗 0 件)。swiftformat / swiftlint とも変更 3 ファイルに差分・指摘なし。
<!-- SECTION:FINAL_SUMMARY:END -->
