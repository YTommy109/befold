---
id: TASK-596
title: XSL を伴う XML を XSLT 変換してプレビューする
status: To Do
assignee: []
created_date: '2026-09-08 11:42'
labels: []
dependencies: []
ordinal: 849000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
e-Gov 電子申請の公文書ビューア (https://shinsei.e-gov.go.jp/recept/official-doc-view/) を befold で置き換えたいという要望があった。公文書は .xml と表示用の .xsl (XSLT 1.0) が対で配布され、表示ロジックは XSL 側にある。現状 befold は .xml をソースコードとしてしか開けないため、受け取った公文書を読むには外部サイトへアップロードする必要がある。

WebKit は libxslt 由来の XSLT 1.0 を持つため、xml と xsl を JS の XSLTProcessor に渡す汎用の変換経路を 1 本用意すれば足りる。法令標準XML のようにスタイルシートが同梱されないスキーマは対象外で、TASK 側で別途扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 xml-stylesheet 処理命令が指す .xsl を解決して変換に使う
- [ ] #2 処理命令が無い場合、同ディレクトリの同名 .xsl をフォールバックとして探す
- [ ] #3 xsl が見つからない .xml は従来どおりソースコード表示にフォールバックする
- [ ] #4 変換結果の HTML は既存のサニタイズ経路 (DOMPurify) を通してから差し込む
- [ ] #5 WKWebView 上で XSLTProcessor が動作することを実測で確認し、結果をタスクの Notes に残す
- [ ] #6 xsl または xml が不正な場合にエラーを表示し、クラッシュ・無限ロードしない
<!-- AC:END -->
