---
id: TASK-285
title: 変更ファイル絞り込みの判定を git 状態の真実の源に合わせる
status: To Do
assignee: []
created_date: '2026-08-04 07:27'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 490000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)で確認された、TASK-264 の絞り込み判定に起因する不具合をまとめる。いずれも『行にキーがあるか』でメンバーシップを決めていることが根で、修正も同じ場所（FileListModel.visibleEntries / isGitChangeFilterEffective と、状態を配る SidebarNavigator）に集まる。

1. 未追跡ディレクトリの畳み込み: porcelain 既定(-unormal)は未追跡ディレクトリを 'dir/' 1 レコードに畳むため、新規フォルダー配下のファイルは gitStatuses にキーが無く、絞り込みで全部消える。1 階層上ではそのフォルダーに未追跡バッジが出ているため表示が自己矛盾する。TASK-263 の集約は祖先方向にしか広げていないので、ファイル側は祖先の畳み込みレコードに一致させる必要がある。
2. 綺麗なリポジトリでの誤縮退: isGitChangeFilterEffective は『非 git』と『変更が無い git リポジトリ』を区別できず、全部コミット済みのリポジトリではトグルが no-op になる。一方でメニューのチェックとヘッダーのアイコンは ON を示すため、機能が壊れて見える。判定はリポジトリを解決できたか（GitStatusResult.indexURL / ルートの有無）で行う。
3. 状態の遅延到着: performListing は一覧取得と refreshGitStatuses を別世代の非同期タスクで走らせるため、別リポジトリへ移動した直後は前のリポジトリの gitStatuses のまま新しい entries が適用され、一覧が一瞬 '..' だけになってから全件へ戻る。バッジだけなら誤描画で済んでいたが、絞り込みでは一覧そのものが消える。

前提となる事実: 2 と 3 は同じ『縮退の判定材料が statuses の中身になっている』ことが原因で、リポジトリ解決結果を持たせれば同時に解ける見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 未追跡ディレクトリ配下のファイルが、絞り込み ON でも一覧に残る（1 階層上のバッジと表示が矛盾しない）
- [ ] #2 変更が無い git リポジトリでトグル ON にしたとき、no-op ではなく意図した結果（変更ファイルが無いことが伝わる表示）になる
- [ ] #3 別リポジトリ・非 git フォルダーへ移動した直後に、古い git 状態で一覧が空にならない
- [ ] #4 縮退の判定がリポジトリを解決できたかどうかに基づき、statuses の中身に依存しない
- [ ] #5 上記 3 ケースが単体テストまたは実 git リポジトリの統合テストで再現・検証される
<!-- AC:END -->
