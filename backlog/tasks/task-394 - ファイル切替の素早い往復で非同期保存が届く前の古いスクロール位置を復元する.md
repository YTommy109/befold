---
id: TASK-394
title: ファイル切替の素早い往復で非同期保存が届く前の古いスクロール位置を復元する
status: To Do
assignee: []
created_date: '2026-08-09 13:33'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 653000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の PLAUSIBLE 指摘。

`beginPresentingDocument` は performFileSwitch 時に保存スクロール位置を **同期的に** 読むが、切替元の位置保存（saveScrollPositionBeforeTransition）は WKWebView の JS ラウンドトリップを介した **非同期** 書き込み。ファイル A をスクロール → A→B → 即座に B→A と往復すると、A の新しい位置の書き込みコールバックより先に `restoredScrollPosition(for: A)` が実行され、古い位置を復元する。`store.scrollPositionToRestore` は提示開始の 3 契機でしか設定されないため、遅れて完了した保存が拾い直されることもない。

参照: ViewerWindowController.swift:489 付近、WebViewCommandController.swift:113-116、WebViewDocumentRenderer.swift:82-84

発生窓は狭い（JS ラウンドトリップ 1 回分）ため優先度は低。修正するなら「保存完了を待ってから切替する」か「切替先の読み直しを保存完了後に行う」のいずれかで、TASK-393 の構造検討と合わせて判断するのがよい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A→B→A の素早い往復でも、A で最後にスクロールした位置が復元される
<!-- AC:END -->
