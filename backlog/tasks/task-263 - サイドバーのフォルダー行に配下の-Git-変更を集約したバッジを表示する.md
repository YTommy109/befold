---
id: TASK-263
title: サイドバーのフォルダー行に配下の Git 変更を集約したバッジを表示する
status: To Do
assignee: []
created_date: '2026-08-03 11:24'
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
- [ ] #1 フォルダー配下（再帰的）に Git 変更のあるファイルが 1 つ以上あるとき、そのフォルダー行にバッジが表示される
- [ ] #2 配下に変更が無いフォルダー、および非 Git・status 取得失敗時はフォルダー行にバッジが出ない
- [ ] #3 フォルダー行のバッジはファイル行のバッジと視覚的に区別でき、混在する複数種類の変更（staged/unstaged/untracked/ブランチ内変更）を集約した表現になっている
- [ ] #4 集約のために追加の git サブプロセス実行を行わない（既存スナップショットから算出する）
- [ ] #5 untracked のディレクトリ畳み込みがあっても、その配下に未追跡ファイルを持つフォルダーがバッジ対象として扱われる
- [ ] #6 集約写像が純関数として単体テストされ、階層をまたぐケース（孫階層のみ変更・親移動行）を含む
<!-- AC:END -->
