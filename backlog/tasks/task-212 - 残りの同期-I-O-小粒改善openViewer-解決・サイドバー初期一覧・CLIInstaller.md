---
id: TASK-212
title: 残りの同期 I/O 小粒改善(openViewer 解決・サイドバー初期一覧・CLIInstaller)
status: In Progress
assignee:
  - '@claude'
created_date: '2026-07-31 02:57'
updated_date: '2026-07-31 07:33'
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
- [ ] #1 openViewer のフォルダ解決がメインスレッドをブロックしない、または現状維持の判断理由がノートに記録される
- [ ] #2 サイドバー初期一覧の同期取得経路が削除される、または現状維持の判断理由がノートに記録される
- [ ] #3 CLI インストールの管理者認証待ちがメインスレッドをブロックしない
- [ ] #4 既存テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstaller: AppDelegate.installCLI で install() を Task.detached へ逃がし、結果ダイアログのみ MainActor で出す(NSAppleScript は detached 側で生成・実行し単一スレッド利用を保つ)
2. openViewer: isDirectory + resolveFileToOpen を Task.detached へ。複数パスの起動順を崩さないよう async 版 openViewer を用意し、openPaths / application(_:open:) は 1 本の Task 内で逐次 await する
3. サイドバー初期一覧: ViewerWindowController.init の同期 directoryLister 呼び出しを廃止し、空一覧で生成 → attach 後に sidebar.refreshFileList()(既存の非同期経路)で埋める。ViewerWindowManager / VWC の directoryLister 注入シームと関連テスト引数を削除
4. swift build / swift test / swiftformat --lint
<!-- SECTION:PLAN:END -->
