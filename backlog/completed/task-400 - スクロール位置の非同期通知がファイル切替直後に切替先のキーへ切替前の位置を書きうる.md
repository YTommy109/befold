---
id: TASK-400
title: スクロール位置の非同期通知がファイル切替直後に切替先のキーへ切替前の位置を書きうる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-09 11:10'
updated_date: '2026-08-09 11:52'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 645000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-388 の設計レビュー（項目 8「非同期で置き換わる表示状態の世代管理」）で見つけた、TASK-388 とは別系統の穴。

ViewerWindowController の renderer(_:didChangeScrollPosition:mode:)（BefoldApp/befold/App/ViewerWindowController.swift）は、保存先のキーを **呼び出し時点の fileURL** から都度求める。fileURL はファイル切替・リネームで書き換わるため、切替直後に JS から遅れて届いた「切替前ファイルのスクロール位置」の通知が、**切替先ファイルのキーへ** 保存されうる。

対になる saveCurrentScrollPosition(for:mode:) は呼び出し側がキーを明示指定する形（WebViewCommandController）になっており、そちらは同じ穴を持たない。通知側だけが現在値参照のまま残っている。

想定される症状: ファイルをすばやく切り替えると、切替先の文書が切替前の文書のスクロール位置で開く。

対処の方針候補（着手時に /review-design で確定させる）:
- 通知に世代（contentUpdateGeneration 相当）や対象 URL を載せ、着地時に一致を確認して捨てる
- あるいは提示中の文書が変わった時点で、それ以前の通知を無効化する

未確認: 実機での再現手順は未取得（レビュー時のコード読みからの指摘）。再現には切替直後に JS からの通知が届く必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 遅れて届いたスクロール位置の通知が、切替先ファイルのキーへ保存されない
- [x] #2 その振る舞いが破れたら落ちるユニットテストがある
- [x] #3 対になる saveCurrentScrollPosition 側と、キーの決め方の考え方が揃っている（片方だけ現在値参照が残らない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 設計方針: スクロール位置の保存キーは「その位置が属する文書」から決める（現在値 fileURL は使わない）。通知側にもこの原則を通す。
2. ViewerRendererDelegate.renderer(_:didChangeScrollPosition:mode:) に、通知の出所となる文書の URL を載せる（renderer 側では描画済みミラー rendered.filePath を渡す）。世代番号(候補B)は新設しない — mode が既に JS 側 DOM 由来であるのと同じく、filePath も DOM が写している文書として既存の値で決まるため、新しい状態を増やす必要がない。
3. ViewerWindowController 側は受け取った URL をキーに保存する。URL が nil（描画未了・直接HTMLモード）なら保存しない。
4. テスト: (a) レンダラが rendered.filePath を通知へ載せること（ViewerRendererMessageHandlingTests）、(b) 切替後に旧 URL の通知が届いても切替先キーへ書かれないこと（ViewerWindowController 側）。
5. saveCurrentScrollPosition(for:mode:) は既に呼び出し側が明示キーを渡す形で原則に一致。doc コメントに原則を明記して両者を揃える。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ViewerRendererDelegate.renderer(_:didChangeScrollPosition:for:mode:) へ「その位置が属する文書」の URL を追加。レンダラは描画済みミラー rendered.filePath を載せ、ViewerWindowController はそれをキーに保存する（nil は捨てる）。世代番号は新設しなかった（mode が既に JS/DOM 由来であるのと同様、filePath も既存のミラーで決まるため）。

設計レビュー（/review-design）で確定した前提と裏付け:
- 通知は JS 側で 200ms デバウンスされる（コード参照: BefoldApp/BefoldKit/Resources/viewer-main.js:1235-1241, 1252-1259）。切替直後に旧文書の通知が届く経路が実在する。
- 復元位置が注入された描画（Swift 主導の切替）では JS 側が保留中の通知を破棄する（同 viewer-main.js:1224）。つまり残る穴は「render 適用より前に着地する通知」で、その時点では rendered.filePath はまだ旧文書 = 正しいキー。
- 既知の残存レグ（軽微・未修正）: rename 直後、再描画で rendered.filePath が更新されるまでの間に届いた通知は旧パスのキーへ書かれる（ScrollPositionStore.migrateScrollPosition は rename 時に実行済みのため孤児キーになる）。窓は極小で、ユーザー可視の症状は無い。

検証: swift test --skip Integration --skip FileWatcherTests → 1130 tests / 156 suites 全通過。新テストが空振りしないことを、保存先を fileURL 参照へ一時的に戻して確認（ViewerWindowScrollPositionNotificationTests の 2 件が失敗することを実測）。swiftformat --lint はエラー 0、変更ファイルに swiftlint の新規指摘なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
スクロール位置の保存キーを「現在表示中の fileURL」から「その位置が属する文書」へ変える。ViewerRendererDelegate の通知に出所の URL（レンダラの描画済みミラー rendered.filePath）を載せ、ViewerWindowController はそれをキーに保存する。これで JS 側 200ms デバウンスにより切替直後に届く旧文書の通知が、切替先のキーへ書かれなくなる。対になる saveCurrentScrollPosition も呼び出し側が明示キーを渡す形で同じ原則に揃い、双方の doc に明記した。担保として、レンダラがミラーの filePath を載せること／切替後の遅延通知が切替先キーへ書かれないこと／url が nil の通知を捨てることの 3 テストを追加（実装を戻すと落ちることを実測）。
<!-- SECTION:FINAL_SUMMARY:END -->
