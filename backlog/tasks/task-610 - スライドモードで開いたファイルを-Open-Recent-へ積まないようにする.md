---
id: TASK-610
title: スライドモードで開いたファイルを Open Recent へ積まないようにする
status: To Do
assignee: []
created_date: '2026-09-11 07:29'
labels: []
dependencies: []
ordinal: 800000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライドモードは通常のドキュメントウィンドウと異なり、プレゼンテーション用途で一時的にファイルを表示するための機能。現状は通常ウィンドウと同じ経路（ViewerWindowManager+OpenViewer.swift の noteOpened / noteNewRecentDocumentURL 呼び出し、ViewerWindowSessionSync.swift のリネーム同期）でファイルを開くため、スライドモードで開いたファイルも RecentDocumentsStore と NSDocumentController の Open Recent メニューに積まれてしまう。スライドモードでの一時的な閲覧が、通常の『最近使ったファイル』の並びを汚す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 スライドモード（ViewerWindowKind.slide）でファイルを開いても RecentDocumentsStore に記録されない
- [ ] #2 スライドモードでファイルを開いても NSDocumentController.shared.noteNewRecentDocumentURL が呼ばれない（Open Recent メニューに現れない）
- [ ] #3 スライドモード中にファイルがリネームされた場合も Open Recent へ積まれない
- [ ] #4 通常のビューアウィンドウ（.viewer）で開いた場合の Open Recent への記録は従来どおり動作する
- [ ] #5 ユニットテストでスライドモード時に記録されないことを確認する
<!-- AC:END -->
