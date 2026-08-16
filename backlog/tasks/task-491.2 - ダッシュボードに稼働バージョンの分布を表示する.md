---
id: TASK-491.2
title: ダッシュボードに稼働バージョンの分布を表示する
status: To Do
assignee: []
created_date: '2026-08-16 02:35'
labels: []
milestone: m-7
dependencies:
  - TASK-491.1
parent_task_id: TASK-491
priority: medium
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
- [ ] #1 稼働中バージョンの分布がダッシュボードに表示される
- [ ] #2 何を 1 と数えているか（延べ確認回数かユニーク利用者かなど）が画面上で分かる
- [ ] #3 stable と develop のチャネルが混ざらずに読める
- [ ] #4 既存のダウンロード対象タグ別の集計と取り違えない見出しになっている
- [ ] #5 遡及分類できない既存行の扱いが注記されている
- [ ] #6 summarize() の発行クエリ数が既存の上限テストを超えない
- [ ] #7 site の vitest と typecheck が通る
<!-- AC:END -->
