---
id: TASK-387
title: 解析ダッシュボードのチャートを複数系列のグループ化バーチャートに統合し、表を削除して横幅と可読性を上げる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-09 08:38'
updated_date: '2026-08-09 09:16'
labels: []
dependencies: []
references:
  - site/src/views/dashboard.tsx
  - site/src/analytics.ts
  - site/test/dashboard.test.ts
priority: medium
type: feature
ordinal: 644000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
解析ダッシュボードの「日毎の推移（直近 14 日）」「時間帯分布（直近 14 日・JST）」は、現在チャートと表の両方を出しており、さらに系列（ページアクセス / ダウンロード / アップデート確認 / 自動アップデート適用 / ユニーク訪問者）ごとに別チャートを並べる構成になっている。この 2 節を、系列を色分けしたグループ化バーチャート 1 枚 + 凡例に置き換え、表は削除する。あわせてチャートの横幅を広げ、日付ラベルのフォントサイズを読める大きさにする。

前提と裏付け（コード参照。すべて site/src/views/dashboard.tsx）:
- 節の構成: 「日毎の推移」:247（チャート＋表）、「時間帯分布」:275（チャート＋表）、「内訳（全期間の累計）」:293（表のみ）、「最新イベント（直近 20 件）」:307（表のみ）、「累計」:216 と「本日」:233 はカードのみ
- チャートはライブラリ不使用のサーバサイド生成インライン SVG。描画関数 BarChart は :85-141。クライアント JS で描かない理由は :77-84 のコメントに明記（SSE が #summary を innerHTML 置換するため）
- 現状は完全な単系列。BarChart は rows: Count[]（{label, count}、src/analytics.ts:12）を 1 本ずつ rect にするだけで、積み上げ・グループ化のコードは無い（:113-126）
- 凡例の実装は存在しない。系列名は SeriesTable の h3（:158）、SVG の aria-label（:101）、バーの title ツールチップ（:123）のみ
- 座標系は viewBox 内部単位 CHART = { width: 640, height: 140, gap: 2, labelGap: 14 }（:75）。実表示幅は .chart { width: 100%; height: auto }（:48）で親に追従
- 横幅に効くのは body { max-width: 60rem }（:30）と .grid の grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr))（:38）の 2 箇所
- 日付ラベルのフォントは .chart-label { font-size: 11px }（:51）。これは viewBox 内部座標に対する 11px なので、実効サイズはチャートの実表示幅に比例する
- CSS は Tailwind も外部ファイルも使わず、STYLE テンプレート文字列（:27-52）を style へ raw() で埋め込む（:346-348）。public/style.css は紹介サイト用でダッシュボードからは参照されない
- 既存テスト: site/test/dashboard.test.ts の describe('グラフ描画')（:282〜）が svg class="chart" / rect class="chart-bar" の存在、SSE 配信 HTML にもグラフが含まれること（:295-301）、全値 0 のとき棒を描かないこと（:310）を検証している

決定済みの方針（ユーザー確認済み）:
- 表の削除はチャートを持つ節（日毎の推移 / 時間帯分布）に限る。「内訳（全期間の累計）」と「最新イベント」はチャートを持たないためそのまま残す
- バーは積み上げではなくグループ化（1 日あたり系列の本数だけバーを横並び）にする

留意点:
- グループ化は 1 スロットに系列数ぶんのバーを詰めるため、直近 14 日 × 5 系列でバーが細くなる。CHART.width（:75）の拡大や、1 チャートあたりの表示幅（:30 / :38）の見直しとセットで考える必要がある
- 日付ラベルの間引きは everyNthLabel={3}（:254, :265, :282）。幅が広がれば間引きを緩められる
- ユニーク訪問者はイベント種別 4 種とは母数の意味が異なるため、同一チャートに混ぜるか別扱いにするかは実装時に判断する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「日毎の推移」「時間帯分布」の各節が、系列を色分けしたグループ化バーチャート 1 枚に統合されている（系列ごとに別チャートを並べる構成ではない）
- [x] #2 各チャートに凡例があり、色と系列名の対応が読み取れる
- [x] #3 上記 2 節から表（SeriesTable）が削除されている。「内訳（全期間の累計）」と「最新イベント」の表は残っている
- [x] #4 チャートの表示幅が現状より広がっており、日付ラベルが間引きなしまたは現状より緩い間引きで読める
- [x] #5 日付ラベルのフォントサイズが現状より大きく、実表示で判読できる
- [x] #6 色分けが色覚特性に依存せず区別できる（色のみに頼らない、または区別可能な配色を選ぶ）
- [x] #7 既存の site/test/dashboard.test.ts のグラフ描画テストが新しい DOM 構造に追従して更新され、全テストが通る
- [x] #8 SSE による #summary の innerHTML 置換後もチャートと凡例が正しく描画される（クライアント JS に依存しないサーバサイド SVG 生成のまま）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. STYLE に系列色（Okabe-Ito 系の検証済み 5 スロット）を CSS 変数 + .chart-bar-N クラスで定義し、light/dark 双方の値を置く
2. BarChart を GroupedBarChart（series: {label, values}[] + labels: string[]）へ置き換える。1 グループ = 1 日/1 時間帯、その中に系列数ぶんのバーを横並び
3. 凡例（HTML の .legend、色スウォッチ + 系列名）を追加。凡例の並び順 = グループ内のバーの並び順にして、色以外の手掛かりを残す
4. SeriesTable を削除し、「日毎の推移」「時間帯分布」を SeriesChart 1 枚ずつに置き換える（.grid を使わない全幅）
5. 横幅: body max-width 60rem→76rem、CHART.width 640→960、height 140→220。日付ラベルは間引きなし（everyNthLabel 廃止）、.chart-label font-size 11px→13px
6. test/dashboard.test.ts のグラフ描画テストを新 DOM（chart-bar-N / legend / 間引きなし）へ追従。SSE 側も凡例を含むことを検証
7. vitest + typecheck を通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
配色は dataviz スキルの検証済みパレット（スロット1-5）を採用し scripts/validate_palette.js で実測: light は全チェック PASS だが aqua/yellow/magenta が対サーフェス 3:1 未満で WARN（relief 要）、dark は全 PASS。relief は表の復活ではなく「凡例の並び順 = グループ内バーの並び順」と各バーの <title>（系列名 + 値）で満たす（AC#3 が表の削除を要求しているため）。

実装: dashboard.tsx の BarChart/SeriesTable を GroupedBarChart + Legend + SeriesChart へ置換。CHART は width 640→960 / height 140→220、上端に topGap 18（最大値の目盛りを最も高い棒に重ねないための余白）。body max-width 60rem→76rem、.chart-label 11px→13px。日付・時間帯ラベルは間引き（everyNthLabel）を廃止。

検証（実測）:
- npx vitest run → 8 files / 133 tests all passed。npm run typecheck → エラーなし
- ダミーデータで HTML を生成して幾何を実測: チャート 2 枚のみ（系列ごとの並列描画ではない）、日毎 = 14 グループ × 5 系列 = 70 本（bar 幅 10.71 / ラベル間隔 68.6）、時間帯 = 24 グループ × 4 系列 = 96 本（bar 幅 6.5 / ラベル間隔 40.0）、ラベルは 14 件・24 件で間引きなし、NaN なし、最大値の棒は 180 = 220-22-18
- 実効フォントサイズ: viewBox 960 が幅 ~1184px（76rem - padding）に描かれるので倍率 1.23、13px → 実効 ~16px。変更前は .grid（minmax 16rem）で 3 列に分かれ 1 枚 ~272px、640 viewBox の倍率 0.43 で 11px → 実効 ~4.7px。ここが「日付ラベルが読めない」の実体だった
- 配色は dataviz の検証済みパレット スロット1-5、validate_palette.js で light/dark とも全 PASS（light のみ aqua/yellow/magenta が対サーフェス 3:1 未満の WARN）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
解析ダッシュボードの「日毎の推移」「時間帯分布」を、系列を色分けしたグループ化バーチャート 1 枚 + 凡例に統合し、両節の表を削除した（チャートを持たない「内訳」「最新イベント」の表は据え置き）。あわせて body 幅 60rem→76rem・viewBox 640→960 へ広げ、日付/時間帯ラベルの間引きを廃止してフォントを 11px→13px（実効 ~4.7px→~16px）にした。色は dataviz の検証済み 5 スロットを CSS 変数で light/dark 両対応にし、色のみに依存しないよう凡例の並び順をグループ内バーの並び順と一致させ、各バーに系列名と値の <title> を付けた。サーバサイド SVG 生成のままなので SSE の innerHTML 置換後も凡例ごと再描画される。vitest 133 件 / typecheck 通過、および生成 HTML の幾何実測で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
