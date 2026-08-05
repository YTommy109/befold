---
id: TASK-204
title: 「最近使ったリポジトリ」メニューで worktree を持つリポジトリを階層化する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 02:02'
updated_date: '2026-07-31 14:52'
labels: []
dependencies:
  - TASK-190
priority: medium
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-190 で追加した「最近使ったリポジトリ」メニューは現状フラットな一覧になっている。worktree を持たないリポジトリはそのままの表示でよいが、worktree を持つリポジトリは項目数が増えて見通しが悪くなるため、リポジトリ配下に worktree をぶら下げる階層化（サブメニュー化）されたメニュー構成にしたい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 worktree を持たないリポジトリは従来どおりフラットな1項目として表示される
- [x] #2 worktree を持つリポジトリは親項目化され、配下のサブメニューに各 worktree が表示される
- [x] #3 サブメニューの各項目から該当 worktree を開ける
- [x] #4 worktree の有無判定や一覧取得のロジックにテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. GitRepository に worktree 一覧取得を追加: `func worktrees(forRoot: URL) -> [GitWorktree]`(git worktree list --porcelain / GitCommandRunner 経由)。併せて repositoryLabel の --git-common-dir 比較を `repositoryIdentity(forRoot:) -> (label: String, mainRoot: URL)` に切り出し、repositoryLabel はその薄いラッパにする。
2. RecentRepositoryEntry に optional フィールド `mainRootPath: String?` を追加(前方/後方互換規約に従う)。record(root:label:) を record(root:label:mainRoot:) に拡張。既存 entry の mainRootPath は nil のまま許容し、その場合は rootPath 自身をグループキーにする。
3. WorktreeCatalog(@MainActor) を新設: mainRootPath -> [GitWorktree] のキャッシュ。git 呼び出しは Task.detached で非同期、menuNeedsUpdate は同期読み取りのみ。起動時(AppDelegate、pruneMissingAsync と同じ箇所)と record 時に refresh。
4. RecentRepositoriesMenuController を階層化: 記憶済みエントリを mainRootPath でグループ化し、カタログ上の worktree 数が 2 以上のグループは親項目(submenu 付き・action なしの見出し)にする。それ以外は従来どおりフラット1項目。サブメニューには全 worktree を並べ、記憶が無い worktree は tabGroup nil のエントリを合成して既存 openHandler に流す(= ルートフォルダを開くフォールバック)。
5. 配線: ViewerWindowManager の repositoryLabelResolver を identity 解決に差し替え、AppDelegate/MainMenuBuilder にカタログを配線。必要なら l10n キーを en/ja 両方追加。
6. 検証: 各ステップ TDD(Swift Testing)。GitRepository は実 git worktree add を使う既存テスト様式に合わせる。最後に swift test フルスイート + 手動スモークテスト。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了(commit bef916d, be2d2d6)。検証: swift test フルスイート 966/966 PASS。
構成: (1) GitRepository.worktrees(forRoot:) = git worktree list --porcelain(先頭が本体、失敗時は空配列に縮退) と repositoryIdentity(forRoot:) -> RepositoryIdentity(label + mainRoot)。repositoryLabel はその薄いラッパ。(2) RecentRepositoryEntry.mainRootPath(optional・worktree のときのみ保持)と groupKey(無い旧データは rootPath にフォールバック)。(3) WorktreeCatalog: 本体ルート単位の worktree 一覧キャッシュ。git 呼び出しは Task.detached、menuNeedsUpdate は同期読み取りのみ。起動時(pruneMissingAsync と同じ箇所)とリポジトリ記録時に refresh。(4) RecentRepositoriesMenuController: groupKey でグループ化し、worktree 2件以上なら親項目(action なしの見出し)+サブメニュー、そうでなければ従来どおりフラット。サブメニューには全 worktree を並べ、記憶の無いものは tabGroup nil の合成エントリで既存 openHandler に流す。カタログに無い記憶済みエントリはサブメニュー末尾に残す。
設計判断: WorktreeCatalog は当初「未解決の本体ルートのみ解決する refreshIfNeeded」を持たせたが、アプリ起動中に作成した worktree が階層に反映されないため撤去し、refresh(mainRoots:) に一本化した(記録のたびに解決し直す)。
l10n キーの追加は不要(項目タイトルはディレクトリ名、Clear Menu は既存キー)。設計ドキュメント docs/superpowers/specs/2026-07-30-recent-repositories-menu-design.md に追記済み。
残: 手動スモークテスト(GUI 目視確認) — worktree を持つリポジトリが親+サブメニューになるか、サブメニューから各 worktree を開けるか、worktree の無いリポジトリがフラットのままか。

追加対応(ユーザーの目視確認起点、commit dc8101d): サブメニューの表示をディレクトリ名のみから「ブランチ名 (ディレクトリ名)」に変更。Warp の worktree レイアウトではディレクトリ末尾が etc / etc002 のように機械的で見分けがつかないため。git worktree list --porcelain の branch 行から refs/heads/ を落とした短縮形を取り、GitWorktree.displayName に集約した。detached HEAD はブランチが無いためディレクトリ名だけに縮退する。
検証: swift test フルスイート 969/969 PASS。GUI 目視確認はユーザー実施済み(親+サブメニューへの階層化、サブメニューからの worktree オープン、worktree 無しリポジトリのフラット表示、ブランチ名併記の表示)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「最近使ったリポジトリ」メニューを worktree 単位に階層化した。worktree を持つリポジトリは親項目(見出しのみ・選択しても開かない)とサブメニューに畳み、配下に git worktree list --porcelain で得た全 worktree を「ブランチ名 (ディレクトリ名)」で並べる(未オープンの worktree も含む。記憶が無いものはタブ構成なしのエントリとして既存のルートフォルダを開くフォールバックに乗る)。worktree を持たないリポジトリは従来どおりフラットな1項目。
所属関係は RecentRepositoryEntry.mainRootPath(optional・worktree のときのみ保持)で永続化し、値の無い旧データは自身の rootPath をグループキーにフォールバックする。ラベル生成の途中で判明していた本体ルートを捨てないよう repositoryLabel は repositoryIdentity(label + mainRoot)の薄いラッパにした。git worktree list をメニュー表示直前に同期実行すると subprocess 待ちが UI を止めるため、WorktreeCatalog が本体ルート単位の一覧を Task.detached で解決してキャッシュし、menuNeedsUpdate はキャッシュを同期で読むだけにする(未解決ならフラット表示へ縮退)。キャッシュは起動時とリポジトリ記録時に更新する。
検証: swift test フルスイート 969/969 PASS(worktree 列挙・ブランチ名短縮形・detached フォールバック・カタログのキャッシュ/再解決・メニュー階層化6件を新規追加) + GUI 手動スモークテスト。commit bef916d, be2d2d6, dc8101d。設計ドキュメント docs/superpowers/specs/2026-07-30-recent-repositories-menu-design.md に追記済み。
<!-- SECTION:FINAL_SUMMARY:END -->
