---
id: TASK-361.2
title: サイドバーの git ステータスを複数ディレクトリ対応にする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 01:57'
updated_date: '2026-08-10 02:45'
labels: []
dependencies:
  - TASK-361.1
parent_task_id: TASK-361
priority: medium
type: task
ordinal: 656000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの git ステータスを、単一ディレクトリぶんから**複数ディレクトリぶん**へ拡張する。TASK-361 の動機（コードレビュー中に複数フォルダへ散らばった変更ファイルを行き来する）に直接効く部分であり、行モデルを一本化しても残る本質的な設計変更。

## 現状（実測 2026-08-10、HEAD a3202d4）

- App/SidebarGitStatus.swift:16 が `let directoryKey` を 1 つだけ持つ（1 ディレクトリぶんのスナップショット）
- Viewer/FileListFilter.swift:47 gitChangeFilter(for:) が `gitStatus.directoryKey == directory.normalizedPathKey` で不一致なら nil を返す
- Viewer/FileListModel.swift:193 / :214 も entriesDirectory.normalizedPathKey と突き合わせる

複数階層を同時表示すると、1 つの directoryKey では表示中の行に対応付けできない。

## 方針

- SidebarGitStatus を「directoryKey → ステータス」の対応（辞書等）へ拡張するか、行の pathKey で直接引ける形へ変える。どちらにするかは /review-design で決める
- 「変更されたファイルのみ表示」（App/SidebarDisplayPreference.swift:23 showChangedFilesOnly）が、表示中のすべての階層に対して効くようにする
- バッジ表示（GitStatusBadge 系）も同様に、行ごとの pathKey で解決する

## 制約

- FeatureGate 配下（サイドバー git ステータスは TASK-187 でまだ stable 未昇格）に触れるため、コミット件名に (gate) スコープを付けるか判断すること。判断基準は FeatureGate.swift の Bool を経由してのみ有効化されるか
- 着手前に /review-design を 1 回回すこと
- 既存テスト SidebarGitStatusTests(5) / SidebarNavigatorGitStatusTests(9) / SidebarChangedFilesOnlyIntegrationTests(4) を壊さないこと
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git ステータスが複数ディレクトリぶん保持でき、表示中のどの階層の行でもバッジが正しく解決される
- [x] #2 「変更されたファイルのみ表示」が、表示中のすべての階層に対して効く
- [x] #3 単一ディレクトリ（ドリルダウン）時の既存の振る舞いと既存テストが壊れていない
- [x] #4 対応付けが単一 directoryKey へ戻ったら落ちるテストがある
- [x] #5 FolderListingSource（FolderListingView.swift:7-12）の Equatable 比較に depth 混在の一覧が載っても、FolderListingViewFilterTests.swift:134 型のテストが depth 差だけで落ちない（TASK-361.1 で FileListEntry の == から depth を外した前提が維持されている）
- [x] #6 listingSource の .shared(visibleEntries)（FileListModel.swift:300-309）が depth 混在の行配列を渡す場合の扱いが決まっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果を反映した実装方針（2026-08-10）

### 単純化の検討 → Description の方針（辞書化）を採らない

実測: GitStatusReader.status(forRepositoryAt:) は **リポジトリルート単位**で取得し、
キーは root.appendingPathComponent(相対パス).normalizedPathKey =
**絶対パスの正規化キー**（GitStatusReader.swift:64-73）。したがって
SidebarGitStatus.files / .folders は **既にリポジトリ全体ぶん**を持っており、
どの階層の行でも pathKey で直接引ける。バッジ描画も既に行ごとの pathKey 解決
（FileListView.swift:166-167）でディレクトリ一致を経由していない。

複数階層を妨げていたのは FileListFilter.gitChangeFilter(for:) の等値ガード
**1 箇所だけ**。辞書化すると 1 スナップショットをディレクトリ単位へ切り分けて
持ち直すことになり、状態と「どのディレクトリぶんが揃っているか」という新しい
不変条件が増える。**採らない。**

### 実装

1. SidebarGitStatus: directoryKey（取得したディレクトリ）→ **repositoryRootKey**
   （リポジトリルート）へ置き換え、covers(_:) を追加。比較は
   DirectoryLister.isWithinHome と同じ「等値または rootKey + / の前方一致」。
2. FileListFilter.gitChangeFilter(for:): 等値 → covers(_:) の包含判定へ。
3. init?(directory:result:) → **init?(result:)**（未使用の directory を落とす）。
   残すと「このディレクトリ用の状態」という読み方が残り、等値ガードを復活させる
   余地になる。対付けが要るのは applyGitStatus の側だけ、と引数の有無で構造的に分ける。
4. 空状態の文言を **SidebarEmptyState** へ共有化。包含化でプレビュー側も git 絞り込みで
   空になれるようになるため、サイドバーだけが理由で出し分ける状態を放置すると
   TASK-287 と同型の誤誘導が復活し、かつ TASK-320 型の片側取り残しになる。
5. listingSource の .shared は **depth 0 の行だけ**を渡す（AC #6）。プレビューが
   見せるのは directory 直下であって、サイドバーで展開したその配下ではない。

### 変えないもの

FileListModel.applyGitStatus / PendingGitStatus の**ディレクトリ対付けは等値のまま**。
ここが見ているのは「この状態はどの一覧の取得と対か」という到着順の整合であって、
「どの行に適用できるか」ではない。緩めると TASK-293 の回帰になる。

### レビューで判明した既存テストの意味変更

FolderListingViewFilterTests の
「選択中のサブフォルダーを提示しているときは、別ディレクトリの git 絞り込みが効かない」は
**期待値ごと書き換える**。包含化により同じリポジトリ内なら絞り込みが効くのが正しい
（サイドバーとプレビューで答えを 1 つにする TASK-288 の方針）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-10）

### 起票時の前提が誤りだった

Description の「SidebarGitStatus.swift:16 が directoryKey を 1 つだけ持つ（1 ディレクトリぶんの
スナップショット）」は誤り。**statuses は元からリポジトリ全体ぶん**（GitStatusReader.swift:64-73）で、
directoryKey は取得元を記録していただけ。辞書化は不要だった。

### /review-design の指摘への対応

- 指摘 D（最重要・実測）: FolderListingViewFilterTests の
  「サブフォルダーには別ディレクトリの絞り込みが効かない」テストが**必ず落ちる**と予告され、
  実際に落ちた。「効かせる」方を選び（TASK-288 の方針と一致）、期待値・テスト名ごと書き換えた
- 指摘 C: プレビュー側の空状態が「対応ファイルがありません」固定だった。両者に書き分けると
  TASK-320 型の取り残しになるため、SidebarEmptyState へ**共有化**して 1 実装にした
- 指摘 B: init?(directory:result:) の未使用引数を落として init?(result:) にした
- 指摘 E: 「包含（適用範囲）」と「等値（到着順の対付け）」の 2 つの粒度に、
  緩めたら落ちるテストを付けた（同じリポジトリ内でも一覧より先に届いた状態は保留される）
- 指摘 A: ネストしたリポジトリ・サブモジュールでは親リポジトリの status では
  正しく答えられないことが実測で判明。**TASK-403 として起票**し、361.2 では
  限界を repositoryRootKey の doc に明記するに留めた（選択肢 1）

### 検証（実測 2026-08-10）

- swift test --skip Integration --skip FileWatcherTests: **1168 tests / 164 suites 全通過**（変更前 1162）
- swiftformat --lint: 全ターゲット 0 件
- swiftlint: origin/main とのベースライン差分は
  **FileListView.swift の type_body_length が 312 行 → 300 行へ減った 1 行のみ**（新規違反ゼロ）。
  途中 FolderListingViewFilterTests が line_length と type_body_length(263) で 2 件出たため、
  新規テストを FolderListingViewRepositoryScopeTests へ分離した
  （DirectoryListerAppendingOpenFileTests と同じ前例）
- xcodegen generate 実行済み / xcodebuild build -scheme befold: exit=0
- FeatureGate.isSidebarGitStatusEnabled（FeatureGate.swift:58）経由の機能であることを確認し、
  コミット件名に (gate) スコープを付けた
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git ステータスの適用範囲を「取得したディレクトリとの等値」から「リポジトリルート配下かどうか」（SidebarGitStatus.covers）へ変えた。statuses は元からリポジトリ全体ぶんの絶対パスキーだったため、辞書化せずガード 1 箇所の変更で複数階層に効くようになった。「どの行に適用できるか」（包含）と「どの一覧の取得と対か」（等値）を分け、後者は据え置いたうえで、緩めたら落ちるテストを付けた。空状態の文言はサイドバーとプレビューで SidebarEmptyState に共有化した。検証: swift test 1168 件全通過、swiftlint は新規違反ゼロ（既存違反が 312→300 行へ減少）、xcodebuild exit 0。ネストしたリポジトリ・サブモジュール配下は親の git status では正しく答えられないことが実測で判明し、TASK-403 として起票した。
<!-- SECTION:FINAL_SUMMARY:END -->
