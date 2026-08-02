---
id: TASK-186.3
title: 'Phase3: merge-base 比較でブランチ内変更ファイルをバッジ表示する'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-28 14:23'
updated_date: '2026-08-02 09:57'
labels: []
dependencies:
  - TASK-186.1
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
parent_task_id: TASK-186
priority: medium
ordinal: 261800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
デフォルトブランチを自動検出（git symbolic-ref --short refs/remotes/origin/HEAD、無ければローカル既定 main/master）し、git merge-base HEAD <default> と git diff --name-status -z <mergeBase> HEAD で、現在ブランチでコミット済み・作業ツリークリーンな変更ファイル（branchModified）を青系バッジで表示する。検出不可時は branchModified のみ無効化し他状態は継続表示する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 現在ブランチが base から変更したコミット済みファイルに branchModified バッジが表示される
- [x] #2 worktree に変更のある staged/unstaged 状態が branchModified より優先/併記されて破綻しない
- [x] #3 デフォルトブランチ検出不可時は branchModified のみ無効化され、staged/unstaged/untracked は表示される（ユニットテスト）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装・検証記録(2026-08-02):

- GitStatusReader.status() の中で、porcelain のマージ後に branchModified を重ねる形にした（Store / SidebarNavigator / 表示層は無変更で済む）。
- デフォルトブランチ検出順: origin/HEAD → ローカル main → ローカル master。検出不可なら branchModified だけ無効化し、staged/unstaged/untracked は継続表示（実 git の統合テストで固定）。
- バッジ優先度は既存の写像どおり untracked > staged > unstaged > branchModified。worktree に変更のあるファイルは橙のまま（青に埋もれない）で、状態としては両方立つ。
- 追加コスト: status 1 回につき最大 3 プロセス（symbolic-ref/rev-parse・merge-base・diff）。契機がイベント駆動で in-flight も畳まれるため許容と判断。
- 検証: swift test 990 件パス（name-status パーサ3本、実 git 統合3本）。GUI は feat/git_status ブランチで Debug ビルドを起動し、このブランチでコミット済み・作業ツリーがクリーンなファイル（AppDelegate.swift 等）に青 M、未コミット変更のあるファイル（GitStatusReader.swift）に橙 M が出ることをスクリーンショットで確認。
- swiftformat 0 件 / swiftlint ベースライン差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
デフォルトブランチ（origin/HEAD → main → master）を検出し、merge-base + diff --name-status -z で「このブランチでコミット済み・作業ツリーはクリーン」なファイルに青の M バッジを出すようにした。検出不可時は branchModified のみ無効化して他の状態表示は継続する。name-status パーサのユニットテストと実 git の統合テスト（ブランチ内変更の検出／worktree 変更との両立／検出不可時の縮退）を追加し swift test 990 件パス、実ビルドで青 M と橙 M の出し分けを目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
