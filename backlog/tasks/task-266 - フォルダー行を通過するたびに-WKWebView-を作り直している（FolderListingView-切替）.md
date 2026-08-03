---
id: TASK-266
title: フォルダー行を通過するたびに WKWebView を作り直している（FolderListingView 切替）
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-03 13:32'
updated_date: '2026-08-03 14:34'
labels:
  - performance
dependencies: []
priority: medium
ordinal: 457000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-265 の GUI 実測（sample 1ms）で判明した残コスト。サイドバーの選択が file 行と folder 行の間で切り替わるたび、ViewerContentView がプレビュー領域を差し替え、ViewerWebView.makeNSView が呼ばれて WKWebView を作り直している。backlog/ で tasks 行を 24 回往復した 4 秒のサンプルで、メインスレッドの 209 サンプルがここに出た（同サンプルの FileListEntryRow.body は 189）。

TASK-265（URL の正規化ハッシュ）とは別原因で、そちらの修正後も残る。フォルダー選択時に WKWebView を破棄せず保持したまま隠す等で避けられる見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォルダー行と file 行を往復しても WKWebView が作り直されない
- [ ] #2 同一手順の sample で ViewerWebView.makeNSView のメインスレッド占有が有意に減ることを実測で示す
<!-- AC:END -->
