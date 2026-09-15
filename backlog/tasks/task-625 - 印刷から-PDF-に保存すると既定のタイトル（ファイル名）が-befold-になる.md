---
id: TASK-625
title: 印刷から PDF に保存すると既定のタイトル（ファイル名）が befold になる
status: To Do
assignee: []
created_date: '2026-09-15 15:37'
labels:
  - print
dependencies: []
references:
  - BefoldApp/befold/App/WebViewDocumentRenderer.swift
  - BefoldApp/BefoldKit/Resources/viewer.html
priority: medium
type: bug
ordinal: 822000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Markdown ファイルを印刷 → PDF として保存すると、既定のタイトル（保存ファイル名の初期値）が「befold」になる。開いているファイル名が妥当（ユーザー報告、2026-09-16）。

調査時点（2026-09-16）の手がかり（未実測、コード参照のみ）:
- `WebViewDocumentRenderer.printDocument(over:)`（BefoldApp/befold/App/WebViewDocumentRenderer.swift）は NSPrintOperation の jobTitle を設定していない
- viewer.html は `<title>befold</title>` 固定で、viewer-src に document.title を書き換える箇所は無い（rg で 0 件）
- どちらが PDF 保存名の由来かは未確認。PDF 面（PDFDocumentRenderer.printDocument）も jobTitle を設定しておらず、同じ症状が出るかは未確認
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Markdown を印刷 → PDF として保存するとき、保存名の初期値が開いているファイル名（拡張子を除く）になる
- [ ] #2 viewer.html を使う他の種別（.mmd / ソースコード等）と PDF 面でも同じ規則になっていることを実機で確認する
<!-- AC:END -->
