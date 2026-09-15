---
id: TASK-626
title: 印刷・PDF 保存で文書の全文が出力されず途中で切れる
status: To Do
assignee: []
created_date: '2026-09-15 15:37'
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
- [ ] #1 再現条件（切れる位置が何に依存するか）を実測し、Implementation Notes に記録する
- [ ] #2 長い Markdown（複数ページ分）を印刷 → PDF 保存すると、ウィンドウサイズ・スクロール位置によらず全文が複数ページに分かれて出力される
- [ ] #3 画面表示のレイアウト（スクロール・ズーム）に変化が無い
<!-- AC:END -->
