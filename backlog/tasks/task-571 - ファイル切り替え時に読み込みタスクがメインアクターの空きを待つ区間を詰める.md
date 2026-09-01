---
id: TASK-571
title: ファイル切り替え時に読み込みタスクがメインアクターの空きを待つ区間を詰める
status: Done
assignee: []
created_date: '2026-08-30 00:33'
updated_date: '2026-09-01 07:06'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 828000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ファイルを切り替えたとき、`ViewerStore.loadContent` が作る `Task { await performLoad(...) }` は MainActor を継承するため、切り替えで積まれた他の仕事（サイドバー同期・ツールバー更新・SwiftUI 再評価）が捌けるまで**読み込みが開始すらしない**。復帰側（バックグラウンドから MainActor へ戻る）でも同じ待ちが入る。

実測（TASK-569 / 2026-08-30、151 ページ・128KB の PDF を窓内で `.md` から切り替え、2 回とも再現）:

| 区間 | 時間 |
| --- | --- |
| `loadContent` 予約 → `performLoad` 開始 | 19.5ms / 17.4ms |
| `performLoad` → pipeline 復帰 | 7.7ms / 5.3ms |
| PDF の実処理（読み込み＋ハッシュ＋probe） | 約 0.5ms |

**PDF 固有ではない。** 同条件の `.md` でも `loadContent → performLoad` に 24〜52ms かかっており、切り替え全体（対処後 34.7ms）の中でこの待ちが最大の区間として残っている。セッション復元のように MainActor が混んでいる場面では 76〜266ms まで伸びるのを観測した。

TASK-569 では PDF 固有の表示サイクル待ち（12〜16ms → 0.25ms）だけを対処し、この区間は範囲外として残した。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 読み込みタスクの開始がメインアクターの空きに依存しなくなっている
- [x] #2 対処の前後で `loadContent` 予約から読み込み開始までの時間が実測され、記録されている
- [x] #3 `.md` と `.pdf` の両方で切り替えが遅くなっていないことが実測で確認されている
- [x] #4 読み込み結果の適用順序（loadGeneration による追い越し判定）と、既存の非同期テストが壊れていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結論（2026-09-01）

### 対処前の実測（AC #2 の前半）

一時計装（`T571Trace`）で `loadContent` 予約 → `performLoad` 開始を測った。
サイドバーの矢印でファイルを切り替え、`.md` と `.pdf` を交互に往復。

| 条件 | 実測（ms） |
| --- | --- |
| markdown | 21.37 / 19.93 / 18.05 / 17.60 / 16.46 / 13.68 |
| pdf | 20.05 / 18.85 / 16.70 / 15.91 |
| 起動・セッション復元 | 44.06 / 446.26 |

`performLoad → pipeline 復帰` は 1.2〜4.2ms。**待ちのほうが実処理の 4〜15 倍**で、
起票時の数字（19.5 / 17.4ms）を再現している。対処する価値がある。

### 実装の形

`loadContent` の同期区間（世代を進める・`beginLoading`・`loadTask` への代入）は
そのまま MainActor 上に残し、**Task の生成だけを nonisolated な static ヘルパーへ移す**。
nonisolated な文脈で作られた `Task {}` はアクターを継承せず、協調プールで即座に走る。
ヘルパーの中で `ViewerLoadPipeline.load` を直接 await し、結果を持って MainActor へ
1 回だけ戻って世代照合と `apply` を行う。

`Task.detached` は使わない（pre-commit が禁止）。

### 保たれる不変条件

- **`loadTask` への代入は同期区間のまま**なので、`close()` のキャンセルから見た順序は不変
- **`loadGeneration` の更新も同期区間のまま**なので「予約の順序＝世代の順序」も不変
- 追い越し判定は `generation == loadGeneration` の等値比較のままで、判定材料を変えない

### Sendable（実測）

捕捉する 3 つはすべて Sendable。`FileReading` は `protocol FileReading: Sendable`、
`ContentLoader` は `struct ContentLoader: Sendable`、`makeChunkedReader` は
`@Sendable` クロージャの typealias。

### 範囲外

- `loadMoreLines`（チャンクの続き取得）は `session.readNextChunk()` を直接 await する
  別経路で同じ待ちを持つが、切り替えの体感に効くのは初回読み込みなので今回は触らない
- QuickLook 側の `OneShotRenderer` も `ViewerLoadPipeline.load` を呼ぶが、1 回描画の
  ホストで MainActor の混雑が問題にならないため触らない

### 守らせるもの（項目 9）

「MainActor を継承しない」は書き方の約束なので、`Task {}` を `@MainActor` の文脈へ
書き戻すと無言で元に戻る。**破れたら落ちるテスト**を用意する
（MainActor を塞いだ状態で読み込みが進むことを見る）。

### 型グループ

`ViewerStore` グループは現在 377 行（上限 400）。ヘルパーを足して超えないか測りながら進める。

### 手順

1. `ViewerStore+Loading` の `loadContent` から Task 生成を nonisolated ヘルパーへ移す
2. MainActor を塞いだ状態で読み込みが始まることを見るテストを足す
3. 対処後の実測（`.md` / `.pdf` 両方）を取り、AC #2・#3 を満たす
4. 一時計装を撤去し、撤去後のビルドで動作確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に `/review-design` を通すこと。共通経路（全種別のファイル読み込み）の実行順序を変える変更にあたる。

方式の制約: `Task.detached` はこのリポジトリでは pre-commit フックが禁止している（コミット時に `OK: Task.detached の使用なし` を検査）。MainActor を継承させない形にするなら、`nonisolated` なヘルパーの中で `Task {}` を作る（nonisolated な文脈で作られた Task はアクターを継承せず、協調プールで即座に走る）方法になる。捕捉する値（fileReader / contentLoader / makeChunkedReader）が Sendable であることの確認が要る。

なお、この変更は**待ちを消すのではなく前倒しする**性質である点に注意。読み込み自体は 0.5ms しかかからないので、開始を早めても `apply` は結局 MainActor の空きを待つ。効果は「読み込みがメインの仕事と重なる」ぶんに留まる可能性があり、実測で確かめてから採否を決めること。

## 採否: 採用した（実測に基づく）

Notes が「効果は限定的かもしれないので実測で採否を決めること」としていたので、
同一条件の A/B（`nonisolated` ↔ `@MainActor` を入れ替えて再ビルド）で測った。

### 実測（2026-09-01 / 起動・セッション復元の外れ値 >100ms は除外）

| 区間 | 対処前（@MainActor 継承） | 対処後（nonisolated） |
| --- | --- | --- |
| `loadContent` → **読み込み開始** | 中央 **19.23ms**（0.36〜22.14 / n=13） | 中央 **0.03ms**（0.01〜0.04 / n=18） |
| `loadContent` → apply（**全体**） | 中央 **21.98ms**（2.91〜24.65 / n=13） | 中央 **19.07ms**（2.11〜26.73 / n=13） |

- **開始待ちは実質ゼロになった**（−99.8%）。AC #1 を満たす
- 全体も中央値で **−2.9ms（−13%）**。起票時の予告どおり劇的ではないが、
  「読み込みがメインの仕事と重なる」ぶんは確かに縮んでいる

条件: 3.7MB の `big.md` を含む 4 ファイル（`doc1〜3.md` / `many.pdf` / `big.md`）を
サイドバーの ↓↑ で往復。AC #3 の「遅くなっていない」も同じ計測で確認している
（`.pdf` は対処前 15.91〜20.05ms / 対処後 0.02ms 開始・全体は同水準）。

## 計測で踏んだこと（記録）

**最初の「対処後」の数字は測る対象を間違えていた。** mark を `apply` の中（MainActor
復帰後）に置いたため、`loadContent→performLoad` というラベルで実際には全体を測っており、
「改善なし」に見えていた。TASK-569 で同じ取り違えが記録されていたのに繰り返した。
Task の先頭（`ViewerLoadPipeline.load` の直前）へ mark を移して測り直した。

## 実装

- `ViewerStore.startLoad` を `nonisolated static` で新設し、`loadContent` からは
  そこへ委譲する。`loadTask` への代入と `loadGeneration` の更新は同期区間に残したので、
  `close()` のキャンセルから見た順序と「予約の順序＝世代の順序」は不変（AC #4）
- 世代照合と `apply` は `applyLoaded` に分けて MainActor 上で 1 回だけ行う
- 引数が 6 個になり `function_parameter_count` に触れたため、`LoadInputs`（Sendable）へ束ねた。
  行数合わせではなく「1 回の読み込みの入力」という 1 つの関心なので型にした
- `Task.detached` は使っていない（pre-commit の禁止に抵触しない）

## 守らせるもの

`ViewerStoreLoadStartTests` が、**MainActor を塞いだまま読み込みが始まる**ことを見る。
`await` せずに占有したままポーリングするので、`nonisolated` を外すと落ちる
（実測で確認: `@MainActor` に戻すと失敗、戻すと通る）。

## 検証

- `swift test`: 1861 tests / 304 suites 通過
- swiftlint: `origin/main` との差分ゼロ（`function_parameter_count` の新規 1 件は
  `LoadInputs` への集約で解消）
- 型グループ / doc-symbols / doc-citations / markdownlint: 通過
- 一時計装（`T571Trace.swift` と各 mark）は撤去済み。撤去後のビルドで全テスト通過

## 型グループの超過を解消した

コミット時のフックで `ViewerStore` グループが 419 行（閾値 400）になっていた。
`LoadInputs` は `startLoad` の引数を束ねるために `ViewerStore+Loading.swift` の中へ
書いていたが、**独立した型なので専用ファイル（`LoadInputs.swift`）へ切り出した**。
閾値を緩める（`type-group-exceptions.txt` への追記）ことはしていない。

### 切り出しの最終形

`LoadInputs` に続いて `startLoad` も `ViewerLoadStarter.start` として専用ファイルへ出した。
`ViewerStore` の状態に触らない `static` な自由関数だったので、責務で分けるのが素直
（結果として `ViewerStore` グループも 406 → 閾値内に戻った）。閾値の緩和はしていない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ファイル切り替え時に読み込みタスクがメインアクターの空きを待つ区間を消した。`loadContent` の `Task {}` は @MainActor を継承するため、切り替えで積まれた他の仕事が捌けるまで読み込みが開始すらしていなかった。`nonisolated static func startLoad` を新設して Task の生成をそこへ移し、アクターを継承しない形にした（Task.detached は使わない）。同一条件の A/B 実測で、開始待ちは中央 19.23ms → 0.03ms、切り替え全体も 21.98ms → 19.07ms（−13%）。loadTask への代入と loadGeneration の更新は同期区間に残したので追い越し判定の不変条件は変えていない。MainActor を塞いだまま読み込みが始まることを見る ViewerStoreLoadStartTests で固定した（nonisolated を外すと落ちることを確認済み）。swift test 1861 件通過、swiftlint 差分ゼロ、一時計装は撤去済み。
<!-- SECTION:FINAL_SUMMARY:END -->
