---
id: TASK-620
title: Bookmark Editor の使い勝手を改善する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 11:41'
updated_date: '2026-09-13 15:10'
labels: []
milestone: m-9
dependencies: []
documentation:
  - docs/superpowers/specs/2026-09-12-bookmark-management-design.md
  - docs/dev/native-app-design.md
priority: medium
type: feature
ordinal: 810000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-536 で新設した Bookmark Editor（Bookmarks > ブックマークを編集…、`BookmarkManagerView`）を実際に使ったところ、次の 5 点で使いにくいことが分かった。

1. 行の左のアイコンが全行同じ SF Symbol の `bookmark` で、情報を持っていない（サイドバーはファイル種別のアイコンを出している）
2. 行の操作（別名・フォルダーへ移動・削除など）が右クリックの `contextMenu` にしか無く、存在に気づけない
3. 並び順は常に名前順で、フォルダーへの格納も右クリック > フォルダーへ移動 からしかできない
4. Bookmark Editor を開くキーボードショートカットが無い（TASK-536.1 で「キー等価は付けない」と判断していた）
5. 別名を付ける操作が「名前を変更…」/「Rename…」と表示され、ファイル自体の改名と誤解される。しかも別名を付けると行からファイル名が消えるため、何のファイルのブックマークか分からなくなる

各項目をサブタスクに分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 5 つのサブタスクがすべて完了している
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
5 つのサブタスクをすべて完了した: 620.4 cmd+shift+D で Bookmark Editor を開閉 (#662) / 620.5 別名操作の文言と別名付き行のファイル名表示 (#663) / 620.1 ファイル種別アイコンと表示で stat しない形への修正 (#664) / 620.2 行の ⋯ ボタン (#665) / 620.3 Bookmark Editor 内の D&D による並び替えとフォルダーへの格納。
<!-- SECTION:FINAL_SUMMARY:END -->
