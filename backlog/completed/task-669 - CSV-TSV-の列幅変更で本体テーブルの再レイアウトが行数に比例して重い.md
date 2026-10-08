---
id: TASK-669
title: CSV/TSV の列幅変更で本体テーブルの再レイアウトが行数に比例して重い
status: Done
assignee:
  - '@claude'
created_date: '2026-10-05 23:38'
updated_date: '2026-10-06 00:24'
labels: []
dependencies:
  - TASK-668
references:
  - 'https://github.com/YTommy109/befold/pull/708'
documentation:
  - docs/dev/file-type-display.md
priority: low
ordinal: 854000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-668 で fitColumn の測定対象を上位 200 セルに絞り、測定表の分は約 2.5 倍速くなったが、列幅を変えるたびに本体テーブル全体が再レイアウトされる分は残っている（行数に比例）。実アプリの resources を実 WKWebView で測った値（強制レイアウトを含む、ms）: フィット直後の追加コストは 10,000 行で 148〜616（初回の `csv-sized`＝`table-layout: fixed` への切替が約 606）、50,000 行で 788〜4,050（初回約 4 秒）。ドラッグ 1 move は 10,000 行で中央値 83・最大約 560、独立ハーネスでは 50,000 行で約 720。同期時間だけを測ると画面に出るまでの待ちが隠れる。原因の推測（`<col>` の幅変更で fixed レイアウトが全行を再計算する）は未検証。測定表を `#diagram-wrap` の外（body 直下）に置くと 2〜3ms だが、本番 CSS が効かず幅が +128px ずれるため使えなかった。利用者は現状ほぼ作者のみで、1 万行超の CSV での操作が対象。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 原因（どの操作が全行の再レイアウトを起こしているか）が実測で特定され、Notes に残っている
- [x] #2 10,000 行でのドラッグ 1 move とフィット直後の強制レイアウト込みの時間が、対策前後で同じハーネス・同じ条件で実測され、数値が Notes に残っている
- [x] #3 対策を入れる場合、選ばれる列幅・表示が現状と一致することがテストまたは実測で確認されている。入れない（許容範囲）と判断する場合は、その理由と閾値が Notes に残っている
- [x] #4 方針に合わせて docs/dev/file-type-display.md の「フィット」の性能の記述が更新されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実 WKWebView（ビルド済みアプリの resources、既存ハーネス）で、再レイアウトのコストを変種ごとに実測して原因を切り分ける（サブエージェント）。変種: 現状 / overflow-wrap:anywhere・min-width:0 の除去 / nowrap+ellipsis / content-visibility（効果の上限を見る目的）/ 最初から fixed レイアウト / ドラッグを pointerup でだけ確定（ガイド線）。フレーム時間（rAF）と強制レイアウト込みの両方
2. 結果から対策を選ぶ。単純化を先に検討する: 状態や分岐を増やす対策（行数しきい値での挙動切替など）より、CSS だけ・または経路を 1 本のまま済む対策を優先
3. 対策を入れる場合は、選ばれる幅・表示が現状と一致することをテストと実測で確認し、前後を同条件で実測。入れない場合は理由と閾値を Notes に残す
4. docs/dev/file-type-display.md の性能の記述を更新

5. 方針: (a) ドラッグ中の .csv-resizing クラス切替を廃止し、pointerdown で全面の透明オーバーレイ（cursor:col-resize、position:fixed、選択を抑止）を 1 要素だけ足して pointerup/cancel で外す（継承プロパティを table に触れない）。(b) 行数が LIVE_RESIZE_MAX_ROWS を超える表では、ドラッグ中は幅を更新せずオーバーレイ内の案内線だけ動かし、pointerup で 1 回だけ setWidth する。しきい値は 1 move の実測 12.8µs/行 から 2,000 行（約 26ms）を仮置きし、2,000 行で実測して確定。(c) 初回の fixed 切替（0.8 秒 / 4 秒）は避けられないので許容し、仕様書に数値で残す。キーボードの幅変更・フィットは離散操作なので現状のまま。
6. /review-design を実装前に 1 回回す（新しい状態＝ドラッグの確定方式の分岐を足すため）

7. /review-design の結果（実装前）: 方針変更なし。決めたこと — 案内線モードは pointerup だけで確定し、pointercancel・lostpointercapture（up 前）・再描画の cancelDrag では破棄（古い表へ確定しない）。オーバーレイと案内線は document.body 直下（ズームは #diagram-wrap のみにかかるので clientX をそのまま使える）。大きい表の判定は pointerdown の 1 回だけ、DOM の行数で行う。担保テスト: 案内線モードで move 中に col が変わらない／pointerup で 1 回だけ確定／cancelDrag で確定しない／ドラッグ中に表の class が変わらずオーバーレイがある／終了後にオーバーレイが残らない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
切り分け実測（ビルド済みアプリ resources・実 WKWebView・新ページ、強制レイアウト込み、中央値 ms。10,000 / 50,000 行）: 幅変更 1 回 128 / 368。初回（table-layout:fixed への切替）780 / 4,038（最初から fixed にしても、このコストが先払いになるだけ）。overflow-wrap・min-width の除去（V1）と content-visibility:auto（V3）は無効（127 / 367）で、折り返しは原因ではない。nowrap+ellipsis（V2）は 91（10k のみ。初回は悪化して 3,980）。選ばれる幅は全変種で一致。ドラッグのフレーム時間 105 / 585-640（約 10fps / 約 1.6fps）。
新たに分かったこと: 継承プロパティ（cursor・user-select）を table に切り替えるだけで幅変更 1 回分（cursor のみで 95 / 500、.csv-resizing の切替で 155 / 864）かかる。ドラッグの開始・終了で引っかかる原因。`.csv-resizing *` の `*` を外しても削減は 5〜12% で効かない（フレーム時間も不変）。
未確認: macOS 14 の content-visibility 対応（採用しないので不要）、実マウス・GPU 描画、実アプリのウィンドウ。

実装: ドラッグ中の .csv-resizing クラス切替を廃止し、body 直下の全面オーバーレイ（.csv-resize-overlay）に置換。行数が LIVE_RESIZE_MAX_ROWS=2000 を超える表は案内線（.csv-resize-guide）だけを動かし、pointerup で 1 回だけ setWidth（取り消し・再描画では確定しない、動かさず離しただけでは何もしない）。/review-design は実装前に実施済み（Plan 7）。
対策後の実測（ビルド済みアプリ resources＋リポジトリの新 viewer.html/bundle/style.css、実 WKWebView、csv-sized 済み、中央値 ms、旧→新）: pointerdown＋強制レイアウト 10,000 行 157→0、50,000 行 862→0。ドラッグのフレーム 10,000 行 105→14、50,000 行 641→14（アイドル並み）。pointerup＋強制レイアウト（確定 1 回）10,000 行 159→105、50,000 行 839→343。ライブ追従のフレーム（しきい値の根拠）1,000 行 14、2,000 行 20（いずれも 33ms 以内）。確定後の列幅は全行数で旧版と完全一致。ドラッグ中 elementFromPoint はオーバーレイを返し、td の cursor は auto（表に触れていない）、終了後にオーバーレイは残らない。
許容した残コスト: 初回の table-layout:fixed への切替（10,000 行 約 0.8 秒、50,000 行 約 4 秒）は最初から fixed にしても先払いになるだけなので操作時に払う。キーボードの幅変更・フィットは離散操作で 1 回分（10,000 行 約 0.13 秒）。
未確認: 実マウス・ポインタ捕捉・案内線の見た目・カーソルの見た目（実アプリのウィンドウ）、ライブ追従が 33ms を超える境目（外挿で約 3,000 行）、50,000 行の 1 回限りの 7 秒フレーム（旧版にも出る）の原因、macOS 14 の WebKit。
検証: viewer-csv-resize 17 件（新規 5 件は実装を戻すと落ちる）、Jest 693 tests、lint・format・循環・型・バンドルの CI 相当 7 ステップ通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ドラッグの引っかかりを 2 段で解消した。(1) 開始・終了時の継承プロパティ（cursor・user-select）の切替が全セルのスタイル再計算を起こしていた（10,000 行で約 0.15 秒、50,000 行で約 0.85 秒）ため、表の外の全面オーバーレイへ置換して 0 ms にした。(2) 行数が 2,000 を超える表はドラッグ中に案内線だけ動かし、離したときに 1 回だけ確定する（フレーム 10,000 行 105→14 ms、50,000 行 641→14 ms、確定 50,000 行 839→343 ms）。確定後の列幅は従来と一致。初回の table-layout:fixed 切替コストは許容し、仕様書に数値で記録した。実アプリのウィンドウでの見た目は未確認。
<!-- SECTION:FINAL_SUMMARY:END -->
