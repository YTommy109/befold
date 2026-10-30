---
id: TASK-904
title: 配布サイトのダッシュボードで OS のバージョンを記録・表示しない
status: To Do
assignee: []
created_date: '2026-10-30T10:29:00Z'
labels: []
dependencies: []
priority: low
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ダッシュボード（/dashboard）の OS 別内訳とイベント一覧に「macOS 10.15」が並ぶが、実際の OS を表していない。OS 列は `site/src/events.ts` の `insertEvent` が User-Agent を `site/src/lib/visitor.ts` の `summarizeOS` に通した値で、ブラウザ（Safari / Chrome / Firefox）は macOS 11 以降でも UA を `Mac OS X 10_15_7` に固定して送るため、ブラウザ経由の行は常に 10.15 になる。アプリ本体の Sparkle の UA（`befold/x Sparkle/y`）は OS を含まず null になる。つまり現在のデータからバージョン分布は分からないのに、数字が実態のように表示されている。2026-10-30 に最低対応 OS（TASK-903）を検討した際、この数字を根拠に誤読しかけた。

本当のバージョンを得るには Sparkle の system profile（利用者の同意が要る）を使う必要があるが、バージョン情報のために同意を求めるほどの価値はないと判断し（2026-10-30 ユーザー判断）、バージョンを記録・表示しない方向にする。OS 種別（macOS / Windows / iOS など）の粗い内訳は残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 新規に記録するイベントの OS 列が macOS ならバージョンを含まず `macOS` になる（`summarizeOS` のテストで担保）
- [ ] #2 既存の行に残る `macOS 10.15` などバージョン付きの値も、ダッシュボードの OS 別内訳とイベント一覧で `macOS` にまとまって表示される（D1 の値を書き換えるか集計時に丸めるかを決め、理由を Notes に残す）
- [ ] #3 OS 別内訳で、バージョン違いの行が別の行として並ばない（集計のテストで担保）
- [ ] #4 `docs/` の現在仕様や ADR に OS バージョンを記録する前提の記述があれば合わせて更新する
<!-- AC:END -->
