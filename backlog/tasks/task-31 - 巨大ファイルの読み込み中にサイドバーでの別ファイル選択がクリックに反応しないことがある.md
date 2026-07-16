---
id: TASK-31
title: 巨大ファイルの読み込み中にサイドバーでの別ファイル選択がクリックに反応しないことがある
status: To Do
assignee: []
created_date: '2026-07-16 13:44'
labels: []
dependencies: []
type: bug
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
巨大ファイル(SJIS CSV等)を表示中にサイドバーで軽量な別ファイルをクリックしても、即座には表示が切り替わらないことがある。数回クリックすると開けることがあり、処理継続中でクリックが無視されているのか、クリックイベント自体が伝わっていないのか切り分けが必要。メインスレッド(MainActor)がブロックされていないか、サイドバーのクリックハンドラとViewerStore.openFileの間で入力が取りこぼされていないかを調査する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 巨大ファイル読み込み中にサイドバーの別ファイルをクリックした際の挙動(取りこぼし/キューイング/ブロッキング)の原因が特定されている
- [ ] #2 原因に応じた対処方針(クリックの取りこぼし防止、または処理中である旨の視覚的フィードバック)が決まっている
<!-- AC:END -->
