---
id: TASK-421
title: exitDirectHTMLMode が in-flight の参照解決応答を取り消さない
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 07:29'
updated_date: '2026-08-10 11:20'
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
- [x] #1 まず再現手順で症状を確認し、結果（再現した／しなかった）を Implementation Notes に記録する
- [x] #2 再現する場合、ページ再読込時に in-flight の参照解決応答が破棄される（新しいページのバッチへ適用されない）
- [x] #3 世代（generation）等でバッチと応答が対応づき、取り違えたら落ちるテストを用意する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. コードを読んで経路を確認し、まず失敗するテスト（再現）を書く。
2. 単純化の余地を検討する（既存の世代 contentUpdateGeneration を流用できるか）。
3. ページ読み直し専用の世代で、評価直前に一致を確認する。
4. 世代判定を外すとテストが落ちること（mutation check）を確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC1（再現確認）: 再現した。ViewerRendererResolveReferencesTests に、解決の最中に exitDirectHTMLMode（=viewer.html の読み直し）を起こすテストを追加したところ、修正前は飛行中の応答 _mmdApplyResolvedReferences({"./old.md":"/repo/old.md"}) が読み直し後も評価された。JS 側は _mmdApplyResolvedReferences が最も古い未応答バッチを shift する FIFO のため、これは新しいページのバッチへ古いマップが当たることを意味する。

単純化の検討（着手前）: 既存の contentUpdateGeneration を流用できないかを先に検討したが、流用不可と判断した。通常の再描画では JS 側が _mmdInvalidatePendingRefs() でバッチの中身だけを空にし、キューの長さ（未応答の要求数）は保つ設計のため、再描画をまたぐ応答は捨てずに評価し続ける必要がある。捨てるとキューが恒久的にずれ、以後すべての参照が解決失敗表示になる。捨ててよいのはキューごと消える読み直しの場合だけで、両者は別概念。この理由を pageGeneration の doc コメントに残した。

実装: pageGeneration を追加し、増やすのは reloadViewerHTML の 1 箇所だけにした。handleResolveReferences は要求受付時の世代を捕まえ、evaluateJavaScript の直前で一致を確認する。判定を要求受付時ではなく評価直前に置くのは、git 解決（GitCommandRunner のタイムアウトは 10 秒）を待つ間に読み直しが起きる窓を取りこぼさないため。直接 HTML モードへ入る側にも増分を置くか検討したが、入った直後の応答は関数の無いページで捨てられるだけでキューはずれず、テストで担保できない分岐が増えるだけなので置かないことにした。

検証:
- 追加テスト 2 本。1 本目は上記の再現（修正前は失敗、修正後は成功）、2 本目は「読み直しの後に出した要求は従来どおり応答される」で、破棄が広すぎないことを担保する（応答が来ないと pending のまま固まるため）。
- mutation check: guard pageGeneration == generation を外すと 1 本目が落ちることを実測（AC3 の「取り違えたら落ちる」担保）。
- フルスイート 1387 tests / 202 suites すべて pass（17.9 秒）。swiftformat 0 件。swiftlint は変更ファイル起因の新規指摘なし（MessageHandling.swift:122 の opening_brace は origin/main 時点で既存）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
exitDirectHTMLMode（viewer.html の読み直し）をまたいだ参照解決の応答が、新しいページの別バッチへ適用される問題を修正した。まず解決の最中に読み直しを起こすテストで再現を確認（AC1）。ページ読み直し専用の世代 pageGeneration を reloadViewerHTML の 1 箇所でだけ進め、評価直前に一致を確認して飛行中の応答を捨てる。既存の contentUpdateGeneration は、再描画では JS 側がキューの長さを保つ設計のため流用不可（捨てるとキューが恒久的にずれる）と判断し、理由を doc に残した。担保として、世代判定を外すと落ちるテストと、破棄が広すぎないこと（読み直し後の要求は従来どおり応答される）を確認するテストを追加。フルスイート 1387 tests すべて pass。
<!-- SECTION:FINAL_SUMMARY:END -->
