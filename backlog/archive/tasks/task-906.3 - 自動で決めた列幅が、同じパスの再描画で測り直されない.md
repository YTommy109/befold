---
id: TASK-906.3
title: 自動で決めた列幅が、同じパスの再描画で測り直されない
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:56:00Z'
updated_date: '2026-11-07T03:14:00Z'
labels: []
dependencies:
  - TASK-906.2
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: high
type: bug
ordinal: 869000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
自動で決めた幅と手動で変えた幅が同じ widths に入っている。prepareCsvResize は同じパスでは widths を捨てないので、initialWidths の対象が空になり測り直されない。

影響（コードからの判断、未実測）: ヘッダーだけの CSV に行が増えてもヘッダー幅のまま。保存で値が長くなっても切り取られたまま。桁区切りの設定変更は再描画するが幅は変わらず、数値の切り取りが悪化する。ファイル監視が中心機能なので、普通に起きる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 同じパスの再描画で、手動で変えていない列は測り直される
- [x] #2 手動で変えた列の幅は、同じパスの再描画でも保持される
- [x] #3 チャンク追記では、自動の幅も手動の幅も変わらない
- [x] #4 ヘッダーだけの CSV に行が増える場合と、桁区切りの設定変更の場合をテストが検証している
- [x] #5 `docs/dev/file-type-display.md` の「寿命」が実装と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 手動で変えた幅を manualWidths（列→幅）に分け、記録は setWidth だけで行う
2. prepareCsvResize は毎回 widths を捨て、手動の幅だけを戻す。別のパスでは手動の幅も捨てる。追記はこの経路を通らないので幅は動かない
3. initialWidths の収まる判定を「手動の幅 + 残りの列の自然幅」に広げ、収まれば残りの列は自然幅にする
4. 列が減ったら消えた列の手動の幅も捨てる
5. テストと file-type-display.md を更新し、大きな表の再描画時間を WebKit で計測する

/review-design: 項目 3（手動の幅が一部にある表の扱い）、5（再描画ごとの測定で大きな表の自動レイアウトが走るおそれ。実測する）を確認。他は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化: 自動の幅と手動の幅に別々の状態を持たせず、widths はそのままに手動の幅だけを manualWidths へ記録する。手動の幅を書くのは setWidth だけ。prepareCsvResize は widths を毎回捨てて手動の幅を戻すので、再描画は自動で測り直しになり、追記はこの経路を通らないので幅が動かない。

設計レビューの懸念を実測: 10,000 行の再描画が 375ms から 3,300ms に悪化した（測定用の表を測るときに本体の表まで自動レイアウトされる）。初回の測定中だけ本体の表を隠して、再描画 390ms、1 回目の描画も 3,300ms から 440ms になった。追記では文書が縮んで読む位置が失われるので隠さない（WebKit で幅あり 2000→2000、自動レイアウト 1500→1500 を確認）。

検証: jest 747 件成功。6 通り壊して落ちることを確認（自動の幅を保持 / 手動を記録しない / 手動の幅を合計に入れない / 常に隠す / 隠さない / 消えた列の手動の幅を残す）。lint・format・型検査は成功。

native-app-design.md への反映は不要（表示仕様は file-type-display.md を更新）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
手動で変えた幅だけを同じパスの再描画で保持し、他の列は再描画のたびに測り直すようにした。チャンク追記では幅を動かさない。

測り直しで大きな表の再描画が悪化したので、初回の測定中は本体の表を隠すようにした。10,000 行の 1 回目の描画も約 3.3 秒から約 0.4 秒に改善した。

残るリスク: 列の対応は位置なので、途中に列が挿入されると手動の幅が 1 つずれる（従来どおり）。
<!-- SECTION:FINAL_SUMMARY:END -->
