---
id: TASK-597
title: 法令標準XML を専用スタイルシートで読める形に表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 11:43'
updated_date: '2026-09-09 09:15'
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
- [x] #1 法令標準XML v3 のルート要素（Law + Era/Num）を検出したとき、内蔵スタイルシートを自動で適用する
- [x] #2 条・項・号の階層と別表・附則が読める形で描画される
- [x] #3 内蔵スタイルシートは TASK-596 の汎用 XSLT 経路に乗せ、専用の描画経路を新設しない
- [x] #4 実際の法令XML (複数本) で描画を確認し、崩れる要素があれば Notes に列挙する
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 前提の訂正: namespace では判定できない

AC#1 は起票時「namespace を検出したとき」だったが、これは成立しない。法令標準XML
スキーマ v3（`XMLSchemaForJapaneseLaw_v3.xsd`, Version 3.0 / Nov 24 2020）は
`targetNamespace` を宣言しておらず、ルート要素 `Law` も無名前空間にある
（実測: `grep -c targetNamespace v3.xsd` = 0）。判定は
**ルート要素が `Law` で必須属性 `Era` と `Num` を持つこと**に変え、AC#1 を書き換えた。
走査はルート要素の開始タグに限る（本文の例示に引きずられないため）。

## 実装

- `JapaneseLawStylesheet`（BefoldKit）が判定と内蔵 XSL の供給を持つ。
  `XSLStylesheetResolver.resolve` の**最後の候補**として差し込むので、以降は
  同ディレクトリに `.xsl` があるときとまったく同じ経路を通る（AC#3。描画経路は増えていない）。
  文書に添えられた `.xsl` が常に優先される。
- ルート要素の走査は `XSLStylesheetResolver.rootElementStart` を共有する
  （走査範囲の規則を 2 箇所に持たせない）。
- `Resources/japanese-law.xsl`（XSLT 1.0、329 行）は構造とクラス名だけを決め、
  見た目は `style.css` の `.law-*` が持つ。XSL に `<style>` を埋めない理由は
  DOMPurify を通ることと、見た目の定義が二重化すること。
- 未対応の要素は既定規則で中身をそのまま出す（v3 は 100 種類ほどあり、名指ししていない
  ものが必ず残る。落とすと本文が黙って消える）。

## 検証（AC#4）

実データ 6 本を e-Gov 法令API v1 から取得し、実 WKWebView の `XSLTProcessor` で描画。
`scripts/webview-smoke.swift` に検証項目 3.3 として常設した（jsdom には XSLTProcessor が
無く `Resources/__tests__` では確認できないため）。結果は
`xslt-body クラス/条数/項数/見出し数/#mmd-error` の順:

| 法令 | 結果 |
| --- | --- |
| 日本国憲法 | `1/103/164/11/`（エラーなし） |
| 労働基準法 | `1/255/458/91/` |
| 民法 | `1/1374/2287/451/` |
| 国税通則法 | `1/412/859/187/` |
| 国家公務員法 | `1/342/745/178/` |
| 労働基準法施行規則 | `1/230/542/262/` |

本文の取りこぼしが無いことは別途 xsltproc（libxslt = WebKit と同系）の出力に対して
`Sentence` / `ArticleTitle` / `ItemTitle` / `ChapterTitle` / `AppdxTableTitle` /
`SupplProvisionLabel` / `RemarksLabel` の全テキストが含まれるかで確認（6 本すべて欠落 0）。

## 崩れる・対応しない要素（AC#4）

- **図（`Fig`）**: 元データが `./pict/*.pdf` 等への外部参照で、法令XML単体には含まれない。
  取得もしない（リモート・兄弟ファイル読み出しの両方を避ける）ため `［図：パス］` と出す。
  実測: 労働基準法施行規則で 63 件。
- **縦書き（`WritingMode="vertical"`）**: 無視して横書きで描く。実測: 同法施行規則に 1,942 件。
- **表の罫線**: `BorderTop="none"` 等の `none` だけを見て消す。`solid` / `dotted` の
  線種は区別しない。
- **所得税法（17.43MB）**: TASK-608 の全量読み込み上限（本体 10MB）を超えるため、
  チャンク読み込みのソース表示のまま。変換はされない。
- **QuickLook 拡張**: `RendererFeatures.allowsSiblingFileReads` が false のため
  `RenderableContent.make` が XSLT 差し替えごと止める。内蔵スタイルシートは兄弟ファイルを
  読まないので原理的には出せるが、ゲートの意味を変える話なので本タスクでは触っていない。

## 検証コマンド

- `swift test --skip Integration --skip FileWatcherTests` → 1857 tests / 306 suites 全通過
- `swift scripts/webview-smoke.swift` → PASS
- `/swiftlint-baseline`: origin/main との「真の新規」ゼロ
- `npm run format:check` / `markdownlint-cli2` → いずれも 0 件
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
法令標準XML（e-Gov 法令検索）に当てる内蔵スタイルシート `japanese-law.xsl` を BefoldKit へ同梱し、`XSLStylesheetResolver` の最後の候補として供給する。判定は namespace ではなくルート要素 `Law` + 必須属性 `Era`/`Num`（スキーマ v3 に targetNamespace が無いことを実測で確認）。TASK-596 の汎用 XSLT 経路にそのまま乗せ、描画経路は増やしていない。実データ 6 本（憲法・労基法・民法・国税通則法・国家公務員法・労基則）を実 WKWebView の XSLTProcessor で描画確認し、その検証を webview-smoke へ常設した。
<!-- SECTION:FINAL_SUMMARY:END -->
