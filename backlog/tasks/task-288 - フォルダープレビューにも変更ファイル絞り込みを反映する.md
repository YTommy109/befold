---
id: TASK-288
title: フォルダープレビューにも変更ファイル絞り込みを反映する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 07:28'
updated_date: '2026-08-04 08:48'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 478000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。showChangedFilesOnly を読むのは FileListModel.visibleEntries だけで、フォルダープレビュー（ViewerContentView → FolderListingView）には sortOrder と showHiddenFiles しか渡っていない。そのため絞り込み ON でフォルダー行を選ぶと、サイドバーは変更ファイルだけ、隣のプレビュー面は未変更を含む全件、という 2 つの答えが 1 ウィンドウ内に並ぶ。

docs/superpowers/specs/2026-07-18-folder-preview-listing-design.md の『プレビュー一覧はサイドバーの表示設定に従う』という契約と矛盾する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 絞り込み ON のとき、フォルダープレビューの一覧もサイドバーと同じ内容になる
- [x] #2 フォルダープレビューが参照する表示設定の受け渡しが 1 箇所にまとまり、次に設定が増えたとき同じ漏れが起きない形になる
- [x] #3 サイドバーとプレビューの一致を検証するテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: プレビュー側に showChangedFilesOnly / gitStatus / filterText を個別に足すのではなく、絞り込み条件を 1 つの値型 FileListFilter に集約する。FileListModel.visibleEntries も FolderListingView もこの同じ値・同じ関数を適用する形にし、設定が増えても片側取り残しが起きない構造にする。
2. FileListFilter.apply(to:in:) は git 絞り込みを 'その状態が対象ディレクトリのものであるとき' に限定する（既存の activeGitChangeFilter の currentDirectory 固定判定を引数へ一般化）。選択中のサブフォルダーを提示している場合は状態が別ディレクトリのものなので自然に無効化される。
3. FileListModel: listFilter を追加し、visibleEntries / activeGitChangeFilter をその上に載せ替える（振る舞いは不変）。
4. FolderListingView: sortOrder/showHiddenFiles はディスク列挙のキーとして従来どおり、新たに filter を受け取り visibleEntries(from:) で適用する。空状態判定も絞り込み後の一覧で行う。
5. ViewerContentView: fileListModel.listFilter を渡す。
6. テスト: FolderListingView.visibleEntries(from:) がサイドバーの FileListModel.visibleEntries と一致することを検証するテストを追加。既存 FileListModelFilterTests が回帰していないことを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討結果: プレビュー側へ showChangedFilesOnly / gitStatus / filterText を個別に足す（引数が3つ増える）案は採らず、絞り込み条件を値型 FileListFilter に集約し、サイドバーとプレビューが同じ値を同じ関数(apply(to:in:))で適用する形にした。FileListModel.visibleEntries と activeGitChangeFilter はこの上に載せ替えただけで振る舞いは不変（既存 FileListModelFilterTests 14 件がそのまま通る）。

git 絞り込みの適用条件は、これまで currentDirectory 固定だった判定を『対象ディレクトリの状態であるとき』へ一般化した。選択中のサブフォルダーを提示している場合は状態が別ディレクトリのものになるため自然に無効化され、サブフォルダー配下の行が丸ごと消える事故が起きない（テストで確認）。

filterText はディレクトリを問わず適用する。spec の『プレビュー一覧はサイドバーの表示設定に従う』契約に合わせた統一で、サブフォルダーのプレビューでも名前フィルターが効く。

空状態表示（ContentUnavailableView）の判定も絞り込み後の一覧に変更した。絞り込みで全部消えたときに無言の空リストにならないようにするため。

検証: swift test 全 1071 件通過。追加した FolderListingViewFilterTests 4 件は、FolderListingView.visibleEntries(from:) の絞り込みを外すと該当 2 件が実際に落ちることを確認済み（['changed.md','clean.md'] != ['changed.md']）。swiftlint は変更ファイルで警告 0 件（全体 78 件、main ベースライン相当）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーとフォルダープレビューの絞り込みを共通の値型 FileListFilter に一本化した。FileListModel.listFilter が表示設定（filterText / showChangedFilesOnly 由来の gitStatus / 提示中の行）をまとめ、サイドバー(visibleEntries)もプレビュー(FolderListingView.visibleEntries(from:))も同じ値を同じ apply(to:in:) で適用する。git 絞り込みは対象ディレクトリの状態であるときだけ効くよう一般化したため、選択中サブフォルダーのプレビューでは自然に無効化される。空状態表示も絞り込み後の一覧で判定する。検証は swift test 全 1071 件通過と、絞り込みを外すと新規テスト 2 件が落ちることの確認。
<!-- SECTION:FINAL_SUMMARY:END -->
