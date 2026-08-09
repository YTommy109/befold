---
id: TASK-391
title: ズーム変更通知がファイル切替後に切替先のキーへ書かれる（TASK-389 のズーム版）
status: To Do
assignee: []
created_date: '2026-08-09 13:32'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 647000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high の CONFIRMED 指摘。

`renderer(_:didChangeZoom:)`（BefoldApp/befold/App/ViewerWindowController.swift:575 付近）はライブ値 `store.zoom` と永続値の両方を **窓の現在の fileURL** でキーする。ズーム操作（cmd+= やピンチ）直後にサイドバーでファイルを切り替えると、切替前文書の zoomChanged が遅れて届いた時点で、切替先の保存倍率を復元済みの `store.zoom` を旧文書の倍率で上書きし、さらにそれを **切替先のキーへ** 保存する。切替先ファイルは以後開くたびに誤った倍率で表示される。

これは TASK-389 がスクロールで直したのと同型のレースの **2 件目**。CLAUDE.md の「同型のバグが 2 回目に出たら構造で塞ぐ」に従い、個別の防御ではなく scroll と同じ構造（通知に出所文書のパスを載せ、保存キーを出所から決める）へ揃えること。scroll 側と異なり `handleZoomChanged` は出所文書の情報を運んでいない（ViewerRenderer+MessageHandling.swift:52-54）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zoomChanged 通知が出所文書のキーで保存され、切替直後の遅延通知が切替先のキーを汚さない
- [ ] #2 切替直後に届いた旧文書の zoomChanged が切替先のライブ zoom（store.zoom）を上書きしない
- [ ] #3 scroll 側（TASK-389 修正）と同じ構造で実装されており、レースを再現するテストがある
<!-- AC:END -->
