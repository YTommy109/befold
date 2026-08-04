---
id: TASK-1.12
title: postMessage ブリッジのゲートと CSP unsafe-inline 削除で多層防御する
status: Done
assignee:
  - '@tommy109'
created_date: '2026-07-18 13:41'
updated_date: '2026-07-19 00:11'
labels: []
dependencies:
  - TASK-1.7
parent_task_id: TASK-1
priority: medium
type: enhancement
ordinal: 1160
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー（2026-07-18）の M-1/M-2（推奨、task-1.7 の多層防御）。(M-1) referenceActivated/loadMoreLines は hostFeatures ゲート対象外で常時有効（ViewerWebView.swift:145-151,226-231, viewer.html:66-70）。QuickLook 拡張ではこれらを登録せず、hostFeatures にリンク遷移無効フラグを追加し JS 側でも抑止する。(M-2) CSP script-src 'unsafe-inline'（viewer.html:13）が H-1 サニタイザのバックストップを無効化している。要因は viewer.html:56-1198 の大きなインライン <script>。インライン script を外部化 or nonce 付与し unsafe-inline を削除して、XSS 混入時もインラインイベントハンドラを CSP で遮断できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 QuickLook 拡張で referenceActivated/loadMoreLines が登録されずリンク遷移が抑止される
- [x] #2 CSP から script-src 'unsafe-inline' が削除され、インライン script が外部化 or nonce 化されている
- [x] #3 アプリ本体の既存操作（リンク遷移・ズーム・検索・Load More）に回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
M-1(postMessage ブリッジのゲート):
1. RendererFeatures に allowsInteractiveBridging: Bool(既定 true)を追加する(QuickLook 等の静的1回描画ホスト向けに referenceActivated/loadMoreLines のブリッジ全体を無効化する1つのフラグとして、直接HTMLモード/画像埋め込みと同じ既存の仕組みを再利用する)
2. ViewerWebView.messageHandlerNames を private static let から static func(for: RendererFeatures) -> [String] に変え、allowsInteractiveBridging が false のとき referenceActivated/loadMoreLines を除外する。makeNSView/dismantleNSView 双方をこの関数経由にする
3. ViewerBridge.hostFeaturesScript に referenceActivation: Bool を追加し、ViewerWebView が rendererFeatures.allowsInteractiveBridging をそのまま loadMore/referenceActivation 両方に渡す
4. viewer.html(→ viewer-main.js)の reference クリックハンドラと _mmdLoadMore() に isHostFeatureEnabled(window._mmdHostFeatures, 'referenceActivation'/'loadMore') の早期 return を追加する(JS 側の抑止。loadMore は既存フラグを流用、referenceActivation は新規)

M-2(CSP unsafe-inline 削除):
5. viewer.html の巨大インライン <script>(旧 57-1213行)を viewer-main.js として外部化し、<script src="viewer-main.js"> に置き換える(Package.swift に .copy 追加)
6. CSP の script-src から 'unsafe-inline' を削除する(style-src の 'unsafe-inline' は mermaid の動的 <style> 注入のため維持)

テスト:
7. Swift: RendererFeatures/messageHandlerNames(for:)/hostFeaturesScript の新規ユニットテスト、bridgeFunctionsExistInViewerHTML を viewer.html+viewer-main.js 結合検証に拡張、CSP unsafe-inline 不在を検証する新規テスト
8. scripts/webview-smoke.swift で実 WKWebView 上での CSP 下スクリプト稼働・mmd/md描画に回帰がないことを確認(mermaid遅延ロード化に伴う既存の古いアサーションも合わせて修正)
9. /run で実アプリを起動し、リンク遷移(referenceActivated)・検索(find)・Load More(loadMoreLines)に回帰がないことを目視確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test 395件全て成功(新規: messageHandlerNames の2件、hostFeaturesScript の referenceActivation 反映確認、bridgeFunctionsExistInViewerHTML の viewer-main.js 拡張、CSP unsafe-inline 不在テストを追加)。
scripts/webview-smoke.swift PASS(script-src 'self' のみで viewer.js/markdown-it/highlight/dompurify/viewer-main.js が全てロードでき、mmd/md描画・data画像埋め込み・外部画像ブロック・data:iframeブロック・PDF blob表示に回帰なし。mermaid.min.js 遅延ロード化(TASK-1.10)に伴い typeof mermaid の初期チェックが既に陳腐化していたためあわせて修正)。
/run で実アプリを起動し目視確認: (1) 相対リンククリックで別ウィンドウへの遷移(referenceActivated → onOpenReference)が動作、(2) cmd+F 検索で対象文字列がハイライトされ 1/1 件ヒット、(3) 1500行超のログファイルで Load More ボタンを繰り返し押下し全1504行が読み込まれる(loadMoreLines → handleLoadMoreLines が正常動作)ことを確認。いずれも allowsInteractiveBridging の既定値(true)でのアプリ本体挙動であり、AC3(回帰なし)を実機で裏付けた。
AC1(QuickLook 拡張での非登録・抑止)は、実際の QuickLook 拡張ターゲットが未作成(task-1.8/1.10/1.11 と同じ準備段階)のため、messageHandlerNames(for:)/hostFeaturesScript のユニットテストで allowsInteractiveBridging:false 時の除外・フラグ伝播を直接検証した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
M-1: RendererFeatures に allowsInteractiveBridging(既定 true)を追加し、false のとき ViewerWebView が referenceActivated/loadMoreLines の WKScriptMessageHandler を登録しない(Swift側)、かつ viewer-main.js の該当 postMessage 呼び出し(reference クリック・_mmdLoadMore)を hostFeatures 経由で抑止する(JS側)多層防御を実装した。QuickLook 拡張のような静的1回描画ホストが1つのフラグで両防御層を有効化できる設計。
M-2: viewer.html の巨大インライン <script>(旧1150行超)を viewer-main.js として外部化し、CSP の script-src から 'unsafe-inline' を削除した(style-src は mermaid の動的 <style> 注入のため維持)。これにより XSS がサニタイザ層をすり抜けてもインライン script/イベントハンドラの実行を CSP がブロックできる。
検証: swift test 395件成功(新規6件)、webview-smoke.swift で実 WKWebView 上の CSP 下スクリプト稼働・mmd/md描画に回帰なしを確認、/run による実アプリでのリンク遷移・検索・Load More の目視確認でAC3を裏付けた。
<!-- SECTION:FINAL_SUMMARY:END -->
