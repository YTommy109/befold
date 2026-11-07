---
id: TASK-906.6
title: 'PR #748 の軽微な指摘（後から増えた列・重複・古い記述）を片付ける'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:56:00Z'
updated_date: '2026-11-07T03:22:00Z'
labels: []
dependencies:
  - TASK-906.3
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: low
type: task
ordinal: 872000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
レビューの軽微な指摘をまとめたもの。201 行目以降で初めて値が出る列は 40px から始まる（仕様書に明記された制限）。測定表を作る処理が fitColumn と initialWidths で重複し、360 と 0.9 が名前の無い数値のまま。テスト名「増えた列は自然幅にする」とそのコメント、style.css の「table は自然幅または明示的な列幅で描き」が実装と合っていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 追記で増えた列は、追記された行も幅の測定対象になる
- [x] #2 測定表を作る処理が 1 か所にある
- [x] #3 初期幅の上限と分位点が名前付き定数になっている
- [x] #4 テスト名・コメント・`style.css` のコメントが実装と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 標本を「その列のセルがある行」から先頭 200 個集める形にし、追記で増えた列も追記された行で測る
2. 測定表の生成を 1 つの関数にまとめ、fitColumn と initialWidths から使う
3. 初期幅の上限と分位点を名前付き定数にする
4. テスト名・JSDoc・file-type-display.md を実装に合わせる

/review-design: 項目 6（列のセルが無い行の走査は追記で列が増えたときだけ。通常の表は 200 行で止まる）。他は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
追記で増えた列: 標本を「その列のセルがある行」から集める形にした。通常の表は 200 行で止まり、古い行にセルが無い列だけが先へ走査する。

古い記述: テスト名とコメントは TASK-906.3 で実装に合わせ済み。style.css の「table は自然幅または明示的な列幅で描き」は TASK-906.1 で自動レイアウトの表が復活したので正しくなり、変更していない。

検証: jest 753 件成功。旧来の標本の取り方へ戻すと落ちることを確認。lint・format・型検査・循環 import 検査は成功。全層を通した WebKit の確認（切り取り 167px / numClipped 0、検索 [771,0,0]→[0,771,0]→[0,0,0]、10,000 行 440ms/390ms、追記でスクロール位置を維持、PDF で全 9 セル）で退行なし。

native-app-design.md への反映は不要（表示仕様は file-type-display.md を更新）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
追記で増えた列を追記された行の値で測るようにし、測定表の生成を 1 か所にまとめ、初期幅の上限と分位点を定数にした。
<!-- SECTION:FINAL_SUMMARY:END -->
