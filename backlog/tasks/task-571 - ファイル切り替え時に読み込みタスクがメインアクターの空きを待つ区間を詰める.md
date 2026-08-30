---
id: TASK-571
title: ファイル切り替え時に読み込みタスクがメインアクターの空きを待つ区間を詰める
status: To Do
assignee: []
created_date: '2026-08-30 00:33'
updated_date: '2026-08-30 00:33'
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
- [ ] #1 読み込みタスクの開始がメインアクターの空きに依存しなくなっている
- [ ] #2 対処の前後で `loadContent` 予約から読み込み開始までの時間が実測され、記録されている
- [ ] #3 `.md` と `.pdf` の両方で切り替えが遅くなっていないことが実測で確認されている
- [ ] #4 読み込み結果の適用順序（loadGeneration による追い越し判定）と、既存の非同期テストが壊れていない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に `/review-design` を通すこと。共通経路（全種別のファイル読み込み）の実行順序を変える変更にあたる。

方式の制約: `Task.detached` はこのリポジトリでは pre-commit フックが禁止している（コミット時に `OK: Task.detached の使用なし` を検査）。MainActor を継承させない形にするなら、`nonisolated` なヘルパーの中で `Task {}` を作る（nonisolated な文脈で作られた Task はアクターを継承せず、協調プールで即座に走る）方法になる。捕捉する値（fileReader / contentLoader / makeChunkedReader）が Sendable であることの確認が要る。

なお、この変更は**待ちを消すのではなく前倒しする**性質である点に注意。読み込み自体は 0.5ms しかかからないので、開始を早めても `apply` は結局 MainActor の空きを待つ。効果は「読み込みがメインの仕事と重なる」ぶんに留まる可能性があり、実測で確かめてから採否を決めること。
<!-- SECTION:NOTES:END -->
