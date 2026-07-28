---
id: TASK-179
title: サイドバーの相対パスコピーを git リポジトリでは git root 基準にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 08:13'
updated_date: '2026-07-28 10:56'
labels: []
dependencies: []
priority: high
ordinal: 254000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーのコンテキストメニュー「相対パスをコピー」は、現在そのウィンドウで開いた最上位ディレクトリーを基準に相対パスを算出している。Quick Open で導入した git リポジトリ判定を活用し、対象ファイルが git 管理下にある場合は git root からの相対パスをコピーするようにする。git リポジトリでない場合は従来どおり最上位ディレクトリー基準のままとする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 対象ファイルが git 管理下にある場合、コピーされる相対パスが git root からの相対パスになる
- [x] #2 対象ファイルが git 管理下にない場合、従来どおり最上位ディレクトリー基準の相対パスがコピーされる
- [x] #3 git root 判定・取得は Quick Open で導入済みの既存ロジックを再利用する
- [x] #4 相対パス算出ロジックにユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PathRelativizer に git root 優先のオーバーロード relativePath(of:workspaceRoot:gitRoot:) を追加（gitRoot があればそれ、なければ workspaceRoot を base にする純粋ロジック）
2. PathRelativizerTests に git root あり/なしのケースを追加（AC#4）
3. FileListView に resolveGitRoot: ((URL)->URL?)? クロージャを追加し copyPath を新オーバーロード経由にする
4. ViewerWindowController で resolveGitRoot に gitFileIndex.repositoryRoot(forFileAt:) を渡す（Quick Open と同一の索引を再利用、AC#3）
5. swift build / swift test
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PathRelativizer に relativePath(of:workspaceRoot:gitRoot:) を追加し gitRoot 優先 base 選択を純粋ロジック化。FileListView.copyPath に resolveGitRoot クロージャを注入し、ViewerWindowController から Quick Open と同一の gitFileIndex.repositoryRoot(forFileAt:) を渡す。swift build 成功、PathRelativizerTests 6件 pass（うち git root あり/なし 2件を追加）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー『相対パスをコピー』を git 管理下では git root 基準に変更。git root 解決は Quick Open と共有の GitCommandFileIndex を再利用し、非 git は従来のワークスペースルート基準を維持。純粋ロジックをユニットテストで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
