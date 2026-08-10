---
id: TASK-421
title: exitDirectHTMLMode が in-flight の参照解決応答を取り消さない
status: To Do
assignee: []
created_date: '2026-08-10 07:29'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 509100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
要検証（レビューの判定は PLAUSIBLE。着手時にまず再現を確認し、再現しなければその根拠を Implementation Notes に残して閉じる）。

exitDirectHTMLMode（ViewerRenderer.swift:332-341）は isDirectHTMLMode / webViewProxy?.isDirectHTMLMode / appliedPageZoom / lastDirectHTMLPath / rendered / pendingAppend をリセットし reloadViewerHTML を呼ぶが、resolveResponseChain は取り消さない。ページ再読込で JS 側の FIFO キュー _mmdPendingRefBatches は空になる。

想定シナリオ: パス参照を含む Markdown を表示中、_mmdResolveReferences（viewer-main.js:319）が resolveReferences を post してバッチ A をキューに積む。Swift の handleResolveReferences は Task を連鎖し、解決は git サブプロセス（GitCommandRunner のタイムアウトは 10 秒）で秒単位かかりうる。応答が返る前にユーザーが .html（direct HTML モード）へ切り替えて戻ると、updateContent → exitDirectHTMLMode → reloadViewerHTML でページとキューが破棄される。新しいページが描画されてバッチ B を積んだところへ、バッチ A の Task が _mmdApplyResolvedReferences(mapA) を評価すると、shift() で取り出されるのは B で、A のマップが B の要素へ適用される。mapA に無い参照はすべて befold-link-dead になり href と title を失う。B の本来の応答は空のキューを shift して捨てられる。

ユーザーから見ると、実在するファイルへのリンクが灰色の死んだ参照になり、再描画するまでクリックできない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 まず再現手順で症状を確認し、結果（再現した／しなかった）を Implementation Notes に記録する
- [ ] #2 再現する場合、ページ再読込時に in-flight の参照解決応答が破棄される（新しいページのバッチへ適用されない）
- [ ] #3 世代（generation）等でバッチと応答が対応づき、取り違えたら落ちるテストを用意する
<!-- AC:END -->
