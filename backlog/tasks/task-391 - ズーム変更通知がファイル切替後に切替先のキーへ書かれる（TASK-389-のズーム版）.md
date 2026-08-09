---
id: TASK-391
title: ズーム変更通知がファイル切替後に切替先のキーへ書かれる（TASK-389 のズーム版）
status: Done
assignee: []
created_date: '2026-08-09 13:32'
updated_date: '2026-08-09 20:09'
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
- [x] #1 zoomChanged 通知が出所文書のキーで保存され、切替直後の遅延通知が切替先のキーを汚さない
- [x] #2 切替直後に届いた旧文書の zoomChanged が切替先のライブ zoom（store.zoom）を上書きしない
- [x] #3 scroll 側（TASK-389 修正）と同じ構造で実装されており、レースを再現するテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
TASK-393 の構造(JS が発火時に出所文書を payload で申告)を zoom へ再利用する。
1. viewer-main.js: 文書パスの所有を _createScrollSync から独立の _createDocPathTracker へ切り出す(scroll 専用ではなく「いま DOM に出ている文書」の owner)。scrollSync は tracker を注入で受け、beginRender で「保留通知の破棄」と「予告パスの採用」を従来どおり同一時点で行う。
2. zoomChanged の payload を裸の数値からオブジェクト {zoom, path} へ変える(ViewerBridge.PayloadKey.ZoomChanged を新設。payloadKeys の網羅 switch が nil→キー集合になるので契約テストが自動で追随する)。
3. ViewerRendererDelegate.renderer(_:didChangeZoom:for:) に出所 URL を足す(scroll 側と同じシグネチャの形)。既定実装ありなので QuickLook は無影響。
4. ViewerWindowController: 保存は必ず通知の url のキーへ。ライブ値 store.zoom の更新は url が現在の fileURL と一致するときだけ(AC2)。url nil の通知は捨てる。
5. 直接 HTML モードは viewer.js を経由せず WebViewCommandController.changeZoom が保存する経路のため、この変更の影響外(currentURL は同期的に読まれる)。
6. テスト: (a) native = payload の path をキーにする / 不一致なら store.zoom を上書きしない / path 欠落は捨てる、(b) jest = zoomChanged payload に採用済み docPath が載る・rename で追随する、(c) 契約テスト(payloadKeys)は自動追随。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-393 で scrollPositionChanged の保存キーを「JS が payload の path で申告する」構造へ移した。zoom の修正時はこの構造を再利用すること(zoomChanged payload に path を載せ、native 側の現在 URL 参照をやめる)。個別ガードを足さない。

設計判断: JS 側の文書パスは scroll 専用ではなくなるため owner を _createDocPathTracker へ切り出す(TASK-393 で scrollSync に置いたのは当時の唯一の消費者がスクロール通知だったため)。採用(adopt)は引き続き render 開始時に、保留デバウンス通知の破棄と同一同期区間で行う。

実装: zoomChanged の payload を裸の数値から {zoom, path} へ変え、保存キーを JS の申告値から決める(scroll と同一構造)。ViewerRendererDelegate は renderer(_:didChangeZoom:for:) へ。ViewerWindowController は保存を必ず通知の url のキーへ行い、ライブ値 store.zoom の更新は url が現在の fileURL と一致するときだけ行う(url nil は破棄)。
リファクタ: JS 側の文書パスの owner を _createScrollSync から _createDocPathTracker へ切り出した(scroll 専用ではなくなったため)。採用(adoptPending)は従来どおり render 開始時に、保留デバウンス通知の破棄と同一同期区間で行う。
検証: swift test 1238 件 / jest 391 件パス。AC1・AC2 = ViewerWindowZoomNotificationTests の 4 ケース(切替後の遅延通知が切替先のキーを汚さない / ライブ倍率を上書きしない / 一致時は両方更新 / nil は破棄)。AC3 = 構造が scroll と同一(payload の path 申告)であることを ViewerRendererZoomMessageTests 3 件 + jest 3 件(採用済みパスを載せる・描画前は null・rename 追随)で固定。契約テスト(payloadKeysByMessageName)は zoomChanged が nil→キー集合になったことで JS 側との突合対象へ自動的に入る。
swiftlint: main ベースライン比で新規違反ゼロ(zoom テストを ViewerRendererZoomMessageTests へ分割して file_length 超過を回避)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
zoomChanged の保存キーを JS が発火時に payload で申告する構造へ移し、ファイル切替直後に届く旧文書の通知が切替先の保存倍率とライブ倍率を汚す問題を解消した。TASK-389/393 のスクロール側と同一構造で、JS 側の文書パス所有は _createDocPathTracker に一本化。swift test 1238 件・jest 391 件で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
