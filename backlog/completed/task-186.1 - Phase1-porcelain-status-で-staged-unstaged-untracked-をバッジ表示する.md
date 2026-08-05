---
id: TASK-186.1
title: 'Phase1: porcelain status で staged/unstaged/untracked をバッジ表示する'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-28 14:22'
updated_date: '2026-08-02 09:16'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
parent_task_id: TASK-186
priority: medium
ordinal: 261400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitStatusReader（git status --porcelain=v2 -z）と GitStatusStore（@MainActor @Observable, ルート単位キャッシュ）を新設し、FileListModel/FileListEntryRow に url→GitFileStatus のバッジ描画を追加する。更新契機は refresh + ウィンドウキー化時。GitCommandRunner の hardeningOptions を通し、非リポジトリ/git不在/reject は status 無しに縮退する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 一時 Git リポジトリで staged/unstaged/untracked が正しく判別される（porcelain v2 パースのユニットテスト）
- [x] #2 GitFileStatus→バッジ文字/色の写像が純粋関数としてテストされ、staged+unstaged 両立時は index 優先になる
- [x] #3 サイドバー行右端にバッジが描画され、ディレクトリ移動・フォーカス復帰で更新される
- [x] #4 非 Git / git 不在 / コマンド reject でバッジ非表示に縮退する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. befold/App/GitFileStatus.swift: ファイル状態の値型（indexChange/worktreeChange/isUntracked、Phase3 用 isBranchModified の器）を追加。
2. befold/App/GitStatusReader.swift: GitStatusReading プロトコル + GitStatusSnapshot（絶対 normalizedPathKey→GitFileStatus と indexFingerprint）+ GitStatusReader（git --no-optional-locks status --porcelain=v2 -z、hardeningOptions 経由）+ porcelain v2 の純関数パーサ。
3. befold/App/GitStatusStore.swift: @MainActor @Observable。ルート解決は注入クロージャ（本番は共有 gitFileIndex.repositoryRoot(forDirectoryAt:)）、git 実行は Task.detached、in-flight Task 辞書で重複を畳む。既定は no-op（常に空）。
4. 表示: FileListModel に gitStatuses: [String: GitFileStatus] を追加。FileListEntryRow に gitStatus: (() -> GitFileStatus?)? = nil を足し、行 body 内で評価（List の遅延評価で再描画が落ちるのを回避）。バッジ写像は befold/Viewer/GitStatusBadge.swift の純関数 + 小さな View。
5. SidebarNavigator: 第3の世代番号 gitStatusGeneration + pendingGitStatusTask を追加し performListing から起動、cancelPendingListing でキャンセル。注入は loadGitStatuses クロージャ（既定 no-op）。
6. 注入経路: AppDelegate.init で GitStatusStore を生成（windowManager.gitFileIndex を使う）→ ViewerWindowManager が保持 → ViewerWindowController → SidebarNavigator へクロージャ。FeatureGate.inProgressFeaturesEnabled はこの注入 1 箇所で分岐。
7. テスト: porcelain パーサ（フィクスチャ）、バッジ写像（index 優先）、GitStatusStore（フェイク Reader）、SidebarNavigator の世代/キャンセル、GitTestRepo に staged/unstaged/untracked ヘルパー追加 + 実 git の統合テスト 1 本。
8. swift build / swift test / swiftformat / swiftlint で検証。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装・検証記録(2026-08-02):

- 設計からの逸脱2点(理由は spec に追記済み): (1) GitFileStatus は OptionSet ではなく構造体(indexChange/worktreeChange/isUntracked/isBranchModified)。バッジ文字が index 側の変更種別そのものなのでフラグ集合から復元できないため。(2) GitStatusSnapshot のキーはルート相対でなく解決済み絶対パス。normalizedPathKey は resolvingSymlinksInPath でファイル IO を伴うため、メイン外で動く Reader 側で変換して FileListEntry.pathKey と同形にする。
- 注入は AppDelegate が windowManager 生成直後に windowManager.gitStatusStore へ差し込む形。共有 gitFileIndex の実体を Manager が握っているため。ViewerWindowManager/Controller の既定はルート解決が常に nil の無効化状態で、テストは git を spawn しない。
- FeatureGate 判定は ViewerWindowController.swift のファイルスコープ関数 makeSidebarGitStatusLoader 1 箇所のみ。stable 昇格時はこの guard を消す(task-187)。
- 検証: swift test 974 件パス。GUI は Debug ビルドを実 worktree で起動し、NSLog(一時計装、除去済み)で「status 22 件がモデルに反映」「変更のある 7 行だけ hit=1 で再描画」を確認、スクリーンショットで AppDelegate.swift に橙の M、未追跡3ファイルに灰の ? が出ることを目視確認。
- swiftformat/swiftlint はベースライン(main 相当)と差分なし。ViewerWindowController の type_body_length を超えかけたため、ゲート判定をファイルスコープ関数へ出して回避した。
- 途中 1 回だけ 974 件中 3 件が失敗する実行があったが、GUI アプリの起動/強制終了と並走していた回。前後の 3 回はクリーンにパスしており再現しない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
GitStatusReader(git --no-optional-locks status --porcelain=v2 -z のパース)と GitStatusStore(@MainActor @Observable、ルート単位キャッシュ + in-flight 畳み込み)を新設し、SidebarNavigator の第3世代タスク経由で FileListModel へ反映、FileListEntryRow の右端に 1 文字バッジ(staged=緑/unstaged=橙/untracked=灰、両立時は index 文字＋橙アクセント)を描画する。露出は FeatureGate 1 箇所で制御。porcelain パース・バッジ写像・Store のキャッシュ/縮退・世代ガードのユニットテストと、実 git を使う統合テスト(サイドバーモデルまでの疎通含む)を追加し swift test 974 件パス。Debug ビルドの実起動でバッジ描画も目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
