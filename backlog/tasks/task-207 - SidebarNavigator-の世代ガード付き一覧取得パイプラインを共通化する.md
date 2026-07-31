---
id: TASK-207
title: SidebarNavigator の世代ガード付き一覧取得パイプラインを共通化する
status: To Do
assignee: []
created_date: '2026-07-31 02:52'
labels:
  - refactoring
dependencies: []
references:
  - BefoldApp/befold/App/SidebarNavigator.swift
priority: medium
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
refreshFileList(SidebarNavigator.swift:117-145)と navigateToFolder(同 192-217)が「refreshBaseDirectory → syncShowHiddenFiles → sortOrder 取得 → listingGeneration += 1 → Task { entries 取得; 世代・host guard; 反映 }」という同一パイプラインを二重に持つ。違いはディレクトリの確定方法と完了後の選択ロジックのみ。世代ガード・host guard という競合安全性の要が 2 箇所に散っており、guard の書き方が既に揺れ始めている(let host = self.host と self.host != nil)。ディレクトリを引数で受ける performListing(of:onApplied:) の形に抽出すれば順序は不変。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 世代ガード付きの一覧取得が単一のヘルパーに統合され、refreshFileList と navigateToFolder がそれを使う
- [ ] #2 一覧更新の競合時(連続操作・フォルダ移動中の再読み込み)の挙動が現状と変わらない(既存テストが通る)
<!-- AC:END -->
