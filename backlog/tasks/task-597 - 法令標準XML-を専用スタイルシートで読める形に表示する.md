---
id: TASK-597
title: 法令標準XML を専用スタイルシートで読める形に表示する
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-08 11:43'
updated_date: '2026-09-09 08:52'
labels: []
dependencies:
  - TASK-608
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

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 前提の訂正（実測）

AC#1 の「namespace を検出したとき」は成立しない。法令標準XML v3 スキーマ
（https://laws.e-gov.go.jp/file/XMLSchemaForJapaneseLaw_v3.xsd, Version 3.0 / Nov 24 2020）
には targetNamespace が無い（`grep -c targetNamespace v3.xsd` = 0）。ルート要素 `Law` も
無名前空間。したがって判定は **ルート要素名 `Law` + 必須属性 Era/Num の存在** で行う。

## 方針

1. `XSLStylesheetResolver.resolve` に 3 番目の候補として「内蔵スタイルシート」を足す。
   優先順位は 処理命令 href → 同名 .xsl → 内蔵（利用者が置いた xsl が常に勝つ）。
   新しい描画経路は作らない（AC#3）。`RenderableContent.make` は無変更。
2. 判定は `JapaneseLawXML.looksLikeLaw(xml:)`（プロローグ〜ルート開始タグだけを見る
   文字列判定。既存の `rootElementStart` と同じ範囲の走査を使う）。
3. 内蔵 XSL は `BefoldKit/Resources/japanese-law.xsl`（XSLT 1.0）。
   `Bundle.befoldKitResources` から読む。Package.swift の resources と
   project.yml の両方へ追加する。
4. 見た目は XSL 側に持たせず、`style.css` の `.xslt-body .law-*` クラスへ置く
   （XSLT 出力は DOMPurify を通るため、`<style>` に依存しない）。
5. 対応する構造: LawTitle / LawNum / EnactStatement / Preamble / TOC /
   Part・Chapter・Section・Subsection・Division の見出し / Article（Caption/Title）/
   Paragraph（Num/Caption/Sentence）/ Item / Subitem1〜10 / Sentence / Column /
   Ruby・Rt / Sup・Sub / List / TableStruct（Table/TableRow/TableColumn/
   TableHeaderRow）/ Remarks / ArithFormula / Fig / StyleStruct /
   AppdxTable・AppdxStyle・AppdxNote・AppdxFig・AppdxFormat / SupplProvision
   （SupplProvisionLabel / SupplProvisionAppdxTable 等）。
6. 検証は実データ 7 本（憲法・民法・労基法・国家公務員法・所得税法・労基則・国税通則法）。
   `sample/` には小さめの 1 本を置き、大きいものはスクラッチパッドで確認する。

## テスト

- `XSLStylesheetResolverTests`: 法令XML で内蔵 XSL が返る / 同名 .xsl があればそちらが勝つ /
  ルートが Law でない XML では nil（従来どおり）。
- `japanese-law.xsl` 自体は `Resources/__tests__` の JS テストで XSLTProcessor 相当
  （jsdom には XSLTProcessor が無いため、node の xslt ライブラリは入れない）→
  実データでの描画確認は手動 + 崩れは Notes に列挙する。
<!-- SECTION:PLAN:END -->
