---
id: TASK-186
title: サイドバーに Git ステータスを表示する（フィーチャーゲート対象）
status: In Progress
assignee: []
created_date: '2026-07-28 14:22'
updated_date: '2026-08-02 08:28'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
priority: medium
ordinal: 263000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Git リポジトリ内のサイドバーファイル一覧で、変更ファイルに状態バッジ（1文字＋色）を表示する。staged(index)/unstaged(worktree)/untracked を区別し、さらに現在ブランチが base ブランチ（デフォルトブランチ自動検出＋merge-base）から変更したコミット済みファイルにもマークする。read-only 表示のみ。FeatureGate.inProgressFeaturesEnabled による露出制御下に置く。段階的に Phase 1〜3 のサブタスクで進める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Git リポジトリ内でサイドバー行の右端に状態バッジが表示される
- [ ] #2 staged / unstaged / untracked / branchModified を区別できる
- [ ] #3 staged+unstaged 両立時は index 側コードを優先表示しつつ色で worktree 変更も示す
- [ ] #4 非 Git・git 不在・status 取得失敗・変更なし ではバッジ非表示に縮退する
- [ ] #5 露出は FeatureGate.inProgressFeaturesEnabled で制御される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前レビュー（2026-08-02）: 既存コードの事前リファクタリングは不要と判断。設計ドキュメント（specs/2026-07-28-sidebar-git-status-design.md）側の前提が実装とずれていたため、以下を修正済み。

1. FeatureGate は task-180 で実装済み・task-184 で先行利用者が撤去済み。blocked-by は解消しており Phase 1 から露出制御を接続してよい（本機能が現時点で唯一の FeatureGate 利用者）。
2. GitStatusStore の踏襲先を GitCommandFileIndex の NSLock/KeyedLock 直列化から WorktreeCatalog パターン（@MainActor + Task.detached + in-flight Task 辞書）へ変更。@MainActor でロックを握って subprocess を待つ形は成立しないため。これにより KeyedLock の抽出も LRU 実装の複製も不要になり、事前リファクタリングが消えた。
3. GitStatusSnapshot のキーを URL から normalizedPathKey(String) へ変更。リポジトリ規約（PathKeyedDictionary / WorktreeCatalog / FileListEntry.pathKey）に合わせないと symlink 別表記で FileListEntry と突合できない。
4. GitRepository.gitDirectory(at:) は private のため直接参照不可。公開済みの indexFingerprint(at:) を使い、Reader が snapshot に fingerprint を同梱して返す形にして Store の依存シームを GitStatusReading 1 本に閉じる。
5. Phase 2 の前提に欠陥。.git/index の mtime は素の作業ツリー編集では変化せず、かつ git status 自体が index を refresh して mtime を動かすため、ポーリング単独だと自己励振ループになる。FileWatcher 起点を第一契機に据え直し、--no-optional-locks を必須とした（task-186.2 の Description/AC も更新済み）。

実装時の確定事項（設計ドキュメントに追記済み）:
- 配置は befold/App/。BefoldKit はサンドボックスの QuickLook 拡張がリンクするため Process spawn コードを置けない。
- ルート解決は共有 gitFileIndex に一本化する（独自に GitRepository を new しない。AppQuickOpenEnvironment に同趣旨の規約あり）。
- 注入経路は AppDelegate.init → ViewerWindowManager → ViewerWindowController → SidebarNavigator へはクロージャ。既定値は no-op。
- List の行ビルダーは遅延評価されるため、status マップを後から差し替えても行が再描画されない。FileListEntryRow に status のデフォルト引数を足し行 body 内で読む（FolderListingView は無変更）。
- 更新契機 1・2 は windowDidBecomeKey → refreshFileList が既にあり追加フック不要。refreshBaseDirectory と同型の第3の世代番号を足す。cancelPendingListing に status タスクのキャンセル追加を忘れない。
- GitCommandOutcome は .rejected はキャッシュ可・.unavailable はキャッシュ不可（既存規約）。
- Phase 1 の API は同期のまま書く。TASK-226 は Phase 2 冒頭で再評価。
- Phase 1 で BefoldTestSupport/GitTestRepo に staged/unstaged/untracked/ブランチ分岐のヘルパーを追加する。

未対応（実装時に判断）: docs/dev/native-app-design.md に Git 系コンポーネントと FeatureGate の記述が一切ない（既存の欠落）。task-186 実装時に追記するのが妥当。
<!-- SECTION:NOTES:END -->
