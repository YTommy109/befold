---
id: TASK-25
title: チャンク読み込みエラーが空チャンク・センチネルで偽装され、幻の空行行番号と「完全読込」誤表示が出る
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 10:55'
updated_date: '2026-07-17 00:36'
labels: []
dependencies:
  - TASK-29
references:
  - BefoldApp/befold/Viewer/ViewerStore.swift
  - BefoldApp/befold/Viewer/ViewerWebView.swift
  - BefoldApp/BefoldKit/Resources/viewer.html
priority: medium
type: bug
ordinal: 60
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerStore.loadMoreLines のエラーパス（ViewerStore.swift:161-169）が ("", isTruncated:false) のセンチネルを返す設計のため 2 つの実害がある。(a) Coordinator が appendChunk("") を送り、行番号 ON のコード表示では buildLineNumberRows("") が空内容の行番号付き <tr> を 1 行追加する（reflowSpanBalancedLines("") は [""] を返し pop 条件 length>1 を満たさない）— 幻の空行が末尾に残る。(b) isTruncated=false でバナーが消えるため、部分読込のファイルが完全表示として提示される。検索全量読込パスでも _mmdOnAllLinesLoaded が発火し、欠落コンテンツに対する検索が「完了」として実行される。エラーは UI にいっさい表出しない。テスト loadMoreLinesErrorKeepsContentAndStops はこの契約を意図として固定している。単純化検討: エラーをタプルのセンチネル値でなく明示的な結果（chunk / completed / failed(reason) の enum）として Store→Coordinator→JS に流し、バナーで「残りを読み込めませんでした」を表示する設計が本筋。最低限の修正は result.chunk.isEmpty のとき appendChunk をスキップし、エラー表示を追加する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 チャンク読込エラー時に幻の空行（空内容の行番号行）が追加されない
- [x] #2 エラーで部分表示になったことがユーザーに視認できる（完全読込と区別される）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer.js: buildLineNumberRows に空文字ガードを追加(空なら''を返す、幻の空行を防止)。jest回帰テスト追加。
2. ViewerStore.swift: LoadMoreLinesResult に loadFailed: Bool を追加。loadMoreLines() の catch 節で isTruncated は true のまま維持し loadFailed: true を返す(バナーは消さずエラー状態として区別)。正常系は loadFailed: false。
3. ViewerBridge.truncatedScript に failed 引数を追加(_mmdSetTruncated(isTruncated, lineCount, failed))。ViewerBridgeTests 更新。
4. viewer.html: failed=true のとき「続きを読み込めませんでした」バナー文言を表示しLoad Moreボタンを隠す。Localizable.xcstrings に banner.loadError キー追加。
5. ViewerWebView.handleLoadMoreLines: result.chunk.isEmpty のとき appendChunkScript 呼び出しをスキップ(防御的)。
6. ViewerStoreTests の loadMoreLinesErrorKeepsContentAndStops を拡張し loadFailed/isTruncated の契約を検証。
ユーザー承認済み(2026-07-17)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-29.6で検索が全量DOM構築から表示範囲内検索に変更され、loadAllLinesForSearch/_mmdOnAllLinesLoaded は削除済み(grep で該当なし)。よってAC#3(検索全量読込のエラー時部分表示)は対象機能自体が存在せず対応不能なため削除(ユーザー承認済み)。残るAC#1(幻の空行)・#2(エラー時の部分表示視認性)を対象に実装する。

実装: (1)viewer.html appendChunk() 冒頭で text が空なら早期return(幻の空行を防止。buildLineNumberRows('') は初回空ファイル描画で1行返す契約のためそちらは変更せず、append呼び出し側でガード)。(2)ViewerStore.LoadMoreLinesResult に loadFailed を追加、loadMoreLines()のcatch節でisTruncated=trueを維持しloadFailed=trueを返す(正常EOFと区別)。ViewerBridge.truncatedScript/_mmdSetTruncatedにfailed引数を追加しバナー文言を「続きを読み込めませんでした」に切替、Load Moreボタンを隠す。Localizable.xcstringsにbanner.loadErrorキー追加(en/ja)。ViewerWebView.handleLoadMoreLinesでresult.chunk.isEmptyのときappendChunkScript呼び出し自体もスキップ(防御)。検証: swift test 335件全パス(loadMoreLinesErrorKeepsContentAndStopsを新契約に更新)、npx jest 193件全パス、webview-smoke PASS、l10n-check(en/ja翻訳漏れ・プレースホルダ不一致なし)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
チャンク読込エラー時の幻の空行(AC#1)とエラー/正常完了の区別不能(AC#2)を修正。viewer.html の appendChunk は空チャンクを早期returnで無視し、ViewerStore.LoadMoreLinesResult に loadFailed を追加してエラー時もisTruncated=trueを維持、バナーを専用のエラー文言に切り替える(Load Moreボタンは隠す)。AC#3(検索全量読込)はTASK-29.6で当該機能自体が削除済みのためユーザー承認のうえ削除。swift test 335件・jest 193件全パス、webview-smoke PASS、l10n-check問題なしで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
