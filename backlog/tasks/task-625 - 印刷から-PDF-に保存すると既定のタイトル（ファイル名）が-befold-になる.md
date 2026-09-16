---
id: TASK-625
title: 印刷から PDF に保存すると既定のタイトル（ファイル名）が befold になる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 15:37'
updated_date: '2026-09-15 15:54'
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
- [x] #1 Markdown を印刷 → PDF として保存するとき、保存名の初期値が開いているファイル名（拡張子を除く）になる
- [x] #2 viewer.html を使う他の種別（.mmd / ソースコード等）と PDF 面でも同じ規則になっていることを実機で確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. DocumentCommandController.printDocument(over:) で currentDocument.url から拡張子を除いたファイル名を求め、DocumentSurfaceOperating.printDocument(over:jobTitle:) の必須引数で面へ渡す
2. WebViewDocumentRenderer / PDFDocumentRenderer は NSPrintOperation.jobTitle に設定するだけ
3. FakeDocumentRenderer で jobTitle を記録し、既存の転送テストで検証する
4. 実機で .md / .mmd / .swift / .pdf の PDF 保存名を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 保存名を決める場所は両方の面が通る DocumentCommandController の 1 箇所にした。各レンダラで window.title / representedURL から組む案は、同じ規則を 2 箇所に書くことになるので採らなかった。jobTitle は必須引数にして、新しい面を足しても渡し忘れられない形にした（デフォルト引数は付けない）。単純化の検討: 新しい状態も分岐も増えず、既存の currentDocument.url から導くだけなので、これ以上削れるところは無い。/review-design は回していない（状態・経路を増やさない局所修正のため）。responsibility-reviewer も起動していない（型・stored property・注入クロージャのどれも増やしていないため）。

検証:
- テスト: DocumentCommandControllerTests の「能力があれば、対応する命令がレンダラへ届く」が .print(jobTitle: "a")（/tmp/a.md）を期待する。コントローラが jobTitle に "befold" を渡すよう一時的に戻すと、このテストが renderer.commands の不一致で落ちることを確認した。
- 実機（Debug ビルド）: 印刷（⇧⌘P）→ PDF メニュー →「PDFとして保存…」を System Events で操作し、保存シートの名前欄をクリップボード経由で読み取った（読み取り後にクリップボードは元に戻した）。note-sample.md → note-sample、flow-sample.mmd → flow-sample、code-sample.swift → code-sample、doc-sample.pdf（PDF 面）→ doc-sample。修正前の値（befold）は、PDF 面も含めて実測していない。
- swift test --skip Integration --skip FileWatcherTests: 1876 件中 6 件失敗。PDFPageIndicatorModelTests / PDFSurfacePositionTests / PDFSurfacePageIndexTests で、git archive で展開した origin/main でも同じ 6 件が落ちる。ローカルの Xcode 27.0 と CI のピン（26.6）のずれによるもので、この変更とは無関係。
- ローカルの Xcode 27.0 では AppDelegate.main() の nonisolated がコンパイルエラーになる（CI のピンは 26.6）。検証の間だけ手元で @MainActor に書き換え、コミット前に元へ戻した。
- swiftlint: origin/main と比べて新規の警告は 0 件（46 件 → 46 件）。
- native-app-design.md への反映は不要: DocumentRendering の説明は「印刷」の粒度で書かれており、引数の追加では記述が変わらない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
印刷の保存名の初期値を、開いているファイル名から拡張子を除いたものにした。DocumentCommandController が名前を決め、printDocument(over:jobTitle:) で WebView 面と PDF 面に渡し、それぞれ NSPrintOperation.jobTitle に設定する。確認は 2 つ: 転送テスト（修正を戻すと落ちることも確認済み）と、実機での .md / .mmd / .swift / .pdf の「PDFとして保存」の名前欄の読み取り。
<!-- SECTION:FINAL_SUMMARY:END -->
