---
id: TASK-476
title: サイドバーの基準ディレクトリ行を worktree 切替プルダウンにする
status: To Do
assignee: []
created_date: '2026-08-13 12:02'
labels: []
dependencies:
  - TASK-475
priority: medium
type: feature
ordinal: 697000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーヘッダー最上部の基準ディレクトリ行（`BaseDirectoryIndicator`）を、git リポジトリかつ worktree が 2 件以上ある場合に限りプルダウンにし、選んだ worktree へ **今のウィンドウのまま** 移動できるようにする。git でない場合、および worktree が本体 1 件のみの場合は現状どおりテキスト表示（`RecentRepositoriesMenuController` の縮退と同じ考え方）。

切替時の挙動: 現在フォルダーと現在ファイルの、本体ルートからの相対パスを切替先へ写す。切替先に同じ相対パスのファイルがあればそのファイルを開く。無ければフォルダーのみ移動する。フォルダーも無ければ切替先ルートへ着地する。

## 既存資産（新規実装は不要）
- git 呼び出し: `GitRepository.worktrees(forRoot:)`（`git_worktree_list` ベース。`GitWorktree` は root / isMain / branch / displayName）
- キャッシュ: `WorktreeCatalog.swift:15`（本体ルート → worktree 配列。detached で `refresh(mainRoots:)`、UI 側は同期読みのみ）

## 設計上の注意
1. **既存の worktree 切替 UI と意味が違う**。`RecentRepositoriesMenuController` の worktree サブメニューは `SessionRestorer.openRepository(root:savedTabGroup:)` を通り「そのルートを新しいウィンドウ／タブグループで開き直す」。本タスクは「今のウィンドウのまま横移動する」。**共存させる**方針とし、それぞれの help / タイトルで違いが分かるようにする。
2. **`BaseDirectoryDescriptor` は従属値であり、切り替えられる状態ではない**。`SidebarBaseDirectoryResolver.swift:50` が `currentDirectory` の git ルート解決結果として毎回作り直す。基準を保持する新しい状態を作らないこと（真実の源が二重化する）。実体は `currentDirectory` と現在ファイルの移動であり、見出しがそこに乗るだけ。
3. **横移動を既存経路が想定していない**。`SidebarNavigator.moveCurrentDirectory(to:)`（`SidebarNavigator+FolderNavigation.swift:46`）は上下移動前提で、上へ移動したときだけ `rootDirectory` を引き上げる。worktree 切替は兄弟ツリーへの横移動なので `rootDirectory` を切替先ルートへ張り替える必要がある。
4. **ホーム外の worktree はメニューに出さない**。`navigateToFolder` のホーム配下チェックで移動できないため、出して失敗させるより現状の制約と一貫させる。
5. **消えた worktree（prunable）を出さない**。`git worktree list` はディレクトリが実在しない登録も返す。
6. **確定前はテキストのまま**。現在フォルダーがどの本体ルートに属するかの解決は detached。`BaseDirectoryIndicator` は既に「解決前は行を出さない」設計なので、同じ扱い（確定後にメニュー化）にする。
7. **TASK-475 と同じヘッダーを触る**。475 で直下のフォルダー名行がパスポップアップになるため、押下可能を示す指示子とホバーの反応を両行で揃える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 git リポジトリで worktree が 2 件以上あるとき、基準ディレクトリ行がプルダウンになり、本体を含む全 worktree が選べる
- [ ] #2 git でない場合、および worktree が本体 1 件のみの場合は現状どおりのテキスト表示になる
- [ ] #3 worktree を選ぶと、同じウィンドウのまま切替先の同じ相対パスのファイルが開く
- [ ] #4 切替先に同じ相対パスのファイルが無い場合は、対応するフォルダーへ移動するだけで本文は切り替わらない
- [ ] #5 切替先に対応するフォルダーも無い場合は、切替先ルートへ着地する
- [ ] #6 切替後、rootDirectory・サイドバー一覧・git ステータス・ウィンドウの所属リポジトリが切替先のものになっている
- [ ] #7 ホーム外にある worktree、および実在しない（prunable な）worktree はメニューに現れない
- [ ] #8 本体ルートの解決が終わるまでは従来のテキスト表示で、確定後にプルダウンへ変わる（解決前に空メニューが出ない）
- [ ] #9 既存の「最近使ったリポジトリ」の worktree サブメニュー（新しいウィンドウで開き直す）は従来どおり動作し、本機能との違いが help から分かる
- [ ] #10 相対パスの写し替え（ファイルあり / ファイル無し / フォルダーも無し / ホーム外 / prunable）は引数で入力を受け取る純粋関数へ切り出し、各ケースをユニットテストで押さえる
- [ ] #11 切替が履歴に記録され、戻る操作で切替前の worktree のファイルへ戻れる
- [ ] #12 実装着手前に `/review-design` を 1 回実施し、結果を Implementation Plan へ反映している
<!-- AC:END -->
