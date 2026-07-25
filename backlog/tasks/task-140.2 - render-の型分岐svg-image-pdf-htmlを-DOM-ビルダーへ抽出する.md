---
id: TASK-140.2
title: render() の型分岐(svg/image/pdf/html)を DOM ビルダーへ抽出する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:42'
updated_date: '2026-07-25 02:47'
labels:
  - refactor
  - structural
  - js
dependencies:
  - TASK-140.1
parent_task_id: TASK-140
priority: medium
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
render()(viewer-main.js:978-1133, 155行)の 9 分岐型ディスパッチのうち svg/image/pdf/html 分岐が viewer.js の buildTableHtml/renderCodeHtml/csvRowsHtml と同じ純粋ビルダー抽出パターンから漏れてインライン DOM 構築している。各分岐を _renderSvg/_renderImage/_renderPdf/_renderHtml(可能な部分は viewer.js 側の純粋 HTML ビルダー)へ切り出し、render() を型→ヘルパー選択+共通オーケストレーション(mermaid/annotate/find/zoom/scroll)に縮小する。TASK-140.1 のエクスポート境界導入が前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 svg/image/pdf/html の各分岐がヘルパー関数へ抽出され、純粋化可能な部分は viewer.js の HTML ビルダーとして単体テストされている
- [x] #2 render() 本体が型ディスパッチ+共通オーケストレーションに縮小している
- [x] #3 各型の描画(mmd/svg/html/csv/image/pdf/code/md)に回帰がない(webview-smoke + 手動確認)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 単純化検討: (a) if/else 連鎖をディスパッチテーブル(_RENDERERS)へ置き換える案 → Swift 側 ViewerBridgeTests の fileTypeJSValuesMatchRenderBranches() が viewer-main.js 内の "type === '<jsValue>'" を文字列一致で検査しており、テーブル化すると Swift↔JS のドリフト検知テストの書き換えが必要になる。分岐の抽出という本題に対して契約テストの意味を弱めるリスクが上回るため不採用。(b) 採用: 型分岐の骨格(if/else)は残したまま各分岐の本体をヘルパーへ切り出す。render() は「型→ヘルパー選択 + 共通オーケストレーション」に縮小され、既存のドリフト検知はそのまま効く。

1. viewer.js に純粋ビルダーを追加(DOM 非依存・単体テスト可能):
   - svgDataURI(svgText)            : UTF-8 → base64 の data URI 化(現行の btoa(unescape(encodeURIComponent(...))) をそのまま踏襲)
   - imageDataURI(base64, mimeType) : 既定 image/png のフォールバック込み
   - base64ToBytes(base64)          : PDF の Blob 生成用のバイト列復号
   いずれも module.exports に追加する。
2. viewer-main.js の render() 各分岐を DOM ビルダーへ抽出する(いずれも diagramWrap を受け取る):
   _renderMmd / _renderSvg / _renderHtml / _renderCsv / _renderImage / _renderPdf / _renderCode / _renderMarkdown
   - markdown-it 未ロード時のみ後続処理(mermaid/annotate/find/zoom/scroll)を飛ばす現行挙動は、_renderMarkdown が false を返し render() が早期 return する形で維持する。
   - PDF の blob URL 解放(_pdfBlobUrl)は「PDF 以外への切替でも解放する」現行仕様のため render() 側の共通処理に残す。
3. render() は「スクロール退避 → 状態更新 → source モード委譲 → クラス一括除去 → blob 解放 → 型分岐でヘルパー呼び出し → mermaid 実行 → annotate/find/zoom/scroll」に縮小する。
4. __tests__/viewer.test.js に 1 の純粋ビルダーのテストを追加。__tests__/viewer-main.test.js に各型の描画結果(生成される DOM 構造・クラス付与)のテストを 140.1 のハーネス経由で追加する。
5. 検証: npx jest / swift test(ViewerBridgeTests の型分岐ドリフト検知含む) / swift scripts/webview-smoke.swift(AC#3)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
- viewer.js に純粋ビルダー svgDataURI / imageDataURI / base64ToBytes を追加(いずれも DOM 非依存、module.exports に追加済み)。
- viewer-main.js の render() 各分岐を DOM ビルダーへ抽出: _renderMmd / _renderSvg / _renderHtml / _renderCsv / _renderImage / _renderPdf / _renderCode / _renderMarkdown。あわせて mermaid 実行部も _mmdRunMermaid() へ切り出した。
- markdown-it 未ロード時に後続処理を飛ばす現行挙動は _renderMarkdown が false を返し render() が早期 return する形で維持。
- PDF の blob URL 解放は「PDF 以外への切替でも解放する」現行仕様のため render() 側の共通処理に残した。
- html 分岐の iframe.sandbox 代入を setAttribute('sandbox', ...) に変更。WebKit では等価だが、DOMTokenList 反映の実装差に依存せず属性値として検証できるようになるため(セキュリティ属性のテスト到達性を確保)。

型分岐の骨格(if/else)は意図的に残した。Swift 側 ViewerBridgeTests.fileTypeJSValuesMatchRenderBranches() が "type === '<jsValue>'" の文字列一致で Swift↔JS のドリフトを検知しているため、ディスパッチテーブル化するとその契約テストを書き換える必要があり、分岐抽出という本題に対して割に合わないと判断した。

規模: render() 155 行 → 69 行。

検証:
- npx jest: 238 passed(viewer.test.js に純粋ビルダー 7 件、viewer-main.test.js に render 型ディスパッチ 11 件を追加)
- swift test: 615 tests / 86 suites passed(型分岐ドリフト検知 fileTypeJSValuesMatchRenderBranches を含む)
- swift scripts/webview-smoke.swift: PASS(mmd/md 描画・data: 埋め込み画像・PDF blob 表示・CSP ブロックを実 WKWebView で確認)

AC#3 について: webview-smoke(実 WKWebView)は PASS し、mmd/md/image(data URI)/pdf(blob) の実描画と CSP ブロックを確認済み。jest 側で svg/html/csv/image/pdf/code/md の DOM 構築も検証している。ただし AC#3 が求める『手動確認』(実アプリでの svg/csv/code/html の目視)は未実施のため、AC#3 は未チェックのままにしている。

AC#3 の手動確認を実施(ユーザーによる目視、2026-07-25)。xcodebuild で .app をビルドして起動し、svg(sample/diagram.svg・ズームコントロール込み)/ csv(sample/sample.csv)/ code(sample/example.swift)/ html(新規追加した sample/sample.html)/ mmd(sample/flowchart.mmd)/ md(sample/sample.md、内部の mermaid フェンス込み)の描画に問題がないことを確認。image / pdf は webview-smoke が実 WKWebView で自動検証済み。

あわせて sample/ に .html が存在せず html 型の確認手段がなかったため、sample/sample.html を追加した(ページ内 CSS・見出し/段落/引用/箇条書き/テーブルに加え、sandbox に allow-scripts が付かないことを目視判定できるスクリプトを含む)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
render() の svg/image/pdf/html 分岐がインライン DOM 構築のままだったのを、型別 DOM ビルダー(_renderMmd/_renderSvg/_renderHtml/_renderCsv/_renderImage/_renderPdf/_renderCode/_renderMarkdown)へ抽出し、純粋化できる data URI 生成と base64 復号は viewer.js の svgDataURI/imageDataURI/base64ToBytes として切り出した。mermaid 実行部も _mmdRunMermaid() へ分離し、render() は型ディスパッチ+共通オーケストレーションに縮小(155行 → 69行)。型分岐の if/else 骨格は Swift 側のドリフト検知テストを維持するため意図的に残した。検証: npx jest 238 passed(純粋ビルダー 7 件・render 型ディスパッチ 11 件を新規追加)/ swift test 615 passed / webview-smoke PASS / 実アプリでの svg・csv・code・html・mmd・md の目視確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
