---
id: TASK-137
title: ウィンドウ登録簿クエリの委譲を整理し switchFile の二重探索を解消する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 04:54'
labels:
  - refactor
  - structural
  - app
dependencies: []
priority: medium
ordinal: 59000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
controllers 辞書([String: ViewerWindowController], ViewerWindowManager)への問い合わせが SidebarNavigator.isFileOpenElsewhere → ViewerWindowController.isFileOpenElsewhere(単純転送)→ delegate.viewerWindow(_:isFileOpenInAnotherWindow:) → ViewerWindowManager.isOpenInAnotherWindow の 3 段パススルーを経る。ViewerWindowController は論理を足さず 2 つ目のプロトコル名で再公開するだけ。さらに switchFile は delegate.isFileOpenInAnotherWindow(newURL) の後 true なら delegate.focusWindowForFile(newURL) を呼び、manager 側では両方が existingOtherController で解決するため同じ辞書 lookup+!== ガードが 1 操作で二重に走る。ViewerWindowControllerDelegate(7メソッド)が登録簿の実装詳細を leak する chatty interface。構造レビュー(2026-07-25)で検出。TASK-116.13(VWM への controller 生成注入)とは別 seam。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 boolean 判定と focus を 1 つの delegate 呼び出し(例: existing target を optional で返す)へ統合し、switchFile の二重 lookup が解消している
- [x] #2 SidebarNavigatorHost が登録簿クエリを直接転送し、ViewerWindowController の並行プロトコル名再宣言が不要になっている
- [x] #3 swift build/test が通り、別ウィンドウで開いているファイルへのフォーカス挙動に回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 単純化検討: 登録簿クエリ用の新メソッドを増やす代わりに、performFileSwitch の戻り値を Bool から結果 enum(switched / failed / openInAnotherWindow(controller))へ変え、登録簿への問い合わせを performFileSwitch 内の 1 箇所へ閉じる。これで SidebarNavigatorHost から登録簿クエリ(isFileOpenElsewhere)と死んだメンバー(switchFile)が消え、switchFile の二重 lookup も消える。
1. テスト先行: 別ウィンドウで開いているファイルへの切替でそのウィンドウが前面化されること(現在テストが無いカバレッジギャップ)と、履歴ナビゲーションが同条件で前面化せず中止されることを characterization テストとして追加し、現行コードで通ることを確認する
2. ViewerWindowControllerDelegate の isFileOpenInAnotherWindow / focusWindowForFile を、対象ウィンドウを optional で返す 1 メソッドへ統合する。ViewerWindowManager 側は existingOtherController 1 回の lookup で解決する
3. performFileSwitch を FileSwitchOutcome 返しに変え、open-elsewhere 判定をその先頭へ移す。switchFile は outcome で分岐(前面化 + 選択復元 / 選択復元 / 同期)、applyHistoryEntry は .switched 以外を中止として扱う(前面化しない現行挙動を維持)
4. SidebarNavigatorHost から isFileOpenElsewhere と未使用の switchFile を削除し、VWC の同名転送メソッドも削除する
5. swift build / swift test / jest で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: performFileSwitch の戻り値を Bool から FileSwitchOutcome(switched / failed / openInAnotherWindow(controller))へ変更し、登録簿への問い合わせを performFileSwitch 内の 1 箇所へ閉じた。ViewerWindowControllerDelegate は isFileOpenInAnotherWindow + focusWindowForFile の 2 メソッドを windowShowingFileElsewhere(対象コントローラを optional で返す)1 メソッドへ統合し、ViewerWindowManager 側の existingOtherController / isOpenInAnotherWindow / focusExistingWindow の 3 ヘルパーは辞書 lookup 1 回のデリゲート実装へ畳んだ。switchFile は outcome で分岐し、前面化は返された ViewerWindowController.focusWindow() へ委譲(openViewer の既存ウィンドウ再利用経路も同メソッドへ統一)。

SidebarNavigatorHost からは登録簿クエリ(isFileOpenElsewhere)と、宣言のみで一度も host 経由で呼ばれていなかった switchFile を削除し、ViewerWindowController 側の同名転送メソッドも削除した。履歴移動は .switched 以外を中止として扱い、前面化しない現行挙動を維持している。

検証: swift build ok / swift test 637 tests 全通過 / npx jest 266 PASS / webview-smoke PASS。追加テストは、別ウィンドウで開いているファイルへの切替が前面化対象のコントローラを結果として返すこと(RED をコンパイル失敗で確認)と、履歴移動が同条件で中止されること(現行挙動の characterization。実装前に通過することを確認)の 2 本。performFileSwitch から別ウィンドウ判定を取り除く変異で 3 テストが失敗することを確認済み。

注意: makeKeyAndOrderFront 自体の効果は非アクティブなテストプロセスでは isKeyWindow が立たず観測できないため、前面化の目視確認はリリース前手動チェックに残る(TASK-137 以前も同様)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
登録簿クエリの 3 段パススルーを解消した。performFileSwitch が FileSwitchOutcome を返すようにして登録簿への問い合わせを 1 箇所へ集約し、デリゲートは対象ウィンドウを optional で返す 1 メソッドへ統合(辞書 lookup は 1 操作 1 回)。SidebarNavigatorHost からは登録簿クエリと未使用の switchFile 宣言を削除し、ViewerWindowController の並行名転送メソッドも消えた。swift test 637 / jest 266 / webview-smoke 通過、変異注入で新旧テスト 3 本の検知力を確認。前面化の目視確認のみ手動チェックに残る。
<!-- SECTION:FINAL_SUMMARY:END -->
