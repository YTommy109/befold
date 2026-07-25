---
id: TASK-131
title: TextEncoding の相対タイミングテストがコールドスタートで判定が緩む
status: To Do
assignee: []
created_date: '2026-07-24 22:23'
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
- [ ] #1 計測前ウォームアップまたは複数回計測により、コールドスタートの影響を受けない
- [ ] #2 線形スキャン回帰を検出できる閾値が維持される
<!-- AC:END -->
