---
id: TASK-536.4
title: Bookmark をフォルダー風の階層で整理できるようにする
status: To Do
assignee: []
created_date: '2026-08-21 07:28'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 780000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の BookmarkStore はフラットな [String]（UserDefaults キー "BookmarkedPaths"）のみを保持し、グループ化やフォルダの概念が無い（実測: BookmarkStore.swift:8-59、PathListDefaults.swift）。近い概念としてサイドバーのファイルツリー（DirectoryListing.swift:9-59／SidebarRowBuilder／SidebarTreePresenter.swift）が階層表示・展開状態分離のパターンを持つが、これはファイルシステムのディレクトリ構造をそのまま反映するものであり、ブックマーク側は「ファイルシステムとは独立したユーザー定義の仮想フォルダ」を新設する必要がある（既存パターンをそのまま流用できない）。

ブックマークをユーザーが任意に作成した「フォルダー」にグルーピングし、階層的に整理できるようにする。

永続化フォーマットをフラットな配列から階層構造へ変更するため、CLAUDE.md の「UserDefaults キーの廃止・改名」節に準じ、既存のフラットな "BookmarkedPaths" からの移行（旧データの意味を保った変換・移行後の旧キー削除・(a)旧データあり (b)旧データなし (c)移行済みの3ケースのユニットテスト）を設計に含めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ユーザーは任意の名前のフォルダーを作成できる
- [ ] #2 ブックマークを任意のフォルダーに所属させられる（フォルダーの入れ子も可能）
- [ ] #3 フォルダーの一覧・展開状態・所属関係は永続化される
- [ ] #4 フォルダーを削除しても配下のブックマークは失われない（ルートへ戻す、または削除確認を挟む）
- [ ] #5 既存のフラットなブックマークデータからの移行が行われ、参照先パスが失われない
- [ ] #6 移行の3ケース（旧データあり／旧データなし／移行済み）がユニットテストで担保される
<!-- AC:END -->
