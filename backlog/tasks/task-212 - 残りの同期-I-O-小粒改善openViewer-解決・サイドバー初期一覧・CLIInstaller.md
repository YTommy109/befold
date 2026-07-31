---
id: TASK-212
title: 残りの同期 I/O 小粒改善(openViewer 解決・サイドバー初期一覧・CLIInstaller)
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 02:57'
updated_date: '2026-07-31 07:42'
labels:
  - refactoring
  - performance
dependencies: []
references:
  - BefoldApp/befold/App/AppDelegate.swift
  - BefoldApp/befold/App/ViewerWindowController.swift
  - BefoldApp/BefoldCLI/CLIInstaller.swift
priority: low
ordinal: 292000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビュー(2026-07-31)で挙がった、頻度・コストが低めの同期 I/O の改善候補 3 件。(1) openViewer のフォルダ解決(AppDelegate.swift:246-247、同型が SessionRestorer.swift:108-110): DirectoryLister.isDirectory + resolveFileToOpen が @MainActor で同期実行され、ネットワークボリューム上のフォルダを開くと orderFront 前に停止する。冒頭の解決部だけ Task.detached へ。(2) ウィンドウ生成時のサイドバー初期一覧(ViewerWindowController.swift:153): 空一覧でウィンドウを出し既存の非同期 refreshFileList() に埋めさせれば、同期経路と init の directoryLister 注入シームごと削除できる可能性がある(単純化を兼ねる)。(3) CLIInstaller.install(CLIInstaller.swift:81-90): 管理者認証の NSAppleScript.executeAndReturnError がパスワード入力完了まで main を同期ブロックし、その間 CLI 転送の ACK も止まる。Task.detached で実行し結果ダイアログだけ MainActor へ。それぞれ独立に適用可能で、体感問題が出ていなければ優先度は低い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 openViewer のフォルダ解決がメインスレッドをブロックしない、または現状維持の判断理由がノートに記録される
- [x] #2 サイドバー初期一覧の同期取得経路が削除される、または現状維持の判断理由がノートに記録される
- [x] #3 CLI インストールの管理者認証待ちがメインスレッドをブロックしない
- [x] #4 既存テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstaller: AppDelegate.installCLI で install() を Task.detached へ逃がし、結果ダイアログのみ MainActor で出す(NSAppleScript は detached 側で生成・実行し単一スレッド利用を保つ)
2. openViewer: isDirectory + resolveFileToOpen を Task.detached へ。複数パスの起動順を崩さないよう async 版 openViewer を用意し、openPaths / application(_:open:) は 1 本の Task 内で逐次 await する
3. サイドバー初期一覧: ViewerWindowController.init の同期 directoryLister 呼び出しを廃止し、空一覧で生成 → attach 後に sidebar.refreshFileList()(既存の非同期経路)で埋める。ViewerWindowManager / VWC の directoryLister 注入シームと関連テスト引数を削除
4. swift build / swift test / swiftformat --lint
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
(1) AppDelegate.openViewer(for:options:) を async 化し、DirectoryLister.isDirectory / resolveFileToOpen を Task.detached で解決。解決待ちで起動順が崩れないよう、openPaths と application(_:open:) は 1 本の Task 内で逐次 await する。非 async の openViewer(for:) は Task 起動のラッパとして維持。
(2) ViewerWindowController.init のサイドバー同期列挙を廃止。空一覧で SidebarNavigator を生成し、sidebar.attach 直後に既存の非同期 refreshFileList() で埋める。あわせて ViewerWindowController / ViewerWindowManager の directoryLister 注入シーム(および各テストの noEntries 注入)を削除し、一覧取得口を SidebarNavigator の非同期版 1 本に統一。
(3) AppDelegate.installCLI が CLIInstaller.install を Task.detached で実行し、結果ダイアログのみ MainActor(presentInstallResult)で出す。NSAppleScript の生成・実行は同じ detached タスク内で完結するため単一スレッド利用の前提は保たれる。

対象外とした同型箇所: SessionRestorer.openRootFallback の resolveFileToOpen。restoreLastSession は NSWindow.allowsAutomaticWindowTabbing を defer で戻す同期スコープ内でウィンドウ構成を再現しており、ここだけ非同期にすると復元中のタブ結合抑止スコープを跨いでしまうため据え置いた。

テスト修正: 初期一覧が非同期になったため、ViewerWindowControllerIntegrationTests の隠しファイル 2 件は pendingListingTask を await する形に変更(false pass 防止に visible.mmd の存在確認も追加)。--sort のテストは廃止したシームでなく fileListModel.sortOrder で検証する形に変更。

検証: swift build 成功、swift test 905 tests / 125 suites 全通過、swiftformat --lint 指摘なし。GUI 上のサイドバー初期表示(空→即埋め)の体感確認は次回 dev ビルドの dogfood 対象。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
同期 I/O 3 件をメインアクター外へ逃がした。(1) openViewer のフォルダ解決を Task.detached 化(複数パスの起動順は 1 本の Task での逐次 await で維持)、(2) サイドバー初期一覧の同期取得経路と directoryLister 注入シームを削除し、非同期 refreshFileList() 1 本に統一、(3) CLI インストールの管理者認証待ちを detached 実行にして結果案内のみ MainActor へ。SessionRestorer.openRootFallback はタブ結合抑止スコープを跨ぐため据え置き(理由をノートに記録)。swift test 905 件全通過・swiftformat --lint 指摘なしで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
