---
id: TASK-131
title: TextEncoding の相対タイミングテストがコールドスタートで判定が緩む
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:23'
updated_date: '2026-07-25 07:24'
labels:
  - test
dependencies: []
priority: low
ordinal: 73000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(wf_8350b192)で PLAUSIBLE 判定。befoldTests/TextEncodingTests.swift:57 の回帰テストは小さい入力を先(コールド)、大きい入力を後(ウォーム)に計測するため、初回のみのウォームアップコスト(page-in、String/ICU の遅延初期化)が elapsedSmall を数倍に膨らませ、線形スキャン回帰を捕まえるはずの 5x 閾値が緩む。逆に大計測中のスケジューラ揺らぎで flaky に赤くなる方向もある。
計測前にウォームアップ呼び出しを入れる、または複数回計測の最小値を使う等で安定化する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 計測前ウォームアップまたは複数回計測により、コールドスタートの影響を受けない
- [x] #2 線形スキャン回帰を検出できる閾値が維持される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 計測前にウォームアップ呼び出し(small/large 各1回)を入れ、page-in や ICU 遅延初期化を計測から外す
2. 各サイズを複数回計測し最小値を採る(スケジューラ揺らぎで上振れした計測を捨てる)
3. 閾値 5 倍 + 50ms スラックは維持する
4. detectWithFallback の sniff 窓を全データに変えるミューテーションで、閾値が回帰を検出できることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 計測前に small/large 各 1 回のウォームアップ呼び出しを行い、さらに各サイズ 5 回計測の最小値を採るようにした(befoldTests/TextEncodingTests.swift)。閾値は従来どおり elapsedLarge < elapsedSmall * 5 + 50ms を維持。

検証:
- 通常実行: 該当テストは 0.37 秒でパス(ウォームアップ + 5 回計測でも実行時間は許容範囲)。
- ミューテーション: TextEncoding.detectWithFallback の 1 段目 sniff 窓を data.prefix(sniffLength) から data(全走査)に変えると、elapsedLarge 6.73 秒 vs 閾値 1.71 秒 で fail することを確認(確認後 git checkout で復元)。線形走査回帰の検出力が維持されている。
- swift test 全体パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncodingTests の相対タイミングテストにウォームアップと 5 回計測の最小値採用を導入し、コールドスタート費用が small 側だけに乗って比率判定が緩む問題と、揺らぎによる誤 fail の両方を除いた。閾値(5 倍 + 50ms)は維持し、sniff 窓を全走査に変えるミューテーションで fail することを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
