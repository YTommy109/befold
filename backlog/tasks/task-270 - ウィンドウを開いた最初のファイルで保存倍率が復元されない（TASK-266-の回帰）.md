---
id: TASK-270
title: ウィンドウを開いた最初のファイルで保存倍率が復元されない（TASK-266 の回帰）
status: To Do
assignee: []
created_date: '2026-08-03 15:21'
labels:
  - bug
  - regression
dependencies: []
priority: high
type: bug
ordinal: 461000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review high で CONFIRMED。TASK-266 で ViewerWebView を常駐させたことにより、makeNSView が store.openFile より前に走るようになった。

## 経路
変更前は、ウィンドウ構築時点では entries が空でプレビュー対象が .folder(parentDir) になるため ViewerWebView が存在せず、makeNSView は一覧が届いた後（= store.filePath が入った後）まで遅延していた。現在は filePreview が opacity 0 で常に階層にあるため、ViewerWindowController.swift:252 の `window.contentViewController = makeSplitViewController(...)` の時点で ViewerWebView が作られる。これは同 :277 の `store.openFile(fileURL)` より前で、store.filePath はまだ nil。

その結果 ViewerContentView.currentZoom が ZoomStore.defaultZoom を返し、ViewerRenderer.makeWebView が atDocumentStart の user script に initialZoomScript(1.0) を焼き込む。以後の再適用は applyStoredZoom()（performFileSwitch からのみ）と reloadViewerHTML（直接 HTML モードの離脱）だけで、**ウィンドウを開いた最初のファイルには一度も走らない**。

## ユーザー影響
ファイルを 150% にして閉じ、同じファイルを開き直すと 100% で表示される。その状態でズームすると、誤った基準から保存値が上書きされる。

## 方針の候補
- store.filePath が確定した時点で保存倍率を適用する経路を用意する（applyStoredZoom を初回にも通す）
- または initialZoom を user script への焼き込みではなく updateNSView 経由の適用に寄せる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ファイルを任意の倍率にして閉じ、同じファイルを開き直すとその倍率で表示される
- [ ] #2 フォルダー→ファイルの切替、ファイル→ファイルの切替でも従来どおり保存倍率が復元される
- [ ] #3 回帰を捉えるテストがある（倍率の適用経路が初回ファイルでも通ることを検証する）
<!-- AC:END -->
