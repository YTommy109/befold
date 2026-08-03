---
id: TASK-275
title: '段1: 提示状態を 1 つの値にする（ViewerSession）'
status: To Do
assignee: []
created_date: '2026-08-03 15:35'
labels:
  - architecture
dependencies: []
priority: high
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0002（docs/adr/0002-presentation-state-and-capabilities.md）の段 1。

「いま何を提示しているか」の真実の源が 5 箇所（ViewerStore.currentURL / ViewerStore.filePath / FileListModel.selection / window.representedURL / PreviewTargetResolver の導出結果）に分散しており、食い違う瞬間がある。これを 1 つの enum に集約し、他はその投影にする。

## 型に無い状態が実害を出している
PreviewTargetResolver.resolve は選択が一覧に無いとき .folder(currentDirectory) を返す（PreviewTargetResolver.swift:25-28）。ウィンドウ生成直後は entries が空（ViewerWindowController.swift:190-192）なので、一覧が届くまで「フォルダーを提示している」と判定される。TASK-266 で入れた isPreviewingFolder はこれを見るため、**起動直後は印刷・検索・ズームがメニュー上で無効**になる。ネットワークボリューム上では体感できる長さ。

原因は「まだ分からない（一覧取得前）」と「フォルダーを選んでいる」が同じ値に潰れていること。前者を独立した case として持たせる。

## 注意
選択が nil のとき現在ディレクトリの一覧を出すのは**意図された挙動**（SidebarNavigator が navigateToFolder で selection = nil にする）。「一覧取得前」と「意図的な nil」を取り違えないこと。

## 後続
段 2 = TASK-271、段 3 = TASK-270、段 4 = TASK-273 の一部、段 5 = TASK-272。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「一覧取得前」が提示状態の値として表現され、起動直後に印刷・検索・ズームが誤って無効化されない
- [ ] #2 選択 nil による意図的なフォルダー表示と、一覧未取得が型で区別されている
- [ ] #3 ViewerContentView と ViewerWindowController が同じ提示状態の値を見る（同じ導出を別々に呼ばない）
- [ ] #4 起動直後・フォルダー選択中・ファイル切替中それぞれの状態遷移を検証するテストがある
<!-- AC:END -->
