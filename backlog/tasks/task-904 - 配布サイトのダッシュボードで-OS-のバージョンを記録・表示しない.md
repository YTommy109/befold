---
id: TASK-904
title: 配布サイトのダッシュボードで OS のバージョンを記録・表示しない
status: Done
assignee: []
created_date: '2026-10-30T10:29:00Z'
updated_date: '2026-10-30T11:46:00Z'
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
- [x] #1 新規に記録するイベントの OS 列が macOS ならバージョンを含まず `macOS` になる（`summarizeOS` のテストで担保）
- [x] #2 既存の行に残る `macOS 10.15` などバージョン付きの値も、ダッシュボードの OS 別内訳とイベント一覧で `macOS` にまとまって表示される（D1 の値を書き換えるか集計時に丸めるかを決め、理由を Notes に残す）
- [x] #3 OS 別内訳で、バージョン違いの行が別の行として並ばない（集計のテストで担保）
- [x] #4 `docs/` の現在仕様や ADR に OS バージョンを記録する前提の記述があれば合わせて更新する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. summarizeOS から macOS のバージョン抽出を外し、macOS は種別だけにする。2. 既存の行は D1 の移行（UPDATE）で macOS に揃える。3. 移行を流した後の OS 別内訳が 1 行にまとまることを集計関数（kindBreakdowns）で検証する。4. site/README の内訳の節に方針を書く。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
既存の行は「集計時に丸める」ではなく「D1 の値を移行で書き換える」を選んだ。os 列を読む箇所は metricBreakdowns（OS 別内訳）と RECENT_COLUMNS（イベント一覧）の 2 つあり、読む側で丸めると読み手が増えるたびに同じ丸めを足す必要がある（足し忘れると版付きの値が再び出る）。記録済みの版は UA の固定値で実態を表さないので、失って困る情報も無い。移行: site/migrations/20261030120000_drop_os_version.sql（UPDATE events SET os = macOS WHERE os LIKE macOS %）。atlas.sum は migrate:hash で打ち直し、migrate:lint は no diagnostics。scripts/check-destructive-migrations.sh の破壊的判定（DROP / RENAME / DELETE / TRUNCATE）には当たらないため、マージ後の site.yml のデプロイで本番 D1 へ自動適用される。

検証: site の vitest 18 ファイル 447 件 pass、oxlint、oxfmt、tsc、markdownlint。test/os-version-migration.test.ts は移行の WHERE を無効（WHERE 0）にすると「macOS 10.15」が別行で残って落ち、戻すと通ることを確認。ダッシュボードのテスト（dashboard-core など）は os に macOS 14.5 等を直接入れて集計の振り分けを見ているもので、記録経路を通らないため変更していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトのダッシュボードで OS のバージョンを記録・表示しないようにした。summarizeOS は macOS を種別だけで返し、既存の行は D1 の移行（UPDATE）で macOS に揃える。ブラウザが UA の macOS バージョンを 10_15_7 に固定するため、記録していた版は実態を表していなかった。検証: site vitest 447 件、移行後の OS 別内訳が 1 行にまとまるテスト（移行を無効にすると落ちることを確認）、atlas migrate lint。マージ後のデプロイで本番 D1 に自動適用される（取り消し不可だが、失う値は UA の固定値のみ）。
<!-- SECTION:FINAL_SUMMARY:END -->
