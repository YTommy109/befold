---
id: TASK-29.6
title: 検索の DOM 全量構築を廃止し表示範囲内検索にする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 13:23'
labels: []
dependencies:
  - TASK-29.3
parent_task_id: TASK-29
priority: high
ordinal: 7
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
loadAllLinesForSearch の仕組み（JS→Swift→全チャンク DOM 化→フリーズ）を削除し、表示済み DOM のみを検索する方式に変更する。切り詰め中は検索件数に「表示範囲内」と表示する。Swift 側の String 検索への完全移行は後続タスクとする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerWebView から loadAllLinesForSearch メッセージハンドラが削除される
- [x] #2 ViewerBridge から loadAllLinesForSearchMessageName / allLinesLoadedScript が削除される
- [x] #3 viewer.html/viewer.js から _mmdOnAllLinesLoaded / _mmdSetFindLoading が削除される
- [x] #4 Cmd+F が常に表示済み DOM のみを検索する
- [x] #5 切り詰め中は検索件数に「表示範囲内」の表示が付く
- [x] #6 検索入力が無効化されたままにならない（TASK-24 解消）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerBridge.swift: loadAllLinesForSearchMessageName / allLinesLoadedScript を削除。findStringsScript の 'loadingAll' キーを 'withinDisplayedRange'（表示範囲内ラベル）に置き換える。
2. Localizable.xcstrings: viewer.find.loadingAll エントリを削除し、viewer.find.withinDisplayedRange（en: 'Displayed range' / ja: '表示範囲内'）を追加。
3. viewer.html: _mmdSetFindLoading / _mmdOnAllLinesLoaded を削除。_mmdOpenFind() の isTruncated 分岐(loadAllLinesForSearch postMessage)を削除し常に _mmdFindRun() を呼ぶ。_mmdFindUpdateCount() に _mmdIsTruncated 時の '(表示範囲内)' サフィックスを追加。_mmdSetTruncated() で検索バーが開いていれば _mmdFindUpdateCount() を呼び直しラベルの即時反映を保証する。
4. ViewerWebView.swift: messageHandlerNames から loadAllLinesForSearchMessageName を削除。該当メッセージ分岐を削除。handleLoadMoreLines から untilFullyLoaded パラメータ・ループ・allLinesLoadedScript 評価を削除し単発チャンク読込に戻す。
5. befoldTests/ViewerBridgeTests.swift: loadAllLinesForSearchMessageNameValue / allLinesLoadedScriptValue テストを削除。findStringsScriptProducesValidJSONWithAllKeys の期待キーを更新。bridgeFunctionsExistInViewerHTML から該当アサーションを削除。
6. swift build / swift test で確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift build / swift test(345件, Integration/FileWatcher含む全件)/ npx jest(185件) / swift scripts/webview-smoke.swift(CSP・mmd・md描画)がいずれもパス。grep で loadAllLinesForSearch / allLinesLoadedScript / _mmdOnAllLinesLoaded / _mmdSetFindLoading / loadingAll が全ファイルから削除されたことを確認。加えて使い捨てのWKWebViewスモークスクリプト(scratchpad, 非コミット)で render→_mmdSetTruncated(true)→_mmdOpenFind→検索実行→appendChunk→_mmdSetTruncated(false) の流れを実機経路(loadFileURL)で検証: 切り詰め中は表示済み2件のみヒットしカウントに '(Displayed range)' ラベルが付与され検索入力は無効化されない(TASK-24解消)、チャンク追記・切り詰め解除後は3件目も検索対象に入りラベルが消える、ことを確認した。Localizable.xcstrings は viewer.find.loadingAll を viewer.find.withinDisplayedRange(en/ja翻訳済み)に置き換え、/l10n-check で翻訳漏れ0件を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
検索バーを開いた際に段階読み込み中の全チャンクを強制的にDOM化していた loadAllLinesForSearch の仕組み(JS↔Swiftの往復・入力欄の無効化・フリーズの原因)を削除し、Cmd+Fは常にその時点で表示済みのDOMのみを検索するように変更した。切り詰め中は検索件数表示に「表示範囲内」ラベル(viewer.find.withinDisplayedRange, en/ja)を付与して範囲限定であることを明示する。チャンク追記時は既存の _mmdFindRefreshAfterRender 経由で自動的に新規表示分も検索対象へ加わり、_mmdSetTruncated がラベルの即時反映も担う。検証: swift build/test(345)・npx jest(185)・webview-smoke、および使い捨てWKWebViewスクリプトによる実機経路での動作確認(表示範囲内のみヒット・ラベル表示・入力非無効化・追記後の再検索)。
<!-- SECTION:FINAL_SUMMARY:END -->
