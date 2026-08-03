---
id: TASK-263
title: サイドバーのフォルダー行に配下の Git 変更を集約したバッジを表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-03 11:24'
updated_date: '2026-08-03 12:20'
labels: []
dependencies:
  - TASK-186
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
priority: medium
type: feature
ordinal: 455000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 Git ステータスのバッジはファイル行にのみ表示され、フォルダー行には何も出ない（FileListEntryRow の case .folder は右端が chevron.right 固定）。そのため折りたたまれたフォルダーの中に変更ファイルがあっても、フォルダーを開くまで気づけない。フォルダー配下（再帰的）に変更ファイルが 1 つ以上あるとき、そのフォルダー行にも変更ありを示すバッジを表示する。

前提となる事実（調査済み・2026-08-03）:
- GitStatusSnapshot.statuses はリポジトリルート単位で配下全ファイルの状態を保持しており、表示中ディレクトリに絞られていない。したがって集約に必要なデータは既に揃っている（追加の git 実行は不要）。パスキーの prefix 判定、または snapshot 構築時に祖先ディレクトリへの集約マップを作る形が候補。
- untracked は porcelain の既定でディレクトリ単位に畳まれる（? レコードが dir/ になる）。集約の際に -uall を付けるかどうかの判断が必要。
- 露出は ViewerWindowController.makeSidebarGitStatusLoader の FeatureGate 分岐 1 箇所に集約されている。本機能もその配下に入るため追加のゲートは不要（解除は TASK-187）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー配下（再帰的）に Git 変更のあるファイルが 1 つ以上あるとき、そのフォルダー行にバッジが表示される
- [x] #2 配下に変更が無いフォルダー、および非 Git・status 取得失敗時はフォルダー行にバッジが出ない
- [x] #3 フォルダー行のバッジはファイル行のバッジと視覚的に区別でき、混在する複数種類の変更（staged/unstaged/untracked/ブランチ内変更）を集約した表現になっている
- [x] #4 集約のために追加の git サブプロセス実行を行わない（既存スナップショットから算出する）
- [x] #5 untracked のディレクトリ畳み込みがあっても、その配下に未追跡ファイルを持つフォルダーがバッジ対象として扱われる
- [x] #6 集約写像が純関数として単体テストされ、階層をまたぐケース（孫階層のみ変更・親移動行）を含む
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitFolderStatus.swift(befold/App/)を追加: hasStaged/hasUnstaged/hasUntracked/hasBranchModified の 4 フラグ + 純関数 aggregate(statuses:) -> [String: GitFolderStatus]。各エントリを『自身のキー + 全祖先ディレクトリ』へ OR 集約する(自身のキーも入れることで、porcelain 既定で畳まれた未追跡ディレクトリ 'dir/' がフォルダー行に一致する)。追加の git 実行はしない。
2. GitStatusBadge に appearance(forFolder:) を追加。文字は '•'(ファイル行の A/M/D/? と視覚的に区別)、tint は staged>unstaged>untracked>branchModified の優先順、2 種以上混在時は既存の accent 円で次点を示す。descriptionKey は新規ローカライズキー。
3. FileListModel に gitFolderStatuses を追加。SidebarNavigator.refreshGitStatuses が statuses と同じ契機で集約結果を書き込む(世代ガードは既存のまま)。
4. FileListEntryRow の .folder 分岐に gitFolderStatus クロージャ(既定 nil)を足し、chevron の手前にバッジを描画。FileListView から注入。FolderListingView は無変更。
5. テスト: GitFolderStatusTests(孫階層のみ変更・親移動行・未追跡ディレクトリ畳み込み・混在)、GitStatusBadgeTests に folder 写像、SidebarNavigatorGitStatusTests に gitFolderStatuses 反映。
6. swift test / swiftlint ベースライン差分ゼロを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: GitFolderStatus(befold/App/)を追加。GitStatusSnapshot.statuses(リポジトリ全体・正規化絶対パスキー)を『自身のキー + 全祖先ディレクトリ』へ OR 集約する純関数 aggregate(statuses:) で写像し、git は追加実行しない。自身のキーも含めるのは、porcelain 既定(-unormal)が未追跡ディレクトリを 'dir/' の 1 エントリに畳むため(URL.normalizedPathKey が末尾スラッシュを落とすのでフォルダー行の pathKey と一致する)。-uall は付けていない。

表示: フォルダー行のバッジは '•'(ファイル行の A/M/D/? と区別)。主色は staged > unstaged > untracked > branchModified の優先順、2 種以上混在時は既存の accent(小さな丸)で次点を示す。chevron の手前に置いた。露出は既存 makeSidebarGitStatusLoader の FeatureGate 分岐配下のまま(追加ゲート無し)。

検証: swift test 1004 tests / 150 suites すべて green。xcodebuild build -scheme befold exit 0。swiftlint は origin/main を git archive で別ディレクトリへ展開して比較し、警告 77 件で新規違反ゼロ(既存の FileListView type_body_length の行数が 270→273 に増えたのみ)。表示は一時的な ImageRenderer ハーネスで FileListEntryRow を実描画して目視確認(混在フォルダー=橙+緑の 2 点、変更なしフォルダー=バッジ無し、ファイル行=橙の M)。ハーネスはコミット前に削除済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーのフォルダー行に、配下(再帰的)の Git 変更を集約したバッジを表示する。純関数 GitFolderStatus.aggregate が既存スナップショットから祖先ディレクトリへ集約するため git の追加実行は無し。単体テスト(集約 9 件・バッジ写像 5 件・SidebarNavigator 反映 1 件)と ImageRenderer による実描画の目視で確認し、全 1004 テスト green・swiftlint 新規違反ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
