---
id: TASK-231
title: CLIOpenOptions のフィールド単位受け渡しを一括受け渡しに集約する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:15'
updated_date: '2026-07-31 22:23'
labels:
  - refactor
dependencies: []
priority: medium
type: task
ordinal: 380000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIOpenOptions の展開が AppDelegate.swift:230-238 / :275-281、SessionRestorer.swift:180-187 の 3 箇所でフィールド単位に手写しされ、ViewerWindowManager.swift:140-155 の受け側でも optional を個別展開している。フィールド追加時に 4 箇所の修正が必要で、忘れると「セッション復元経路だけ新オプションが効かない」という気付きにくい欠落になる。ViewerWindowManager の API を CLIOpenOptions 受け（openViewer(for:options:) / applyDisplayOverrides(_:)）に寄せ、options.sortOrder.map { _ in options.viewerSortOrder } という不自然な変換も解消する。オプションなし呼び出し向けに既定引数を用意する。既存の ViewerWindowManagerDisplayOverridesTests 等のシグネチャ変更に注意。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLIOpenOptions のフィールド追加時に転送コードの修正箇所が 1 箇所になっている
- [x] #2 CLI オープン・セッション復元・通常オープンの各経路でオプション適用が従来どおり動作しテストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerWindowManager.openViewer の 4 つのオーバーライド引数を options: CLIOpenOptions に置換
2. applyDisplayOverrides も CLIOpenOptions 受けにし、sortOrder.map { _ in viewerSortOrder } の不自然な変換を撤去
3. AppDelegate / SessionRestorer の展開を options のそのまま渡しへ集約
4. シグネチャ変更に追随してテストを更新し、復元経路の並び順転送を固定するテストを追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerWindowManager の API を CLIOpenOptions 受け(openViewer(for:options:disposition:relativeTo:forceSidebarVisible:) / applyDisplayOverrides(_:))へ寄せ、AppDelegate 2 箇所・SessionRestorer 1 箇所のフィールド単位の手写しを撤去した。CLIOpenOptions のフィールドを読む箇所は ViewerWindowManager の適用側 2 メソッド（新規ウィンドウ生成と既存ウィンドウ一括適用）に集約され、転送コードは 0 になった。showHiddenFiles だけはウィンドウ単位ではなくアプリ全体設定のため、従来どおり AppDelegate / SessionRestorer の入口で扱う（別経路のまま）。sortOrder.map { _ in options.viewerSortOrder } は『指定があったときだけ viewerSortOrder を適用する』という素直な形へ置換。オプションなし呼び出し向けに options に既定引数を用意したため、既存の openViewer(for:) 系呼び出し 40 箇所超は無変更。検証: swift test --skip Integration --skip FileWatcherTests → 939 passed（復元経路で --sort alphabetical が効くことを固定するテストを追加）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIOpenOptions のフィールド単位の受け渡しを ViewerWindowManager への一括受け渡しへ集約し、AppDelegate / SessionRestorer の手写し 3 箇所を撤去した。sortOrder の不自然な変換も解消。swift test 939 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
