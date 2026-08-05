---
id: TASK-186
title: サイドバーに Git ステータスを表示する（フィーチャーゲート対象）
status: Done
assignee: []
created_date: '2026-07-28 14:22'
updated_date: '2026-08-02 10:01'
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
- [x] #1 Git リポジトリ内でサイドバー行の右端に状態バッジが表示される
- [x] #2 staged / unstaged / untracked / branchModified を区別できる
- [x] #3 staged+unstaged 両立時は index 側コードを優先表示しつつ色で worktree 変更も示す
- [x] #4 非 Git・git 不在・status 取得失敗・変更なし ではバッジ非表示に縮退する
- [x] #5 露出は FeatureGate.inProgressFeaturesEnabled で制御される
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

Phase 1〜3 を完了(2026-08-02)。コミット: 65963d2f(Phase1) / 89f2fd71(Phase2) / 71c19c7a(Phase3)。

受け入れ条件の裏取り:
#1 サイドバー行右端のバッジ描画 → Debug ビルドの実起動+スクリーンショット(3 フェーズそれぞれで確認)。
#2 staged/unstaged/untracked/branchModified の区別 → GitStatusReaderTests(porcelain・name-status のフィクスチャ)と実 git の統合テスト。
#3 staged+unstaged 両立時の index 優先＋色でのアクセント → GitStatusBadgeTests(純粋写像)。
#4 非 Git / git 不在 / 取得失敗 / 変更なしでの縮退 → GitStatusStoreTests(unavailable はキャッシュせず空へ縮退・rejected は空スナップショット)と統合テスト。
#5 FeatureGate による露出制御 → 判定は ViewerWindowController.makeSidebarGitStatusLoader の 1 箇所のみ(stable 昇格時は task-187 でこの guard を消す)。

残る手動確認: 撤去(task-187)まではバッジは dev/DEBUG ビルドのみで露出する。

既知の不安定テスト(本タスクとは無関係、2026-08-02 に特定): CLIRequestWireIntegrationTests「全オプション付きの要求が実際の Distributed Notification を通って復元できる」がフルスイート実行時に約 5〜8 回に 1 回失敗する（waitUntil で通知が届かずタイムアウト）。単体実行(--filter)では 6/6 成功するため、フルスイート並行実行時の Distributed Notification 配送遅延が原因と推定。本タスクの差分は CLI/通知経路に一切触れておらず(git diff origin/main で当該テストと BefoldCLI に変更なし)、既存の不安定性。別タスクとして起票するかはユーザー判断待ち。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーのファイル一覧に git 状態バッジを実装した。Phase 1 で porcelain v2 による staged/unstaged/untracked の表示（GitStatusReader / GitStatusStore / バッジ写像 / FeatureGate 制御）、Phase 2 で .git/index 監視と表示中ファイル再読込による自動更新（ポーリングなし・自己励振なし）、Phase 3 で merge-base 差分によるブランチ内変更（青 M）を追加。swift test 990 件パス、swiftformat/swiftlint はベースライン差分なし、各フェーズで Debug ビルドを実起動して描画と自動更新を目視確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
