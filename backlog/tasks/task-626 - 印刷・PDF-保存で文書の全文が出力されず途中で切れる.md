---
id: TASK-626
title: 印刷・PDF 保存で文書の全文が出力されず途中で切れる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-09-15 15:37'
updated_date: '2026-09-16 00:34'
labels:
  - print
dependencies: []
references:
  - BefoldApp/befold/App/WebViewDocumentRenderer.swift
  - BefoldApp/BefoldKit/Resources/style.css
priority: high
type: bug
ordinal: 823000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Markdown ファイルを印刷 → PDF として保存すると、全文が PDF にならない。どこで切れるかの再現性は不明（ユーザー報告、2026-09-16）。

調査時点（2026-09-16）の手がかり（未実測、コード参照のみ）:
- style.css に @media print が 1 件も無く、画面用レイアウトのまま印刷される
- 画面用レイアウトは `body { height: 100vh; display: flex }` の中で `.viewer { flex: 1; overflow: auto }` がスクロールするスクロールコンテナ構造。高さ固定 + overflow:auto の箱は、印刷時にその箱の高さで内容が切り抜かれうる
- `WebViewDocumentRenderer.printDocument(over:)` は白紙対策として印刷ビューの frame を用紙 1 枚分（printInfo.paperSize）に設定している。100vh がこの高さに解決されると 1 ページ前後で切れる可能性がある
- 切れる位置がウィンドウサイズ・スクロール位置・ズームに依存するかは未確認。viewer.html を使う他の種別（.mmd / ソースコード表示の `#diagram-wrap.code-body` も height:100% + overflow:auto）も同じ構造で、同様に切れるかは未確認

まず再現条件（何ページ目で切れるか、ウィンドウの高さやスクロール位置で変わるか）を実測して特定すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 再現条件（切れる位置が何に依存するか）を実測し、Implementation Notes に記録する
- [x] #2 長い Markdown（複数ページ分）を印刷 → PDF 保存すると、ウィンドウサイズ・スクロール位置によらず全文が複数ページに分かれて出力される
- [x] #3 画面表示のレイアウト（スクロール・ズーム）に変化が無い
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. WKWebView + printOperation の実測ハーネスで再現条件を特定する
2. 単純化の余地（画面側のスクロールコンテナ構造そのものの廃止）を検討する
3. style.css に @media print を追加し、印刷時だけスクロールコンテナを解く
4. scripts/webview-smoke.swift に印刷の全文出力チェックを足し、修正を戻すと落ちることを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 再現条件（実測 / 2026-09-16）

WKWebView に viewer.html を実アプリと同じ経路で読ませ、`WebViewDocumentRenderer.printDocument`
と同じ NSPrintInfo 設定で PDF へ保存するハーネス（.tmp/print-probe.swift、スクラッチ）で実測した。
文書は番号付き段落 400 本の Markdown。

| ウィンドウ高 | スクロール位置 | ページ数 | 出た段落 |
|---|---|---|---|
| 500px | 先頭 | 1 | 1〜8 |
| 500px | 中間 | 1 | 201〜208 |
| 700px | 先頭 | 1 | 1〜11 |
| 700px | 中間 | 1 | 201〜211 |
| 1200px | 先頭 | 2 | 1〜19 |
| 1200px | 中間 | 2 | 201〜219 |

**出力されるのは常に「そのときウィンドウに見えている範囲だけ」。** ページ数はウィンドウ高で、
開始位置はスクロール位置で決まる。文書の長さには依存しない（400 段落でも 8〜19 段落しか出ない）。

原因は起票時の推測どおり。同じ実測で `document.body.scrollHeight = 700`（= ビューポート高）に対し
`.viewer.scrollHeight = 16048` だった。`body { height: 100vh; display: flex }` の中で
`.viewer { flex: 1; overflow: auto }` がスクロールコンテナになっているため、印刷対象の document
自体が 1 画面分の高さしか持たず、残りはクリップされる。

ソースコード表示も同じ（`#diagram-wrap.code-body pre code` が height:100% + overflow:auto）。
実測: 400 行のコードが修正前は 1 ページ 40 行、修正後は 9 ページ 400 行。

## 単純化の検討

画面側のスクロールコンテナ構造そのものを廃して body を普通に流す案（@media print が不要になる）を
先に検討したが、採らなかった。`.viewer.scrollTop` はスクロール位置の保存・復元
（`ViewerBridge.currentScrollPositionScript`）、検索・ジャンプのスクロール、ダイアグラムの
枠内ズーム（zoom.ts が `.diagram-zoom-scroll` の高さをインラインで書く）が依存しており、
波及が JS 全体に及ぶうえ AC #3（画面表示を変えない）に反する。

## 修正

style.css の末尾に `@media print` を 1 ブロック追加した。高さの制約と入れ子の overflow を
まとめて解き、画面に重ねるだけの UI（検索バー・切り詰めバナー・ズームコントロール）を消す。
種別ごとに分けず 1 ブロックに畳んであるので、md / mmd / ソースコード / 画像が同じ経路で直る。
`.diagram-zoom-scroll` の高さは zoom.ts がインラインで書くため !important が要る。

## 回帰の担保

`scripts/webview-smoke.swift`（/webview-smoke）に検証 6「印刷・PDF 保存で全文が出るか」を追加した。
400 段落を描画して実際に printOperation で PDF を作り、**出た段落数**を数える
（ページ数だけで見ると用紙設定や既定フォントが変わったときに通ってしまう）。

- 修正あり: `print: pages=31 paragraphs=400/400` → PASS
- 修正を戻すと: `print: pages=1 paragraphs=9/400` → `FAIL: 印刷で文書が途中で切れた(出たのは 9/400 段落)`

## 画面表示（AC #3）

`@media print` 内だけの追加なので画面には適用されない。実測でも同一:
修正前後とも md・高さ 700px で `viewer.scrollHeight/clientHeight/body.scrollHeight/scrollTop
= 16048/700/700/0`。webview-smoke の既存検証（mmd/md/法令XML 描画・CSP）も全て PASS。

## 環境メモ（このタスクとは無関係）

ローカル Xcode が 27.0 / Swift 6.4 に上がっており（CI ピンは 26.6）、`swift build` が
`AppDelegate.swift:73: main() must be @MainActor` で落ちる。作業ツリーは clean な状態で
再現するため既存のツールチェーンずれ。本タスクの変更（CSS と scripts/）はビルド対象外。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
`style.css` に `@media print` を追加し、印刷時だけ画面用のスクロールコンテナ構造（`body` の `height:100vh` と `.viewer` の `overflow:auto`、コード表示の `height:100%`、ダイアグラムの枠）を解いて、文書の実寸で用紙へ流し込むようにした。あわせて検索バー・切り詰めバナー・ズームコントロールを紙から外した。

検証は `scripts/webview-smoke.swift` に足した検証 6（400 段落を描画して実際に printOperation で PDF を作り、出た段落数を数える）。修正ありで `pages=31 paragraphs=400/400` の PASS、修正を戻すと `pages=1 paragraphs=9/400` で FAIL する。ウィンドウ高 500/700/1200px × スクロール先頭/中間の 6 通りでも全て 400/400 段落・31 ページで一致。ソースコード表示は 400 行が 1 ページ 40 行 → 9 ページ 400 行。画面表示は `@media print` 内だけの追加で変わらず、実測でもレイアウト値が修正前後で同一（16048/700/700/0）。
<!-- SECTION:FINAL_SUMMARY:END -->
