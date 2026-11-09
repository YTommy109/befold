---
id: TASK-925
title: Mermaid 図の描画前に naturalHeight を測ると、図の枠が小さいまま残る
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T04:58:00Z'
updated_date: '2026-11-09T11:16:00Z'
labels:
  - bug
  - viewer
dependencies:
  - TASK-924
references:
  - https://github.com/YTommy109/befold/pull/771
priority: low
type: bug
ordinal: 890000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #771 のレビュー中の実測で見つけた既存の不具合で、PR が持ち込んだものではない。_mmdWrapDiagrams は naturalHeight をラップ時に 1 回だけ測るので、SVG の描画前に包まれた図は枠の高さが古いまま残り、図の大部分が枠内スクロールの向こうに隠れる。

実測（WKWebView、1200x800、図は 8 エッジの graph TD、2 回とも同じ結果）: 図 1 個の描画後に appendChunk を同じ tick で 2 回呼ぶと、3 個目の図が natural 154 / 枠 116px / 中身 639px になる。PR 適用前の main（4771f4d0 以降）でも、入れ子の内側のラッパーが natural 154 / 枠 116px になる。appendChunk の間隔が 0ms / 30ms、または描画完了を待つ場合は再現しなかった。

未確認: 実際のアプリでこの状況が起きるか。Swift 側は isLoadingMoreLines で追記の交錯を防いでおり（ViewerRenderer+RenderHelpers.swift の handleLoadMoreLines）、同じ tick の 2 回呼び出しは通常の経路では起きない可能性がある。描画に時間がかかる図で間隔を空けた場合、再現しなかった理由、mermaid.run の並行実行が原因かどうかも未確認。原因の説明はこの実測からの推定で、確定ではない。PR #771 のガードが無い状態を前提に直すと二度手間になるので、取り込み後に着手する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 実際のアプリの追記経路で再現するかどうかが、測定条件（図の重さ・追記の間隔）とともに Notes に記録されている
- [x] #2 再現条件を満たす追記の後でも、すべての図の枠の高さが描画後の図の高さに追従している。アプリの経路で起きないと判断して直さない場合は、その根拠が Notes に記録されている
- [x] #3 直す場合は、修正を戻すと落ちる回帰テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実 WKWebView と実アプリの経路で再現条件を測り、Notes に記録する
2. _mmdRunMermaid の対象は呼び出し時に同期で選び、mermaid.run と包む処理だけを前の実行の後へ直列化する（/review-design 項目 5: 順番が来てから選ぶと、古い render が新しい DOM を選び、次の render が描画済みの図を再描画して壊す）
3. _mmdWrapDiagrams は渡された図だけを包む（必須引数）。diagramIndex は全図の順番、#771 の closest ガードは維持
4. mermaid.run を制御できる偽物で回帰テストを書き、修正を戻して落ちることを確かめる
5. バンドル再生成、実アプリの行列を修正後に測り直す、一時 NSLog を剥がす
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因（実測で確定）: _mmdRunMermaid の完了時に _mmdWrapDiagrams が容器内の未ラップの図をすべて包むため、別の実行が描画待ちの図まで描画前の高さで包んでいた。mermaid.run は描画 1 件ずつしか直列化しない（mermaid.min.js の run / render）。重なりの窓は次の 2 つ。図の重さは関係しない（200 エッジでも、ロード済みなら間隔 0〜1000ms で再現なし。描画中の macrotask は 0 回で、対照の sleep(50) は 1520 回）。
(a) mermaid.min.js のロード完了前に次の追記が届く
(b) ラベルに読み込みの遅い画像を持つ図の描画中（26MB の PNG で 132ms、macrotask 4515 回。ロード済みでも間隔 0 / 30ms で再現）

実アプリの経路での測定（2026-11-09、Debug ビルド、一時コードで loadMoreLines を 4 回送り、Swift の handleLoadMoreLines → updateContent → appendChunk を通して枠を測定。各条件 3 回。文書 6 ブロック、図 8 エッジ）。再現回数を修正前 → 修正後で示す。
a-load-window（先頭チャンクに図なし、1 チャンク約 1000 行の軽い本文）: 20ms 1→0 / 50ms 0→0 / 150ms 0→0 / 300ms 0→0
b-plain（先頭チャンクに図あり）: 全間隔 0→0
d-heavy（先頭チャンクに図なし、1 行に装飾 40 組の重い本文）: 20ms 0→0 / 50ms 2→0 / 150ms 3→0 / 300ms 3→0
再現時の値はタスク記載と同じ natural 154 / 枠 116 / 中身 639。修正前は mermaid を初めて使う追記の次の図で起きた。つまり Swift の isLoadingMoreLines は取得の重なりを防ぐだけで、描画の重なりは防がない。

WKWebView の単体ハーネスの修正後: 未ロードから同じ tick を含む 31 シナリオで再現 0、画像ラベルの間隔 0 / 30ms は枠 290 / 中身 290（修正前は枠 116 / 中身 272）。

未確認: 実マウスでの操作は未確認（AX から Web コンテンツが見えず、ボタンのクリックではなくブリッジへの送信で代用。d-heavy の 150ms が人のダブルクリック相当という位置付けは推定）。data: 画像の図の実アプリ測定は結果が返らず未測定（e-dataimg、6.9MB）。file:// の別パスの画像は CSP 等で読めず、画像の窓(b)は実アプリでは未確認。最初に取った 36 回の結果は、復元された別ウィンドウの値を拾っていたため破棄した。

単純化の検討と設計: 枠を後から測り直す案は zoom 適用後の実測になるため不採用。状態を増やさず包む対象の限定だけで済むかも測ったが、図 2 個の実行の残りを次の実行が奪うと不足する（戻すと「図 2 個の実行の途中で追記」が落ちる）。そのため実行の直列化（_mermaidRunTail 1 個）を併用した。/review-design 項目 5 で、当初案の「順番が来てから対象を選ぶ」は render の連続で描画済みの図を作り直すと判明し、「呼び出し時に同期で選び、実行だけ直列化」へ変更した。PR #771 に続く同型の問題なので、容器全体の走査をやめる構造で塞いだ。

回帰テスト（viewer-main-markdown-append.test.ts の 3 件）を修正を戻して確認: 渡された図に限定しない → 3 件すべて落ちる / 直列化しない →「図 2 個の実行の途中で追記」が落ちる / 順番が来てから選ぶ →「render が重なっても 1 度しか描画しない」が落ちる。_mmdWrapDiagrams の引数は必須で、渡し忘れは型エラー。

既存テストの変更: viewer-main-find-highlight.test.ts の 1 件は mermaid のロード開始が同期である前提だったため、microtask を 1 回待つ形にした（ロード開始が 1 microtask 遅れる）。

検証: Jest 23 スイート 761 件、typecheck / lint / format:check、swift test（--skip Integration --skip FileWatcherTests --skip PDF）1897 件 + 77 件が成功、known issue 1 件。PDF 系は未実行。Swift の差分はなし（一時 NSLog は除去済み）で swiftlint の差分確認は不要。xcodebuild はこの修正を含めて通った（当時は一時 NSLog を含む）。

docs/dev への反映は不要（内部の実行順の修正で、構成・表示仕様に変更なし）。

補足: 上の「ロード済みなら間隔 0〜1000ms で再現なし」の間隔は macrotask をまたぐ場合（setTimeout）の値。起票時の条件（ロード済みで同じ tick に appendChunk を 2 回）も修正前後のバンドルで測った。修正前は 8 / 200 エッジとも 3 個目が natural 154 / 枠 116（中身 639 / 14751）で起票時の値と一致、修正後は 4 シナリオすべて再現なし。同じ tick の窓は実アプリの通常経路では起きない見込み（appendChunk は evaluateJavaScript ごとに別タスクで呼ばれる）で、実アプリで再現したのはロード待ちの窓。

実アプリの測定の読み方: 修正後の d-heavy 20ms は図 1 個、50ms は図 1〜2 個までしか追記されず（isLoadingMoreLines で要求が落ちる）、重なりの検証としては弱い。修正の効果を示すのは図 4 個まで追記された 150 / 300ms（修正前 6/6 → 修正後 0/6）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
追記時に図の枠が小さいまま残る不具合を直した。実アプリの経路で再現し（重い本文の文書で追記間隔 150 / 300ms のとき 6 回中 6 回）、修正後は同条件で 0 回。図の重さではなく、mermaid のロード待ちなどで実行が重なると、先の実行が描画前の図まで包むのが原因だった。_mmdRunMermaid を対象の同期選択 + 実行の直列化に、_mmdWrapDiagrams を渡された図だけ包む形に変えた。回帰テスト 3 件は修正を戻すと落ちることを確認済み。実マウスでの操作と data: 画像の図は未確認（Notes 参照）。
<!-- SECTION:FINAL_SUMMARY:END -->
