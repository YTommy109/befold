---
id: TASK-491.2
title: ダッシュボードに稼働バージョンの分布を表示する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-16 02:35'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-7
dependencies:
  - TASK-491.1
parent_task_id: TASK-491
priority: medium
type: task
ordinal: 729000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-491 の表示側。記録は TASK-491.1 で行う。

`update_check` に記録された稼働中バージョンを、ダッシュボードで分布として読めるようにする。見たいのは「古いバージョンを使い続けている利用者がどれだけいるか」であって延べ確認回数ではないため、**何を数えるかを決める必要がある**。

## 決めること

- **母数の取り方。** `update_check` はアプリが定期的に飛ばすため、延べ件数はバージョンではなく起動回数に比例する。`visitor_token`（`sha256(ip \0 ua \0 JST 日付)`、`site/src/lib/visitor.ts:26-30`）は日ごとに変わるので通算のユニーク利用者数にはならない。「直近 N 日でそのバージョンから確認が来た visitor_token のユニーク数」など、何を 1 とするかを決めて指標名に反映する。
- **チャネルの扱い。** 実測（2026-08-16）では `update_check` 132 件のうち develop チャネルが 81 件と多数を占め、これは開発機からの確認。stable と develop を混ぜると stable 利用者の分布が読めない。

## 注意

- 既存の「バージョン別」セクション（`site/src/analytics.ts` の `byVersion`）はダウンロード対象のタグ別であり、稼働バージョンとは別物。同じ画面に並べるなら、どちらが何を表すかが読んで分かる見出しにする。
- 遡及分類できない既存行（`update_check` 132 件すべて）の注記を、既存の「遡及分類不可」と同じ形で置く（`site/src/views/dashboard.tsx`）。
- ボット除外は既存の `HUMAN_ONLY` を使う。ボット除外条件が 1 箇所に集約されていることは規約テスト `site/test/analytics.test.ts:299` が担保している。
- `summarize()` のクエリ数上限テストに注意（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。指標を足す際にクエリを線形に増やさない。
- 実装着手前に `/review-design` を 1 回回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 稼働中バージョンの分布がダッシュボードに表示される
- [x] #2 何を 1 と数えているか（延べ確認回数かユニーク利用者かなど）が画面上で分かる
- [x] #3 stable と develop のチャネルが混ざらずに読める
- [x] #4 既存のダウンロード対象タグ別の集計と取り違えない見出しになっている
- [x] #5 遡及分類できない既存行の扱いが注記されている
- [x] #6 summarize() の発行クエリ数が既存の上限テストを超えない
- [x] #7 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. /review-design を実施（結果は Implementation Notes）。
2. 何を 1 と数えるかを決める: 延べ確認回数ではなく COUNT(DISTINCT visitor_token)（＝アクセス元×日の異なり数）。期間は全期間ではなく直近 DAILY_WINDOW_DAYS（14 日）。チャネル別に分ける。
3. クエリ本数を増やさないため、軸ごとに 1 本ずつ引いていた metricBreakdown（os / as_org）を UNION ALL で 1 本に畳んで枠を空け、そこへ runningVersionBreakdown を入れる（13 本のまま）。
4. Summary に runningVersions（Record<Channel|'unrecorded', Count[]>）を足す。列挙は CHANNELS から生成し、チャネルを増やしたら型で落ちるようにする。
5. dashboard.tsx に専用セクションを追加。単位・期間・チャネル分離・ダウンロード対象タグとの違い・遡及不可の注記を置く。0 件のチャネルも表を残す。
6. テスト: analytics.test.ts に単位/チャネル分離/窓/NULL/ボット除外/0 件/上位 N の 7 件、dashboard.test.ts に表示 5 件。query-count.test.ts の内訳コメントを更新。
7. npm test / typecheck を通す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこと: 何を 1 と数えるか

**延べ確認回数ではなく `COUNT(DISTINCT visitor_token)`**（アクセス元×日の異なり数、`cumulativeTotals` の `visitor_days` と同じ単位）。`update_check` はアプリが定期的に飛ばすため、件数はバージョンではなく起動回数に比例する。通算のユニーク利用者数ではない（visitor_token は日付を材料に混ぜているので日をまたぐ同一人物は追えない）。この単位は画面の注記に書き、テスト（`延べ確認回数ではなくアクセス元の異なり数を数える`）で固定した。

**期間は全期間ではなく直近 14 日（`DAILY_WINDOW_DAYS`）。** 見たいのは今も使われ続けている版であって、過去に一度でも動いた版の履歴ではない。全期間で数えると、すでに更新を終えた版がいつまでも分布に残る。

**チャネル別に分けた。** 実測で `update_check` の大半が develop（開発機）だったため、混ぜると stable 利用者の分布が読めない。列挙は `CHANNELS` から生成しているので、チャネルを増やすと `CHANNEL_LABELS` の型で落ちる（系列だけ無名で増えることがない）。channel が NULL の行は `unrecorded` の表に入れ、0 件でも表そのものは残す（「まだ 0 だった」と「そもそも数えていない」を画面上で区別できなくしないため）。

## クエリ本数を増やさずに 1 本ぶん空けた方法

上限は `test/query-count.test.ts` の `MAX_QUERIES = 13` で、変更前はちょうど 13 本で余裕が無かった。

- 相乗り先として検討した `eventBreakdowns` は不可。あの 1 本は「値が列挙で閉じた列の組で集約すれば返る行は高々数十行」という前提の上に立っており、値が増え続ける `app_version` を GROUP BY へ足すと行数が発散し、TOP_N 切りも SQL 側で効かない。
- `UNIQUE_SOURCE_COLUMNS` の列展開方式（`COUNT(DISTINCT CASE WHEN ... END)` を系列ぶん並べる）も不可。系列が定数個であることが前提。
- 採ったのは**軸ごとに 1 本ずつ引いていた `metricBreakdown`（os / as_org）を `UNION ALL` で 1 本に畳む**方法（2 本 → 1 本）。`trafficSplit` の区分・`eventBreakdowns` の列と同じ「増やす方向を行にして窓で切る」既存パターンの延長で、軸を足しても本数が増えない形になった。空いた 1 本ぶんへ `runningVersionBreakdown` を入れて合計 13 本を維持。

稼働バージョンを独立した 1 本にしたのは、数える単位（COUNT(*) ではなく COUNT(DISTINCT visitor_token)）も期間（全期間ではなく直近 N 日）も他の内訳と違うため。1 本に混ぜると 1 つのクエリが 2 つの意味を持つ。

## /review-design の結果

- **項目 1（判定の真実の源）**: 「古いバージョン」を文字列比較で判定しない。SQL でのバージョン順序比較は semver にならないため、述語を作らず分布をそのまま出す形にした。チャネルの分岐は `channel IS NULL` を明示（`COALESCE(channel, 'unrecorded')`）。
- **項目 3（消費経路の全列挙）**: 列挙元を `CHANNELS` に一本化。`HUMAN_ONLY` は `analytics.test.ts` の構造ガードテストが「`FROM events` を含むクエリは必ず含む」ことを検査しており、新しいクエリもこれに従っている。TOP_N での切り出しがあることを注記に書き、`TOP_N` を export して画面の数字が実装からずれないようにした。
- **項目 4（新しい状態に対応する表示）**: 0 件のチャネルも表を残す。NULL の 3 通りの意味（列導入前 / Sparkle 以外のクライアント / パース不能）を注記に書き分けた。
- **項目 9（決めた粒度を守らせるもの）**: 単位（異なり数）と期間（直近 N 日）は doc コメントだけでなくテストで固定した。実装を戻すと落ちることを確認済み。
- 項目 2・5・6・7・8・10 は非該当（既存の不変条件に触れない／集計は 1 回きり／高頻度経路でない／非同期の表示状態が無い／Swift 専用）。

## 検証

- `npm test` → 12 files / 277 tests すべて通過（+13 件）
- `npm run typecheck` → エラーなし
- `test/query-count.test.ts` → 13 本のまま通過（内訳コメントも更新）
- **修正を戻して落ちることを確認**（いずれも復元済み）:
  - `WHERE ... timestamp >= ?` の窓を外す → `窓の外の確認は数えない（今も使われている版だけを見る）` が fail
  - `COUNT(DISTINCT visitor_token)` を `COUNT(*)` に戻す → `延べ確認回数ではなくアクセス元の異なり数を数える` が fail
- 描画結果を実際に出して文言を確認（「稼働中のアプリバージョン（直近 14 日）」「上位 10 件まで」「アプリ（stable）: 稼働バージョン別」等が意図どおり出ることと、0 件チャネルが「データなし」で残ることを確認）

## 補足

既存の `byVersion`（「バージョン別ダウンロード」）は `kind='download' AND COALESCE(source,'lp')='lp'` のままで、SQL も値も変えていない（TASK-491 の AC #4）。取り違えを防ぐため、新セクションの注記で「あちらは更新先のタグ、こちらは更新元の稼働版」と明示している。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ダッシュボードに「稼働中のアプリバージョン（直近 14 日）」セクションを追加し、チャネル別（stable / develop / 未記録）の表で分布を出すようにした。数えるのは延べ確認回数ではなくアクセス元の異なり数（COUNT(DISTINCT visitor_token)）で、単位・期間・チャネルを分ける理由・ダウンロード対象タグ別集計との違い・遡及分類できない既存行を画面上の注記で説明している。クエリ本数は 13 のまま——軸ごとに 1 本ずつ引いていた指標別内訳（os / as_org）を UNION ALL で 1 本に畳んで枠を空け、そこへ稼働バージョンのクエリを入れた。検証は `npm test`（277 tests 通過、うち新規 13 件）・`npm run typecheck`・query-count テスト（13 本）と、窓の絞り込みと DISTINCT をそれぞれ戻すと該当テストが落ちることの確認、および描画結果の実物確認。
<!-- SECTION:FINAL_SUMMARY:END -->
