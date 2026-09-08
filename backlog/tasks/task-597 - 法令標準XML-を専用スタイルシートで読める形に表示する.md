---
id: TASK-597
title: 法令標準XML を専用スタイルシートで読める形に表示する
status: To Do
assignee: []
created_date: '2026-09-08 11:43'
labels: []
dependencies:
  - TASK-596
priority: low
ordinal: 850000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
e-Gov 法令検索が配布する法令XML (法令標準XMLスキーマ v3, https://laws.e-gov.go.jp/file/XMLSchemaForJapaneseLaw_v3.xsd) には表示用スタイルシートが同梱されていない。e-Gov 側もサーバーで HTML を生成しており、XSLT を配布していない (2026-09-08 時点で法令データ ドキュメンテーションに記載なし)。つまり TASK-596 の汎用 XSLT 経路では法令XMLは表示できず、befold 側が法令XML専用のスタイルシートを同梱する必要がある。

条・項・号・別表・附則という決まった構造なので変換自体は書けるが、TASK-596 の 5〜10 倍の規模になる。TASK-596 で汎用経路が入ってから、そこへ「スキーマを見て内蔵 XSL を選ぶ」形で乗せる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 法令標準XML v3 の namespace を検出したとき、内蔵スタイルシートを自動で適用する
- [ ] #2 条・項・号の階層と別表・附則が読める形で描画される
- [ ] #3 内蔵スタイルシートは TASK-596 の汎用 XSLT 経路に乗せ、専用の描画経路を新設しない
- [ ] #4 実際の法令XML (複数本) で描画を確認し、崩れる要素があれば Notes に列挙する
<!-- AC:END -->
