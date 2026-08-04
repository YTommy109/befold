---
id: TASK-67
title: 小粒の衛生課題を解消する（死んだ注入・fileExists 重複・JS リテラル化・ブリッジ突合テストの穴）
status: Done
assignee: []
created_date: '2026-07-19 02:57'
updated_date: '2026-07-19 05:10'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-07-19 のアーキテクチャレビューで見つかった独立の小粒課題をまとめて解消する。

1. 死んだ注入: SessionRestorer は fileReader を注入・保持する（befold/App/SessionRestorer.swift:9,21,25）のに存在確認は FileManager.default 直呼び（:83）
2. fileExists + ディレクトリ判定の 4 重複: ViewerWindowController.swift:236-243 / :326、ViewerWindowManager.swift:54、SessionRestorer.swift:82-90（DirectoryLister.isDirectory とも同型）→ FileReading へ集約
3. JSONEncoder → JS リテラル化の 4 重複: BefoldKit/ViewerBridge.swift:55-56 / :116-121 / :139-144 / :195-200 → ヘルパー 1 個に畳む
4. 遅延 0.2 秒の二重定義: FileWatcher.swift:15 defaultDebounceDelay と :37 renameSettleDelay のハードコード
5. ブリッジ突合テストの穴: bannerStrings キー名（ViewerBridge.swift:134-138 ↔ viewer-main.js:852-865、タイポは英語文言に静かに縮退）、findStrings 8 キーの JS 側読取（viewer-main.js:508-518,647）、FileType.jsValue ↔ viewer-main.js render() 分岐名（:1020-1097）
6. SidebarNavigator.refreshFileList の静的 DirectoryLister.listEntries 直呼び（befold/App/SidebarNavigator.swift:72-76、再読込経路がテスト差し替え不能）
7. テストヘルパー重複: makeController 系ファクトリ 4 ファイル（ViewerWindowControllerTests.swift:56-69 ほか）、makeHomeTempDir 2 ファイル完全同一、symlink 判定テストのコピー（ZoomStoreTests.swift:84-98 / ScrollPositionStoreTests.swift:80-93）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SessionRestorer の存在確認が注入された fileReader 経由になっている
- [x] #2 ファイル存在＋ディレクトリ判定が 1 箇所に集約されている
- [x] #3 ViewerBridge の JSON→JS リテラル化がヘルパーに共通化されている
- [x] #4 bannerStrings / findStrings / FileType.jsValue の Swift↔JS 突合テストが追加されている
- [x] #5 テストヘルパーの同型重複が解消されている
- [x] #6 対応しない項目は見送り理由がノートに記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 死んだ注入(対応): SessionRestorer.restoreLastSession の FileManager.default 直呼びを注入済み fileReader 経由へ。
2. fileExists+ディレクトリ判定の集約(対応): FileReading に isDirectory(at:)/isExistingFile(at:) を追加し ObjCBool の重複を DefaultFileReader 1箇所へ。InMemoryFileReader も実装。DirectoryLister は DefaultFileReader へ委譲する薄い静的ファサードに。VWC(handleOpenReference/performFileSwitch)/VWM/SessionRestorer/DirectoryLister の重複を解消。
3. ViewerBridge の JSON→JS リテラル化(対応): [String:...] を JS オブジェクトリテラルへ畳むヘルパー jsObjectLiteral を1個追加し hostFeatures/bannerStrings/findStrings で共通化。
4. 遅延0.2秒の二重定義(対応): FileWatcher に defaultRenameSettleDelay 定数を追加しハードコード除去。
5. ブリッジ突合テスト(対応): bannerStrings(showing/loadMore/loadError)・findStrings(8キー)・FileType.jsValue↔render()分岐名 の Swift↔JS 突合テストを ViewerBridgeTests へ追加。
6. SidebarNavigator.refreshFileList(対応): directoryLister クロージャを SidebarNavigator へ注入し静的直呼びを差し替え可能に。VWC から既存の directoryLister を伝播。
7. テストヘルパー重複(部分対応): makeHomeTempDir(2ファイル同一)を TestSupport へ集約。symlink ペア生成を TestSupport のヘルパーへ集約。makeController 系ファクトリの統合は見送り(各 Suite が type_body_length 対策で意図的に分割され、UserDefaults 分離プレフィックスと注入ストアが異なるため、共有化するとローカル定義より不明瞭になる。重複は PerFileStateStore 構築の浅い重複に留まる)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。swift test 全 433 テスト成功。
- 項目1(死んだ注入): SessionRestorer.restoreLastSession が注入済み fileReader.isExistingFile 経由に。
- 項目2(存在+ディレクトリ判定集約): FileReading に isDirectory(at:)/isExistingFile(at:) を追加。ObjCBool の取り回しは DefaultFileReader.existence(of:) 1箇所へ集約。DirectoryLister は DefaultFileReader へ委譲する薄い静的ファサード化(isExistingFile/fileExists/isDirectory)。VWC(handleOpenReference→isExistingFile / performFileSwitch→fileExists)・VWM・SessionRestorer の重複を解消。InMemoryFileReader も対応。※FileWatcher:143 の fileExists は rename 追従判定の内部処理で対象クラスタ外のため据え置き。
- 項目3(JS リテラル化): ViewerBridge に jsonLiteral / assignGlobalScript を追加し hostFeatures/bannerStrings/findStrings/contentCallScript の 4 重複を共通化。
- 項目4(遅延0.2秒): FileWatcher.defaultRenameSettleDelay 定数を追加しハードコード除去。
- 項目5(ブリッジ突合テスト): bannerStrings 全キー・findStrings 8キーの JS 側 strings.<key> 読取、FileType.jsValue↔render() type 分岐 の突合テストを ViewerBridgeTests に追加(3件)。
- 項目6(SidebarNavigator 再読込): directoryLister クロージャを SidebarNavigator に注入し静的直呼びを差し替え可能に。VWC から伝播。
- 項目7(テストヘルパー重複): makeHomeTempDir(2ファイル同一)と symlink ペア生成を TestSupport へ集約。makeController 系ファクトリ統合は見送り(各 Suite が type_body_length 対策で意図的分割、UserDefaults 分離プレフィックス・注入ストアが異なり共有化するとローカル定義より不明瞭。重複は PerFileStateStore 構築の浅い重複に留まる)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
小粒の衛生課題を解消。FileReading に isDirectory/isExistingFile を追加し ObjCBool 判定を DefaultFileReader 1箇所へ集約(DirectoryLister は薄いファサード化)、SessionRestorer を注入 fileReader 経由に、ViewerBridge の JSON→JS リテラル化を jsonLiteral/assignGlobalScript へ共通化、FileWatcher の renameSettleDelay を定数化、SidebarNavigator の再読込に directoryLister を注入。bannerStrings/findStrings/FileType.jsValue の Swift↔JS 突合テスト3件と、テストヘルパー(makeHomeTempDir/symlink ペア)集約を追加。makeController 系ファクトリ統合は見送り(理由はノート)。swift test 全433テスト成功で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
