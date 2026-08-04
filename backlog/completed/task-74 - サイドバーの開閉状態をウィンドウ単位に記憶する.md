---
id: TASK-74
title: サイドバーの開閉状態をウィンドウ単位に記憶する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-19 11:53'
updated_date: '2026-07-19 14:25'
labels: []
dependencies: []
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状サイドバー(ファイルツリー)の開閉状態はウィンドウ単位で記憶されていない。
ウィンドウごとに開閉状態を保持し、新規ウィンドウを開いたときのデフォルトは
「ユーザーが最後に操作したサイドバー開閉状態」かつ「最後にアクティブだった
ウィンドウの設定」を引き継ぐ。

参考: 既存の永続化パターンとして SessionStore
(App/SessionStore.swift、noteActivated/savedActivePath でアクティブウィンドウの
記録を UserDefaults に永続化している)や PerFileStateStore
(App/PerFileStateStore.swift、ファイル単位の状態記憶)がある。新規ウィンドウの
デフォルト値解決は「最後にアクティブだったウィンドウ」の状態を参照する点で
SessionStore の noteActivated の仕組みと関連する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 各ウィンドウでサイドバーの開閉状態を個別に切り替えられ、切り替えた状態がそのウィンドウに保持される
- [x] #2 既存ウィンドウのサイドバー開閉状態はアプリ再起動後も復元される
- [x] #3 新規ウィンドウを開いたとき、サイドバーの初期開閉状態は最後にアクティブだったウィンドウの状態を引き継ぐ
- [x] #4 起動直後などアクティブウィンドウの記録がない場合はユーザーが最後に操作した開閉状態にフォールバックする
- [x] #5 他ウィンドウのサイドバー開閉状態を変更しても、既存の他ウィンドウの表示状態には影響しない
- [x] #6 各ウィンドウのサイズ・位置(フレーム)を個別に保持し、リサイズ/移動した状態がそのウィンドウに保持される
- [x] #7 既存ウィンドウのフレームはアプリ再起動後もウィンドウ単位に復元される(現状は単一の共有フレームが全ウィンドウに適用されており、これを解消する)
- [x] #8 新規ウィンドウを開いたとき、フレームの初期値はサイドバー開閉状態と同じ優先順位(自身の保存値→直近アクティブだったウィンドウの値→既定のカスケード配置)で解決する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarStateStore を新設 (ZoomStore と同型: ファイルパスキーの UserDefaults 辞書, isCollapsed(for:)/setCollapsed(_:for:)/migrate(from:to:)), PerFileStateStore に登録する
2. フォールバック用グローバル値 lastToggledSidebarCollapsed を追加 (HiddenFilesPreference と同型の単一 Bool)
3. ViewerSplitViewController の toggleSidebar(_:) から開閉変化を外部へ通知する onSidebarCollapsedChange クロージャを追加
4. ViewerWindowController に makeSplitViewController() の戻り値を保持するプロパティを追加し、初期サイドバー状態を (a) SidebarStateStore の保存値 (再オープン時) → (b) SessionStore.savedActivePath() 経由で参照した直近アクティブウィンドウの状態 (新規ファイル時) → (c) lastToggledSidebarCollapsed (フォールバック) の優先順で解決。forceSidebarVisible (CLI由来) は最優先で上書き
5. トグル時に SidebarStateStore と lastToggledSidebarCollapsed の両方を更新
6. rename 時は既存の PerFileStateStore.migrate フローに相乗りさせる
7. ZoomStoreTests.swift のパターン (makeIsolatedDefaults, 複数インスタンス間の永続化検証, rename移行テスト) を踏襲してTDDで進める(完了)

--- 以下、AC#6-#8(ウィンドウフレームのウィンドウ単位記憶)を追加実装 ---
8. WindowFrameStore を新設 (SidebarStateStore と同型: PathKeyedDictionary<String> でファイルパスキーのフレーム記述子(NSWindow.frameDescriptor)を保持。setFrameDescriptor(_:for:)/frameDescriptor(for:)/recordUserAdjustedFrame(_:for:)/lastUserAdjustedFrameDescriptor/initialFrameDescriptor(for:lastActivePathKey:)/migrateFrameDescriptor(from:to:))、PerFileStateStore に登録し migrate に相乗りさせる
9. ViewerWindowManager.openViewer で initialSidebarCollapsed と同様に initialFrameDescriptor を解決し、ViewerWindowController へ渡す(自身の保存値 → 直近アクティブウィンドウの値 → 最後にユーザーが調整したフレーム → nil ならこれまで通り既定カスケード配置)
10. ViewerWindowController.init の『defaults.string(forKey: lastWindowFrameKey) から復元』を注入された initialFrameDescriptor に置き換え、既存の共有 lastWindowFrameKey とその保存処理(saveWindowFrame)は WindowFrameStore への保存(recordUserAdjustedFrame)に置き換える(fileURL キー)
11. offsetFrameToAvoidOverlap は既存動作を維持(自身の保存値・引き継ぎ値のどちらでも重なる場合はずらす)
12. WindowFrameStoreTests.swift / PerFileStateStoreTests.swift / ViewerWindowManagerTests.swift に SidebarStateStore と対になるテストを追加し TDD で進める
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ユーザー指摘: 複数ウィンドウを開いて再起動すると、両方とも同じウィンドウサイズで復元される(ViewerWindowController.lastWindowFrameKey が全ウィンドウ共有の単一キーであるため)。サイドバー開閉状態と同じ保存ロジック(SidebarStateStore と同型のファイルキー辞書 + 直近アクティブ引き継ぎ)を再利用して解決する方針で本タスクに統合する(AC#6-#8 追加)。

検証結果: swift test (482 tests, 59 suites) 全て pass。AC#1/#5 は SidebarStateStoreTests(per-file独立性・recordToggle)+実機での手動トグル確認(ユーザー確認済み)。AC#2 は SidebarStateStoreTests(インスタンス跨ぎ永続化)+ViewerWindowManagerTests(保存値の再オープン時保持)。AC#3/#4 は ViewerWindowManagerTests(直近アクティブウィンドウ引き継ぎ)+SidebarStateStoreTests(フォールバック優先順位)。AC#6/#7 は WindowFrameStoreTests+ViewerWindowControllerTests(リサイズ/クローズ時の記録、initialFrameDescriptor注入)に加え、実機で a.mmd/b.mmd を異なるサイズ・位置にリサイズしてアプリを再起動し、両ウィンドウがそれぞれ個別の位置・サイズで復元されることをユーザーが目視確認済み(「位置、サイズともに復元されました」)。AC#8 は WindowFrameStoreTests(初期フレーム解決の優先順位)+ViewerWindowManagerTests(直近アクティブウィンドウのフレーム引き継ぎ)。swiftformat --lint / swiftlint も新規コードに起因する新たな重大違反なし(既存の型/ファイル長系警告のみ)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー開閉状態とウィンドウフレーム(位置・サイズ)をともにウィンドウ(=ファイル)単位で永続化するよう変更した。SidebarStateStore/WindowFrameStore を新設し(いずれも ZoomStore と同型のファイルパスキー辞書 + 直近アクティブウィンドウ引き継ぎ + 最終フォールバック値)、PerFileStateStore に統合(migrate に相乗り)。ViewerWindowManager.openViewer が SessionStore.savedActivePath() を使って新規ウィンドウの初期値を解決し、ViewerWindowController/ViewerSplitViewController はその解決結果を受け取って適用するだけの薄い層にした。ウィンドウフレームは従来 UserDefaults の単一共有キーで全ウィンドウに同じ値を適用していたが、これを廃止しウィンドウ単位の記憶に変更(ユーザー指摘により当初のサイドバースコープから拡張)。TDD で実装し、swift test 482件全て pass。実機ビルドでサイドバートグルとウィンドウフレームの再起動後復元をユーザーが目視確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
