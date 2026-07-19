---
id: TASK-67
title: 小粒の衛生課題を解消する（死んだ注入・fileExists 重複・JS リテラル化・ブリッジ突合テストの穴）
status: To Do
assignee: []
created_date: '2026-07-19 02:57'
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
- [ ] #1 SessionRestorer の存在確認が注入された fileReader 経由になっている
- [ ] #2 ファイル存在＋ディレクトリ判定が 1 箇所に集約されている
- [ ] #3 ViewerBridge の JSON→JS リテラル化がヘルパーに共通化されている
- [ ] #4 bannerStrings / findStrings / FileType.jsValue の Swift↔JS 突合テストが追加されている
- [ ] #5 テストヘルパーの同型重複が解消されている
- [ ] #6 対応しない項目は見送り理由がノートに記録されている
<!-- AC:END -->
